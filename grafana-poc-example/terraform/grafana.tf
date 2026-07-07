resource "azurerm_dashboard_grafana" "grafana" {
  name                          = "grafana-pzu-lab"
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
