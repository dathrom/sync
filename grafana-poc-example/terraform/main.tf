# Wszystko trzymamy w jednej grupie zasobów: AKS, Grafana, monitoring, sieci.
# Wygodne o tyle, że skasowanie tej grupy sprząta całe laboratorium za jednym ruchem.

resource "azurerm_resource_group" "rg" {
  name     = "rg-xyz-grafmon-lab"
  location = var.location
  tags     = local.tags
}
