<#
.SYNOPSIS
  configure-grafana.ps1 - konfiguracja "warstwy danych" Grafany, odpalana po apply.

.DESCRIPTION
  Terraform nie ogarnie tu wnętrza Grafany (Azure Managed Grafana wyłącza konta
  usługowe, więc provider Grafany nie ma jak się zalogować). Dlatego lecimy przez
  `az grafana` (na Twoim `az login`) i tworzymy 4 źródła danych:
    AMW-A, AMW-B      : Prometheus, uwierzytelnianie tożsamością zarządzaną (MSI)
    AzMon-CurrentUser : Azure Monitor (zalogowany user + zapasowo SP)
    OSS-Prometheus-PLS: prywatna ścieżka do self-hosted Prometheusa przez MPE->PLS (S1.6)
  Skrypt jest idempotentny - najpierw kasuje źródło o tej samej nazwie, potem tworzy.
  Kolejność: `terraform apply` -> k8s/deploy-k8s.ps1 -> ten skrypt.

.EXAMPLE
  ./configure-grafana.ps1
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$TfDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# Pomocnik: terraform output -raw, z opcjonalną wartością domyślną.
function Get-TfOutput {
    param(
        [Parameter(Mandatory)][string]$Name,
        [string]$Default,
        [switch]$HasDefault
    )
    $val = terraform -chdir="$TfDir" output -raw $Name 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($val)) {
        if ($HasDefault) { return $Default }
        throw "FATAL: terraform output '$Name' is empty"
    }
    return $val
}

$Graf   = Get-TfOutput -Name grafana_name -Default 'grafana-xyz-lab' -HasDefault
$Rg     = Get-TfOutput -Name resource_group_name
$EpA    = Get-TfOutput -Name amw_a_query_endpoint
$EpB    = Get-TfOutput -Name amw_b_query_endpoint
$Sub    = az account show --query id -o tsv
$Ten    = az account show --query tenantId -o tsv
$Cid    = Get-TfOutput -Name app_reg_client_id
$Sec    = Get-TfOutput -Name app_reg_secret
$NodeRg = Get-TfOutput -Name aks_node_resource_group

# arbitrary; Grafana resolves it internally to the MPE IP
$OssDomain = if ($env:OSS_DOMAIN) { $env:OSS_DOMAIN } else { 'prometheus.xyzlab.net' }

# Pomocnik: kasuje istniejące źródło i tworzy je od nowa (stąd idempotencja).
function Invoke-DsRecreate {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Definition
    )
    # delete: błędy ignorujemy (kod != 0 nie rzuca dla natywnych narzędzi)
    az grafana data-source delete -n $Graf -g $Rg --data-source $Name *> $null
    az grafana data-source create -n $Graf -g $Rg --definition $Definition --query name -o tsv
}

Write-Host "== AMW-A / AMW-B (managed Prometheus, managed-identity auth) =="
$defAmwA = [ordered]@{
    name = 'AMW-A'; type = 'prometheus'; access = 'proxy'; url = $EpA
    jsonData = [ordered]@{ httpMethod = 'POST'; azureCredentials = [ordered]@{ authType = 'msi' } }
} | ConvertTo-Json -Compress -Depth 10
Invoke-DsRecreate -Name 'AMW-A' -Definition $defAmwA

$defAmwB = [ordered]@{
    name = 'AMW-B'; type = 'prometheus'; access = 'proxy'; url = $EpB
    jsonData = [ordered]@{ httpMethod = 'POST'; azureCredentials = [ordered]@{ authType = 'msi' } }
} | ConvertTo-Json -Compress -Depth 10
Invoke-DsRecreate -Name 'AMW-B' -Definition $defAmwB

Write-Host "== AzMon-CurrentUser (Azure Monitor, Current User + fallback service credentials) =="
$defAzMon = [ordered]@{
    name = 'AzMon-CurrentUser'; type = 'grafana-azure-monitor-datasource'; access = 'proxy'
    jsonData = [ordered]@{
        azureAuthType    = 'currentuser'
        subscriptionId   = $Sub
        azureCredentials = [ordered]@{ authType = 'currentuser' }
        fallbackCredentials = [ordered]@{
            authType = 'clientsecret'; azureCloud = 'AzureCloud'; tenantId = $Ten; clientId = $Cid
        }
    }
    secureJsonData = [ordered]@{ fallbackClientSecret = $Sec }
} | ConvertTo-Json -Compress -Depth 10
Invoke-DsRecreate -Name 'AzMon-CurrentUser' -Definition $defAzMon

Write-Host "== S1.6: Grafana MPE -> self-hosted Prometheus PLS, approve, refresh =="
$PlsId = az network private-link-service show -g $NodeRg -n pls-prometheus --query id -o tsv 2>$null
if ($LASTEXITCODE -ne 0) { $PlsId = $null }

if (-not [string]::IsNullOrWhiteSpace($PlsId)) {
    az grafana managed-private-endpoint create --workspace-name $Graf -g $Rg -n mpe-oss-prometheus `
        --private-link-resource-id $PlsId --private-link-service-url $OssDomain `
        --private-link-resource-region westeurope *> $null
    if ($LASTEXITCODE -ne 0) { Write-Host "  (MPE may already exist)" }

    $Conn = az network private-endpoint-connection list --id $PlsId `
        --query "[?properties.privateLinkServiceConnectionState.status=='Pending'].id | [0]" -o tsv 2>$null
    if ($LASTEXITCODE -ne 0) { $Conn = $null }
    if (-not [string]::IsNullOrWhiteSpace($Conn)) {
        az network private-endpoint-connection approve --id $Conn --description "lab S1.6" *> $null
    }

    az grafana managed-private-endpoint refresh --workspace-name $Graf -g $Rg *> $null

    $defOss = [ordered]@{
        name = 'OSS-Prometheus-PLS'; type = 'prometheus'; access = 'proxy'; url = "http://$OssDomain"
        jsonData = [ordered]@{ httpMethod = 'POST' }
    } | ConvertTo-Json -Compress -Depth 10
    Invoke-DsRecreate -Name 'OSS-Prometheus-PLS' -Definition $defOss
}
else {
    Write-Host "  PLS 'pls-prometheus' not found yet — run k8s/deploy-k8s.ps1 first (it creates the PLS via service annotations)."
}

Write-Host "Done. Data sources:"
az grafana data-source list -n $Graf -g $Rg --query "[].name" -o tsv
