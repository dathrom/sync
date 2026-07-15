#!/usr/bin/env bash
# teardown.sh - sprząta zasoby robione ręcznie, PRZED terraform destroy.
# Scenariusze S1.x dorzucają rzeczy poza Terraformem (przez az CLI): dodatkowe
# Private Endpointy, Grafana Managed Private Endpoints, grupy reguł Prometheus,
# prywatyzację AMW. Te "obce" zasoby potrafią zablokować destroy (np. PE trzymający
# podsieć = 409). Skrypt je kasuje i przywraca publiczny dostęp do AMW, żeby destroy
# przeszedł gładko.
#
# ODPAL PRZED `terraform destroy`, jeśli robiłeś jakikolwiek krok S1.x z CLI.
# Zasoby zarządzane Terraformem (PE→AMW-A, strefa DNS) zostawiamy dla destroy.
# Removes the CLI-created "variables under test" so `terraform destroy` can complete.
# MUST run BEFORE `terraform destroy` whenever any S1.x CLI step has been executed:
# a leftover PE in vnet-b's subnet makes destroy fail (409, subnet in use), and a leftover
# Grafana managed private endpoint slows/blocks Grafana deletion.
#
# Usage: ./teardown.sh <resource-group> <grafana-name>
# Then:  terraform destroy
set -uo pipefail
RG="${1:?usage: teardown.sh <resource-group> <grafana-name>}"
GRAFANA="${2:?usage: teardown.sh <resource-group> <grafana-name>}"
rc=0

echo "== 1. Delete Grafana managed private endpoints (S1.1 / S1.3b / S1.5) =="
for mpe in $(az grafana managed-private-endpoint list -g "$RG" --workspace-name "$GRAFANA" --query "[].name" -o tsv 2>/dev/null); do
  echo "  deleting Grafana MPE $mpe"
  az grafana managed-private-endpoint delete -g "$RG" --workspace-name "$GRAFANA" --name "$mpe" -y || rc=1
done
az grafana managed-private-endpoint refresh -g "$RG" --workspace-name "$GRAFANA" >/dev/null 2>&1 || true

echo "== 2. Delete CLI-created private endpoints (tagged lab=cli, e.g. PE->AMW-B in vnet-b) =="
# Only lab=cli — never the Terraform-managed PE->AMW-A.
for pe in $(az network private-endpoint list -g "$RG" --query "[?tags.lab=='cli'].name" -o tsv 2>/dev/null); do
  echo "  deleting CLI PE $pe"
  az network private-endpoint delete -g "$RG" -n "$pe" || rc=1
done

echo "== 3. Delete CLI-created Prometheus rule groups (S2.4/S2.5) — else they block RG destroy =="
for rg_rule in $(az resource list -g "$RG" --resource-type Microsoft.AlertsManagement/prometheusRuleGroups --query "[].name" -o tsv 2>/dev/null); do
  echo "  deleting rule group $rg_rule"
  az resource delete -g "$RG" -n "$rg_rule" --resource-type Microsoft.AlertsManagement/prometheusRuleGroups --api-version 2023-03-01 || rc=1
done

echo "== 4. Re-enable public access on any AMW left private (S1.4) =="
for id in $(az resource list -g "$RG" --resource-type Microsoft.Monitor/accounts --query "[].id" -o tsv 2>/dev/null); do
  az resource update --ids "$id" --api-version 2023-04-03 --set properties.publicNetworkAccess=Enabled >/dev/null 2>&1 || true
done

echo "== 5. Verify nothing CLI-created remains =="
remaining_pe=$(az network private-endpoint list -g "$RG" --query "length([?tags.lab=='cli'])" -o tsv 2>/dev/null || echo 0)
remaining_mpe=$(az grafana managed-private-endpoint list -g "$RG" --workspace-name "$GRAFANA" --query "length(@)" -o tsv 2>/dev/null || echo 0)
if [ "${remaining_pe:-0}" != "0" ] || [ "${remaining_mpe:-0}" != "0" ]; then
  echo "WARNING: ${remaining_pe} CLI PE(s) and ${remaining_mpe} Grafana MPE(s) still present — re-run before destroy."
  rc=1
fi

echo "Done (rc=$rc). Terraform-managed PE->AMW-A and the private DNS zone are left to 'terraform destroy'."
exit $rc
