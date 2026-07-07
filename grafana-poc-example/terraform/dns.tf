# Explicit private DNS zone for the AMW Prometheus privatelink subdomain.
# Explicit (not auto-created by PE) ensures clean terraform destroy with no orphans.
resource "azurerm_private_dns_zone" "prometheus" {
  name                = "privatelink.${var.location}.prometheus.monitor.azure.com"
  resource_group_name = azurerm_resource_group.rg.name
  tags                = local.tags
}

# Link zone into vnet-lab so AKS debug pod can resolve the private A-record for AMW-A.
resource "azurerm_private_dns_zone_virtual_network_link" "prometheus_vnet_lab" {
  name                  = "link-vnet-lab"
  resource_group_name   = azurerm_resource_group.rg.name
  private_dns_zone_name = azurerm_private_dns_zone.prometheus.name
  virtual_network_id    = azurerm_virtual_network.vnet_lab.id
  registration_enabled  = false
  tags                  = local.tags
}

# PE → AMW-A in snet-pe (vnet-lab), WITH a private_dns_zone_group so Azure auto-manages
# the A-record for AMW-A in our explicit zone above.
# NOTE: do NOT create a PE → AMW-B here (see infra-plan critical note: DNS-off on AMW-B PE
# is what makes S1.3 NXDOMAIN proof work; that PE is a CLI step tagged lab=cli).
resource "azurerm_private_endpoint" "pe_amw_a" {
  name                = "pe-amw-a"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
  subnet_id           = azurerm_subnet.snet_pe.id

  private_service_connection {
    name                           = "psc-amw-a"
    private_connection_resource_id = azurerm_monitor_workspace.amw_a.id
    subresource_names              = ["prometheusMetrics"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "pdzg-amw-a"
    private_dns_zone_ids = [azurerm_private_dns_zone.prometheus.id]
  }

  tags = local.tags
}
