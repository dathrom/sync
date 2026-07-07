output "resource_group_name" {
  description = "Resource group containing all substrate."
  value       = azurerm_resource_group.rg.name
}

output "amw_a_id" {
  description = "Resource ID of AMW-A (managed-Prometheus, private via Grafana MPE)."
  value       = azurerm_monitor_workspace.amw_a.id
}

output "amw_a_query_endpoint" {
  description = "AMW-A Prometheus query endpoint (use this in Grafana data source)."
  value       = azurerm_monitor_workspace.amw_a.query_endpoint
}

output "amw_b_id" {
  description = "Resource ID of AMW-B (self-hosted remote_write, stays public)."
  value       = azurerm_monitor_workspace.amw_b.id
}

output "amw_b_query_endpoint" {
  description = "AMW-B Prometheus query endpoint."
  value       = azurerm_monitor_workspace.amw_b.query_endpoint
}

output "grafana_endpoint" {
  description = "Managed Grafana HTTPS endpoint."
  value       = azurerm_dashboard_grafana.grafana.endpoint
}

output "grafana_name" {
  description = "Managed Grafana workspace name."
  value       = azurerm_dashboard_grafana.grafana.name
}

output "grafana_mi_principal_id" {
  description = "System-assigned MI object ID of Managed Grafana (for additional role assignments)."
  value       = azurerm_dashboard_grafana.grafana.identity[0].principal_id
}

output "aks_name" {
  description = "AKS cluster name (use with az aks get-credentials)."
  value       = azurerm_kubernetes_cluster.aks.name
}

output "aks_node_resource_group" {
  description = "Auto-created MC_ node resource group (contains node VMs, disks, NICs)."
  value       = azurerm_kubernetes_cluster.aks.node_resource_group
}

output "app_reg_client_id" {
  description = "Client ID (app ID) of the Area-2 app registration."
  value       = azuread_application.app_reg.client_id
}

output "app_reg_secret" {
  description = "App registration client secret. Sensitive — use: terraform output -raw app_reg_secret"
  value       = azuread_application_password.app_password.value
  sensitive   = true
}

output "private_dns_zone_name" {
  description = "Explicit private DNS zone for AMW Prometheus privatelink."
  value       = azurerm_private_dns_zone.prometheus.name
}

output "dce_b_id" {
  description = "DCE-B resource ID; needed to get the metricsIngestion endpoint for prometheus remote_write."
  value       = azurerm_monitor_data_collection_endpoint.dce_b.id
}

output "dcr_b_id" {
  description = "DCR-B resource ID; its immutableId is part of the remote_write URL."
  value       = azurerm_monitor_data_collection_rule.dcr_b.id
}

output "aks_kubelet_client_id" {
  description = "Client ID of the AKS kubelet (node) managed identity; used by self-hosted Prometheus azuread remote_write."
  value       = azurerm_kubernetes_cluster.aks.kubelet_identity[0].client_id
}
