# =============================================================================
# grafana.tf — Azure Managed Grafana (warstwa wizualizacji)
# -----------------------------------------------------------------------------
# Zarządzana usługa Grafana, do której podpinamy oba źródła Prometheus (AMW-A,
# AMW-B) oraz Azure Monitor. Ważne decyzje projektowe:
#   - SKU "Standard": wymagane, aby móc tworzyć Managed Private Endpoints (MPE),
#     czyli prywatną ścieżkę Grafana -> AMW-A / self-hosted Prometheus.
#   - Tożsamość SystemAssigned: to za jej pomocą Grafana odpytuje przestrzenie
#     monitoringu (role nadawane w rbac.tf).
#   - public_network_access_enabled = true: samą Grafanę zostawiamy publiczną
#     (prywatyzujemy dane/źródła, nie interfejs Grafany).
# =============================================================================

resource "azurerm_dashboard_grafana" "grafana" {
  name                          = "grafana-xyz-lab"
  resource_group_name           = azurerm_resource_group.rg.name
  location                      = var.location
  sku                           = "Standard" # Standard required for Managed Private Endpoints (F2).
  grafana_major_version         = "12"       # Current Azure Managed Grafana GA (11 EOL 2026-06-15; azurerm 4.79 allows 11/12).
  zone_redundancy_enabled       = false
  public_network_access_enabled = true # NOT privatising Grafana itself.

  identity {
    type = "SystemAssigned"
  }

  tags = local.tags
}
