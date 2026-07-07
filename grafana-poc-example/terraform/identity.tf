data "azuread_client_config" "current" {}

# Area-2 app-reg auth identity (S2.3 second data source for alerting/recording rules).
resource "azuread_application" "app_reg" {
  display_name = "pzu-grafmon-lab-area2"
  owners       = [data.azuread_client_config.current.object_id]
}

resource "azuread_service_principal" "sp" {
  client_id = azuread_application.app_reg.client_id
  owners    = [data.azuread_client_config.current.object_id]
}

resource "azuread_application_password" "app_password" {
  application_id = azuread_application.app_reg.id
  display_name   = "lab-secret"
}
