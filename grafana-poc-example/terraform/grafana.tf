# Zarządzana Grafana. To tu wpinamy oba Prometheusy (AMW-A, AMW-B) i Azure Monitor.
# Parę rzeczy, na które warto uważać:
#   SKU Standard bierzemy nie bez powodu — bez niego nie da się tworzyć Managed
#   Private Endpointów, a to one robią prywatną ścieżkę do AMW-A i self-hosted Prometheusa.
#   Tożsamość SystemAssigned to ta, którą Grafana odpytuje monitoring (role siedzą w rbac.tf).
#   Samej Grafany celowo nie chowamy za prywatną sieć: public_network_access zostaje na true.
#   Prywatyzujemy dane i źródła, nie sam interfejs.

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
