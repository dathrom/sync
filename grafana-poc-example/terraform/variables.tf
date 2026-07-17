# Parametry wdrożenia. Domyślne wartości pasują do labu xyz, a te "na sztywno"
# siedzą w terraform.tfvars. Zmienne project/owner/ttl idą tylko do tagów
# (patrz locals.tf) — służą do identyfikacji i sprzątania.

variable "subscription_id" {
  description = "Azure subscription ID (MVP Lab)."
  type        = string
  default     = "ac74f09f-f550-4aa6-b41f-0fbf419c85fd"
}

variable "location" {
  description = "Azure region for all resources."
  type        = string
  default     = "westeurope"
}

variable "project" {
  description = "Tag: project."
  type        = string
  default     = "xyz-grafmon-lab"
}

variable "owner" {
  description = "Tag: owner."
  type        = string
  default     = "sebastian"
}

variable "ttl" {
  description = "Tag: ttl."
  type        = string
  default     = "destroy-after-demo"
}

# Opcjonalny user testowy. Jak wrzucisz jego object ID z Azure AD, dostanie rolę
# "Grafana Viewer" (żeby w ogóle wejść do Grafany) i "Monitoring Reader" na grupie
# zasobów (pod scenariusze z Obszaru 2). Puste = pomijamy nadania ról.
variable "test_user_object_id" {
  description = "AAD object ID of a test user. If set, grants Grafana Viewer on the Grafana resource and Monitoring Reader on the RG. Leave empty to skip."
  type        = string
  default     = ""
}

# Opcjonalna tożsamość (user albo SPN), która uruchamia configure-grafana.sh/.ps1,
# jeśli to INNE konto niż to, którym wykonano `terraform apply` (a więc inne niż
# data.azuread_client_config.current, które dostaje Grafana Admin automatycznie —
# patrz rbac.tf:deployer_grafana_admin). Bez tego az CLI dostanie AuthorizationFailed
# na 'Microsoft.Dashboard/grafana/read' — sama subskrypcja/Owner nie daje dostępu do
# danych Grafany, potrzebna jest explicit rola. Puste = pomijamy nadanie.
variable "configurator_object_id" {
  description = "AAD object ID of the identity running configure-grafana.sh/.ps1, if different from the terraform apply identity. If set, grants Grafana Admin on the Grafana resource (needed to manage data sources). Leave empty to skip."
  type        = string
  default     = ""
}
