#!/usr/bin/env bash
# deploy-k8s.sh - instalacja self-hosted Prometheusa w AKS, po terraform apply.
# Co robi po kolei:
#   1. Wyciąga z outputs Terraforma dane do remote_write (endpoint DCE-B,
#      immutableId DCR-B, client_id tożsamości kubeleta) i skleja z nich URL.
#   2. Wstrzykuje je (sed) do prometheus-values.yaml w miejsce placeholderów.
#   3. Instaluje Prometheusa Helmem do namespace "monitoring" — metryki lecą do
#      AMW-B przez remote_write (auth: azuread / tożsamość kubeleta z IMDS).
#      Adnotacje usługi tworzą przy okazji Private Link Service (pls-prometheus) do S1.6.
#   4. Wrzuca pod diagnostyczny (netshoot) do prób DNS/łączności (S1.3).
# Potrzebne: kubectl, helm >= 3, jq, zalogowany az CLI.
# Post-apply: install self-hosted Prometheus (feeds AMW-B) and a debug pod.
# Run from the terraform/ directory after `terraform apply`.
# Prerequisites: kubectl, helm >= 3, jq, az CLI authenticated.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TF_DIR="$(dirname "$SCRIPT_DIR")"

# ── Git Bash / MSYS path handling ────────────────────────────────────────────
# Native Windows tools (terraform, az, kubectl, helm) need Windows-style paths
# (C:/...), while MSYS tools (sed, redirection) use the /c/... form.
# `to_native` converts under Git Bash and is a no-op on Linux/macOS.
# Azure resource IDs (/subscriptions/...) must NOT be path-converted, so the
# `az resource show --ids` calls below are prefixed with MSYS_NO_PATHCONV=1
# (a harmless unused env var off Windows).
if command -v cygpath >/dev/null 2>&1; then
  to_native() { cygpath -m "$1"; }
else
  to_native() { printf '%s' "$1"; }
fi
TF_DIR_WIN="$(to_native "$TF_DIR")"

# ── 1. Pull values from terraform outputs ────────────────────────────────────
AKS_NAME=$(terraform -chdir="$TF_DIR_WIN" output -raw aks_name)
RG=$(terraform -chdir="$TF_DIR_WIN" output -raw resource_group_name)
DCE_B_ID=$(terraform -chdir="$TF_DIR_WIN" output -raw dce_b_id)
DCR_B_ID=$(terraform -chdir="$TF_DIR_WIN" output -raw dcr_b_id)
KUBELET_CLIENT_ID=$(terraform -chdir="$TF_DIR_WIN" output -raw aks_kubelet_client_id)

API="2023-03-11"  # DCE/DCR API version that reliably exposes metricsIngestion + immutableId

# DCE-B metrics ingestion endpoint (where prometheus POSTs remote_write data).
DCE_B_METRICS=$(MSYS_NO_PATHCONV=1 az resource show --ids "$DCE_B_ID" --api-version "$API" \
  --query "properties.metricsIngestion.endpoint" -o tsv)

# DCR-B immutable ID (embedded in the remote_write URL path).
DCR_B_IMMUTABLE=$(MSYS_NO_PATHCONV=1 az resource show --ids "$DCR_B_ID" --api-version "$API" \
  --query "properties.immutableId" -o tsv)

# Uwaga: `set -e` NIE łapie samej pustej zmiennej (az zwraca 0 przy polach null).
# Pusta wartość skleiłaby zły URL remote_write, a wtedy AMW-B nigdy nie przyjmie metryk.
# Guards: `set -e` does NOT catch a var that is merely empty (az exits 0 on null fields).
# An empty value here would silently build a malformed remote_write URL → AMW-B never ingests.
[ -n "$DCE_B_METRICS" ]    || { echo "FATAL: DCE-B metricsIngestion.endpoint is empty (api-version $API?)"; exit 1; }
[ -n "$DCR_B_IMMUTABLE" ]  || { echo "FATAL: DCR-B immutableId is empty"; exit 1; }
[ -n "$KUBELET_CLIENT_ID" ] || { echo "FATAL: aks_kubelet_client_id output is empty"; exit 1; }

REMOTE_WRITE_URL="${DCE_B_METRICS}/dataCollectionRules/${DCR_B_IMMUTABLE}/streams/Microsoft-PrometheusMetrics/api/v1/write?api-version=2023-04-24"

echo "AKS:               $AKS_NAME"
echo "DCE-B endpoint:    $DCE_B_METRICS"
echo "DCR-B immutableId: $DCR_B_IMMUTABLE"
echo "kubelet client_id: $KUBELET_CLIENT_ID"
echo "remote_write URL:  $REMOTE_WRITE_URL"

# ── 2. Kubeconfig ─────────────────────────────────────────────────────────────
az aks get-credentials --resource-group "$RG" --name "$AKS_NAME" --overwrite-existing

# ── 3. Prometheus (prometheus-community/prometheus, not kube-prometheus-stack) ─
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts 2>/dev/null || true
helm repo update prometheus-community

kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -

# Patch the placeholder URL + kubelet client_id into the values file.
# sed (MSYS) reads/writes with /c/... paths; helm (native) gets the C:/... form.
PATCHED_VALUES="$(mktemp)"
trap 'rm -f "$PATCHED_VALUES"' EXIT
sed -e "s|PLACEHOLDER_REMOTE_WRITE_URL|${REMOTE_WRITE_URL}|g" \
    -e "s|PLACEHOLDER_KUBELET_CLIENT_ID|${KUBELET_CLIENT_ID}|g" \
  "$SCRIPT_DIR/prometheus-values.yaml" > "$PATCHED_VALUES"

helm upgrade --install prometheus prometheus-community/prometheus \
  --namespace monitoring \
  --values "$(to_native "$PATCHED_VALUES")" \
  --wait --timeout 5m

echo "Prometheus installed. Verify metrics ingestion:"
echo "  kubectl -n monitoring get pods"
echo "  kubectl -n monitoring logs -l app=prometheus,component=server --tail=20"

# ── 4. Debug pod (dig + curl for DNS white-box probes, S1.3) ─────────────────
kubectl apply -f "$(to_native "$SCRIPT_DIR/debug-pod.yaml")"
echo "Debug pod applied. Shell in: kubectl exec -it debug -- bash"

echo ""
echo "Next: add both AMW query endpoints as Prometheus data sources in Grafana (MI auth) → S1.0 baseline."
