# =============================================================================
# main.tf — Grupa zasobów (fundament całego wdrożenia)
# -----------------------------------------------------------------------------
# Wszystkie pozostałe zasoby (AKS, Grafana, monitoring, sieć) trafiają do tej
# jednej grupy zasobów. Usunięcie tej grupy usuwa całe laboratorium.
# =============================================================================

resource "azurerm_resource_group" "rg" {
  name     = "rg-xyz-grafmon-lab"
  location = var.location
  tags     = local.tags
}
