# Dwie osobne sieci wirtualne pod scenariusze z prywatną łącznością:
#
#   vnet-lab (10.10.0.0/16) - główna sieć labu:
#       snet-aks (10.10.0.0/24): węzły AKS i miejsce na Private Link Service
#       snet-pe  (10.10.1.0/24): Private Endpoint do AMW-A
#
#   vnet-b (10.20.0.0/16) - "poletko" pod PE do AMW-B tworzony ręcznie z az CLI,
#       na którym pokazujemy rozjeżdżający się DNS (NXDOMAIN).

# vnet-lab (10.10.0.0/16): węzły AKS + Private Endpoint do AMW-A
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
  # Bez tego Private Link Service, który AKS stawia w kroku S1.6, nie wrzuci tu swoich adresów NAT.
  # Required so the AKS-managed Private Link Service (S1.6) can place its NAT IPs here.
  private_link_service_network_policies_enabled = false
}

resource "azurerm_subnet" "snet_pe" {
  name                 = "snet-pe"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet_lab.name
  address_prefixes     = ["10.10.1.0/24"]
}

# vnet-b (10.20.0.0/16): pod PE→AMW-B tworzony ręcznie z CLI (S1.2b)
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
