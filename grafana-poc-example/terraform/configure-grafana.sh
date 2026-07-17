#!/usr/bin/env bash
# configure-grafana.sh - konfiguracja "warstwy danych" Grafany, odpalana po apply.
# Terraform nie ogarnie tu wnętrza Grafany (Azure Managed Grafana wyłącza konta
# usługowe, więc provider Grafany nie ma jak się zalogować). Dlatego lecimy przez
# `az grafana` (na Twoim `az login`) i tworzymy 4 źródła danych:
#   AMW-A, AMW-B      : Prometheus, uwierzytelnianie tożsamością zarządzaną (MSI)
#   AzMon-CurrentUser : Azure Monitor (zalogowany user; BEZ fallbacku SP — środowisko
#                       nie ma uprawnień do tworzenia app registration, patrz identity.tf)
#   OSS-Prometheus-PLS: prywatna ścieżka do self-hosted Prometheusa przez MPE→PLS (S1.6)
# Skrypt jest idempotentny - najpierw kasuje źródło o tej samej nazwie, potem tworzy.
# Kolejność: `terraform apply` -> k8s/deploy-k8s.sh -> ten skrypt.
# Codifies the Grafana data-plane config that Terraform can't manage here (Azure Managed Grafana
# disables service accounts, so the Grafana TF provider can't authenticate). Uses `az grafana`
# (your az login). Run AFTER `terraform apply` and `k8s/deploy-k8s.sh`.
#
# Creates the 4 data sources used by the lab and wires the OSS-Prometheus private path (S1.6).
# Idempotent: deletes a same-named data source before recreating.
#
# Usage: ./configure-grafana.sh
set -euo pipefail
TF_DIR="$(cd "$(dirname "$0")" && pwd)"
GRAF=$(terraform -chdir="$TF_DIR" output -raw grafana_name 2>/dev/null || echo grafana-xyz-lab)
RG=$(terraform -chdir="$TF_DIR" output -raw resource_group_name)
EP_A=$(terraform -chdir="$TF_DIR" output -raw amw_a_query_endpoint)
EP_B=$(terraform -chdir="$TF_DIR" output -raw amw_b_query_endpoint)
SUB=$(az account show --query id -o tsv)
NODE_RG=$(terraform -chdir="$TF_DIR" output -raw aks_node_resource_group)
OSS_DOMAIN="${OSS_DOMAIN:-prometheus.xyzlab.net}"   # arbitrary; Grafana resolves it internally to the MPE IP

# Pomocnik: kasuje istniejące źródło i tworzy je od nowa (stąd idempotencja).
# $1 = nazwa źródła, $2 = definicja JSON
ds_recreate() { # $1=name  $2=definition-json
  az grafana data-source delete -n "$GRAF" -g "$RG" --data-source "$1" >/dev/null 2>&1 || true
  az grafana data-source create -n "$GRAF" -g "$RG" --definition "$2" --query name -o tsv
}

echo "== AMW-A / AMW-B (managed Prometheus, managed-identity auth) =="
ds_recreate AMW-A "{\"name\":\"AMW-A\",\"type\":\"prometheus\",\"access\":\"proxy\",\"url\":\"$EP_A\",\"jsonData\":{\"httpMethod\":\"POST\",\"azureCredentials\":{\"authType\":\"msi\"}}}"
ds_recreate AMW-B "{\"name\":\"AMW-B\",\"type\":\"prometheus\",\"access\":\"proxy\",\"url\":\"$EP_B\",\"jsonData\":{\"httpMethod\":\"POST\",\"azureCredentials\":{\"authType\":\"msi\"}}}"

echo "== AzMon-CurrentUser (Azure Monitor, Current User; brak fallback SP — patrz identity.tf) =="
ds_recreate AzMon-CurrentUser "{\"name\":\"AzMon-CurrentUser\",\"type\":\"grafana-azure-monitor-datasource\",\"access\":\"proxy\",\"jsonData\":{\"azureAuthType\":\"currentuser\",\"subscriptionId\":\"$SUB\",\"azureCredentials\":{\"authType\":\"currentuser\"}}}"

echo "== S1.6: Grafana MPE -> self-hosted Prometheus PLS, approve, refresh =="
PLS_ID=$(az network private-link-service show -g "$NODE_RG" -n pls-prometheus --query id -o tsv 2>/dev/null || true)
if [ -n "$PLS_ID" ]; then
  az grafana managed-private-endpoint create --workspace-name "$GRAF" -g "$RG" -n mpe-oss-prometheus \
    --private-link-resource-id "$PLS_ID" --private-link-service-url "$OSS_DOMAIN" \
    --private-link-resource-region westeurope >/dev/null 2>&1 || echo "  (MPE may already exist)"
  CONN=$(az network private-endpoint-connection list --id "$PLS_ID" --query "[?properties.privateLinkServiceConnectionState.status=='Pending'].id | [0]" -o tsv 2>/dev/null || true)
  [ -n "$CONN" ] && az network private-endpoint-connection approve --id "$CONN" --description "lab S1.6" >/dev/null 2>&1 || true
  az grafana managed-private-endpoint refresh --workspace-name "$GRAF" -g "$RG" >/dev/null 2>&1 || true
  ds_recreate OSS-Prometheus-PLS "{\"name\":\"OSS-Prometheus-PLS\",\"type\":\"prometheus\",\"access\":\"proxy\",\"url\":\"http://$OSS_DOMAIN\",\"jsonData\":{\"httpMethod\":\"POST\"}}"
else
  echo "  PLS 'pls-prometheus' not found yet — run k8s/deploy-k8s.sh first (it creates the PLS via service annotations)."
fi

echo "Done. Data sources:"; az grafana data-source list -n "$GRAF" -g "$RG" --query "[].name" -o tsv