<#
.SYNOPSIS
  deploy-k8s.ps1 - instalacja self-hosted Prometheusa w AKS, po terraform apply.

.DESCRIPTION
  Co robi po kolei:
    1. Wyciaga z outputs Terraforma dane do remote_write (endpoint DCE-B,
       immutableId DCR-B, client_id tozsamosci kubeleta) i skleja z nich URL.
    2. Wstrzykuje je do prometheus-values.yaml w miejsce placeholderow.
    3. Instaluje Prometheusa Helmem do namespace "monitoring" - metryki leca do
       AMW-B przez remote_write (auth: azuread / tozsamosc kubeleta z IMDS).
       Adnotacje uslugi tworza przy okazji Private Link Service (pls-prometheus) do S1.6.
    4. Wrzuca pod diagnostyczny (netshoot) do prob DNS/lacznosci (S1.3).
  Potrzebne: kubectl, helm >= 3, jq, zalogowany az CLI.
  Uruchamiac z katalogu terraform/ po `terraform apply`.

.PARAMETER KubectlPath
  Sciezka do kubectl (np. C:\k8s\kubectl.exe). Jesli pominieta, skrypt zapyta
  interaktywnie; jesli i wtedy nic nie podasz - uzyje "kubectl" z PATH.
#>

[CmdletBinding()]
param(
    [string]$KubectlPath
)

$ErrorActionPreference = 'Stop'

# Zatrzymaj skrypt, jesli ostatnie wywolanie zewnetrznego narzedzia zwrocilo blad.
function Assert-ExitCode {
    param([string]$What)
    if ($LASTEXITCODE -ne 0) {
        throw "FATAL: '$What' zakonczone kodem $LASTEXITCODE"
    }
}

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$TfDir     = Split-Path -Parent $ScriptDir

# -- 0. Sciezka do kubectl -----------------------------------------------------
# Priorytet: parametr -KubectlPath > pytanie interaktywne > "kubectl" z PATH.
# Jesli podasz pelna sciezke (np. C:\k8s\kubectl.exe), wszystkie wywolania robimy
# ta pelna sciezka (operator wywolania &).
if (-not $KubectlPath) {
    $KubectlPath = Read-Host "Podaj sciezke do kubectl (Enter = wez z PATH)"
}
if ([string]::IsNullOrWhiteSpace($KubectlPath)) {
    $KubectlPath = "kubectl"
}
Write-Host "kubectl:           $KubectlPath"

# -- 1. Pull values from terraform outputs ------------------------------------
$AksName        = terraform -chdir="$TfDir" output -raw aks_name;                Assert-ExitCode "terraform output aks_name"
$Rg             = terraform -chdir="$TfDir" output -raw resource_group_name;     Assert-ExitCode "terraform output resource_group_name"
$DceBId         = terraform -chdir="$TfDir" output -raw dce_b_id;                Assert-ExitCode "terraform output dce_b_id"
$DcrBId         = terraform -chdir="$TfDir" output -raw dcr_b_id;                Assert-ExitCode "terraform output dcr_b_id"
$KubeletClientId = terraform -chdir="$TfDir" output -raw aks_kubelet_client_id;  Assert-ExitCode "terraform output aks_kubelet_client_id"

# Pin the subscription to the one Terraform actually deployed into - it's embedded
# in every resource ID (/subscriptions/<id>/...). Passing it explicitly to az stops
# it from falling back to the SPN's default subscription context (which may differ).
$SubscriptionId = ($DceBId -replace '^/subscriptions/', '') -replace '/.*$', ''
if ([string]::IsNullOrWhiteSpace($SubscriptionId)) {
    throw "FATAL: could not parse subscription from dce_b_id: $DceBId"
}

$Api = "2023-03-11"  # DCE/DCR API version that reliably exposes metricsIngestion + immutableId

# DCE-B metrics ingestion endpoint (where prometheus POSTs remote_write data).
$DceBMetrics = az resource show --ids "$DceBId" --api-version "$Api" `
    --subscription "$SubscriptionId" `
    --query "properties.metricsIngestion.endpoint" -o tsv
