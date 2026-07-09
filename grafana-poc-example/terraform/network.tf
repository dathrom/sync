# =============================================================================
# network.tf — Sieci wirtualne i podsieci
# -----------------------------------------------------------------------------
# Dwie oddzielne sieci wirtualne obsługujące scenariusze prywatnej łączności:
#
#   vnet-lab (10.10.0.0/16) — główna sieć laboratorium:
#       snet-aks (10.10.0.0/24) : węzły AKS + miejsce na Private Link Service
#       snet-pe  (10.10.1.0/24) : Private Endpoint do AMW-A (patrz dns.tf)
#
#   vnet-b   (10.20.0.0/16) — sieć pomocnicza, "poletko" pod ręcznie tworzony
#       (przez az CLI) Private Endpoint do AMW-B — służy do demonstracji
#       rozwiązywania DNS (scenariusz NXDOMAIN).
# =============================================================================

# ── vnet-lab (10.10.0.0/16) — węzły AKS + Private Endpoint do AMW-A ────────────
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
  # Wymagane, aby usługa Private Link Service tworzona przez AKS (krok S1.6)
  # mogła umieścić w tej podsieci swoje adresy NAT.
  # Required so the AKS-managed Private Link Service (S1.6) can place its NAT IPs here.
  private_link_service_network_policies_enabled = false
}

resource "azurerm_subnet" "snet_pe" {
  name                 = "snet-pe"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet_lab.name
  address_prefixes     = ["10.10.1.0/24"]
}

# ── vnet-b (10.20.0.0/16) — miejsce na tworzony przez CLI PE→AMW-B (S1.2b) ────
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
