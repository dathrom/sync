# ── Grafana system MI → Monitoring Data Reader on each AMW ───────────────────
# Required so the Prometheus data sources in Grafana can query both workspaces.

resource "azurerm_role_assignment" "grafana_data_reader_amw_a" {
  scope                = azurerm_monitor_workspace.amw_a.id
  role_definition_name = "Monitoring Data Reader"
  principal_id         = azurerm_dashboard_grafana.grafana.identity[0].principal_id
}

resource "azurerm_role_assignment" "grafana_data_reader_amw_b" {
  scope                = azurerm_monitor_workspace.amw_b.id
  role_definition_name = "Monitoring Data Reader"
  principal_id         = azurerm_dashboard_grafana.grafana.identity[0].principal_id
}

# ── Grafana system MI → Monitoring Reader on RG ───────────────────────────────
# Needed for the Azure Monitor data source (Area 2) to enumerate resources.

resource "azurerm_role_assignment" "grafana_monitoring_reader_rg" {
  scope                = azurerm_resource_group.rg.id
  role_definition_name = "Monitoring Reader"
  principal_id         = azurerm_dashboard_grafana.grafana.identity[0].principal_id
}

# ── App-reg SP → Monitoring Reader on RG ──────────────────────────────────────
# Area-2 S2.3: service-identity data source for alerts / recording rules.

resource "azurerm_role_assignment" "sp_monitoring_reader_rg" {
  scope                = azurerm_resource_group.rg.id
  role_definition_name = "Monitoring Reader"
  principal_id         = azuread_service_principal.sp.object_id
}

# ── AKS → Monitoring Metrics Publisher on DCR-A (managed-Prometheus add-on ingestion) ──
# Reviewers disagreed on which identity the ama-metrics add-on uses (control-plane MI vs
# kubelet MI), and the DCR association may auto-authorize anyway. Grant BOTH (harmless if
# redundant) so ingestion into AMW-A cannot fail on a wrong-principal 403. Verify `up` lands
# in AMW-A at deploy time regardless.
resource "azurerm_role_assignment" "aks_metrics_publisher_dcr_a" {
  scope                = azurerm_monitor_data_collection_rule.dcr_a.id
  role_definition_name = "Monitoring Metrics Publisher"
  principal_id         = azurerm_kubernetes_cluster.aks.identity[0].principal_id
}

resource "azurerm_role_assignment" "aks_kubelet_metrics_publisher_dcr_a" {
  scope                = azurerm_monitor_data_collection_rule.dcr_a.id
  role_definition_name = "Monitoring Metrics Publisher"
  principal_id         = azurerm_kubernetes_cluster.aks.kubelet_identity[0].object_id
}

# ── AKS kubelet identity → Monitoring Metrics Publisher on DCR-B ──────────────
# Self-hosted Prometheus pods auth to AMW-B via IMDS; IMDS returns the kubelet (node) identity.

resource "azurerm_role_assignment" "aks_kubelet_metrics_publisher_dcr_b" {
  scope                = azurerm_monitor_data_collection_rule.dcr_b.id
  role_definition_name = "Monitoring Metrics Publisher"
  principal_id         = azurerm_kubernetes_cluster.aks.kubelet_identity[0].object_id
}

# ── AKS cluster identity → Network Contributor on vnet-lab ───────────────────
# Required for AKS to provision the internal Load Balancer frontend IP and the
# Private Link Service (S1.6) in the BYO subnet. Without it the internal LB stays
# <pending> with a 403 reading the subnet.
resource "azurerm_role_assignment" "aks_network_contributor_vnet" {
  scope                = azurerm_virtual_network.vnet_lab.id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_kubernetes_cluster.aks.identity[0].principal_id
}

# ── Deployer → Grafana Admin on the Grafana workspace ────────────────────────
# Subscription Owner does NOT grant Grafana data-plane access; an explicit Grafana
# role is required to create/manage data sources (configure-grafana.sh).
resource "azurerm_role_assignment" "deployer_grafana_admin" {
  scope                = azurerm_dashboard_grafana.grafana.id
  role_definition_name = "Grafana Admin"
  principal_id         = data.azuread_client_config.current.object_id
}

# ── Optional test user ─────────────────────────────────────────────────────────
# Set test_user_object_id in tfvars to enable. Grants Grafana Viewer (required
# for the user to log into Grafana at all) and Monitoring Reader on RG (for S2 scenarios).

resource "azurerm_role_assignment" "test_user_grafana_viewer" {
  count                = var.test_user_object_id != "" ? 1 : 0
  scope                = azurerm_dashboard_grafana.grafana.id
  role_definition_name = "Grafana Viewer"
  principal_id         = var.test_user_object_id
}

resource "azurerm_role_assignment" "test_user_monitoring_reader_rg" {
  count                = var.test_user_object_id != "" ? 1 : 0
  scope                = azurerm_resource_group.rg.id
  role_definition_name = "Monitoring Reader"
  principal_id         = var.test_user_object_id
}
