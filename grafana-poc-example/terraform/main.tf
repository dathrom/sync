resource "azurerm_resource_group" "rg" {
  name     = "rg-pzu-grafmon-lab"
  location = var.location
  tags     = local.tags
}
