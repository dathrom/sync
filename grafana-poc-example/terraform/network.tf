# ── vnet-lab (10.10.0.0/16) — AKS nodes + private endpoint for AMW-A ──────────

resource "azurerm_virtual_network" "vnet_lab" {
  name                = "vnet-lab"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
  address_space       = ["10.10.0.0/16"]
  tags                = local.tags
}

resource "azurerm_subnet" "snet_aks" {
  name                 = "snet-aks"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet_lab.name
  address_prefixes     = ["10.10.0.0/24"]
  # Required so the AKS-managed Private Link Service (S1.6) can place its NAT IPs here.
  private_link_service_network_policies_enabled = false
}

resource "azurerm_subnet" "snet_pe" {
  name                 = "snet-pe"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet_lab.name
  address_prefixes     = ["10.10.1.0/24"]
}

# ── vnet-b (10.20.0.0/16) — placeholder for the CLI-created PE→AMW-B (S1.2b) ─

resource "azurerm_virtual_network" "vnet_b" {
  name                = "vnet-b"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
  address_space       = ["10.20.0.0/16"]
  tags                = local.tags
}

resource "azurerm_subnet" "snet_pe_b" {
  name                 = "snet-pe"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet_b.name
  address_prefixes     = ["10.20.1.0/24"]
}
