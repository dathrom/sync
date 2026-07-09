# =============================================================================
# variables.tf — Zmienne wejściowe konfiguracji
# -----------------------------------------------------------------------------
# Parametry sterujące wdrożeniem. Wartości domyślne pasują do laboratorium xyz;
# faktyczne wartości "zablokowane" znajdują się w pliku terraform.tfvars.
# Zmienne "project", "owner", "ttl" służą wyłącznie do tagowania zasobów
# (patrz locals.tf) — ułatwiają identyfikację i późniejsze sprzątanie.
# =============================================================================

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

# Opcjonalny użytkownik testowy. Po podaniu jego ID obiektu w Azure AD
# otrzyma on rolę "Grafana Viewer" (logowanie do Grafany) oraz "Monitoring Reader"
# na grupie zasobów (scenariusze z Obszaru 2). Pusta wartość = pomijamy nadanie ról.
variable "test_user_object_id" {
  description = "AAD object ID of a test user. If set, grants Grafana Viewer on the Grafana resource and Monitoring Reader on the RG. Leave empty to skip."
  type        = string
  default     = ""
}