Assert-ExitCode "az resource show (DCE-B)"

# DCR-B immutable ID (embedded in the remote_write URL path).
$DcrBImmutable = az resource show --ids "$DcrBId" --api-version "$Api" `
    --subscription "$SubscriptionId" `
    --query "properties.immutableId" -o tsv
Assert-ExitCode "az resource show (DCR-B)"

# Uwaga: az zwraca 0 przy polach null -> pusta wartosc skleilaby zly URL remote_write,
# a wtedy AMW-B nigdy nie przyjmie metryk. Dlatego jawne guardy ponizej.
if ([string]::IsNullOrWhiteSpace($DceBMetrics))     { throw "FATAL: DCE-B metricsIngestion.endpoint is empty (api-version $Api?)" }
if ([string]::IsNullOrWhiteSpace($DcrBImmutable))   { throw "FATAL: DCR-B immutableId is empty" }
if ([string]::IsNullOrWhiteSpace($KubeletClientId)) { throw "FATAL: aks_kubelet_client_id output is empty" }

$RemoteWriteUrl = "$DceBMetrics/dataCollectionRules/$DcrBImmutable/streams/Microsoft-PrometheusMetrics/api/v1/write?api-version=2023-04-24"

Write-Host "subscription:      $SubscriptionId"
Write-Host "AKS:               $AksName"
Write-Host "DCE-B endpoint:    $DceBMetrics"
Write-Host "DCR-B immutableId: $DcrBImmutable"
Write-Host "kubelet client_id: $KubeletClientId"
Write-Host "remote_write URL:  $RemoteWriteUrl"

# -- 2. Kubeconfig -------------------------------------------------------------
az aks get-credentials --subscription "$SubscriptionId" `
    --resource-group "$Rg" --name "$AksName" --overwrite-existing
Assert-ExitCode "az aks get-credentials"

# -- 3. Prometheus (prometheus-community/prometheus, not kube-prometheus-stack) -
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts 2>$null
helm repo update prometheus-community
Assert-ExitCode "helm repo update"

# --validate=false pomija pobieranie schematu OpenAPI z serwera API (to pobranie
# potrafi lecac przez korporacyjne proxy z inspekcja TLS -> x509 "unknown authority").
& $KubectlPath create namespace monitoring --dry-run=client -o yaml | & $KubectlPath apply --validate=false -f -
Assert-ExitCode "kubectl apply namespace monitoring"

# Patch the placeholder URL + kubelet client_id into the values file.
$PatchedValues = [System.IO.Path]::GetTempFileName()
try {
    (Get-Content -Raw "$ScriptDir\prometheus-values.yaml") `
        -replace 'PLACEHOLDER_REMOTE_WRITE_URL', $RemoteWriteUrl `
        -replace 'PLACEHOLDER_KUBELET_CLIENT_ID', $KubeletClientId |
        Set-Content -NoNewline -Encoding utf8 $PatchedValues

    helm upgrade --install prometheus prometheus-community/prometheus `
        --namespace monitoring `
        --values "$PatchedValues" `
        --wait --timeout 5m
    Assert-ExitCode "helm upgrade --install prometheus"
}
finally {
    Remove-Item -Force -ErrorAction SilentlyContinue $PatchedValues
}

Write-Host "Prometheus installed. Verify metrics ingestion:"
Write-Host "  $KubectlPath -n monitoring get pods"
Write-Host "  $KubectlPath -n monitoring logs -l app=prometheus,component=server --tail=20"

# -- 4. Debug pod (dig + curl for DNS white-box probes, S1.3) ------------------
& $KubectlPath apply --validate=false -f "$ScriptDir\debug-pod.yaml"
Assert-ExitCode "kubectl apply debug-pod"
Write-Host "Debug pod applied. Shell in: $KubectlPath exec -it debug -- bash"

Write-Host ""
Write-Host "Next: add both AMW query endpoints as Prometheus data sources in Grafana (MI auth) -> S1.0 baseline."
