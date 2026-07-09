# =============================================================================
# aks.tf — Klaster Kubernetes (AKS) + podpięcie do managed Prometheus
# -----------------------------------------------------------------------------
# Klaster AKS pełni podwójną rolę:
#   - hostuje dodatek "managed Prometheus" (agent ama-metrics), który zasila AMW-A,
#   - uruchamia samodzielny Prometheus (instalowany później Helmem), zasilający AMW-B.
# Konfiguracja jest minimalna/laboratoryjna: 1 węzeł, SKU Free (bez SLA na API).
# Sieć: Azure CNI w trybie "overlay" — Pody dostają adresy z osobnej puli
# (pod_cidr), niezależnej od adresacji VNet.
# Na końcu pliku: powiązania AKS -> DCR-A, które faktycznie kierują strumień
# metryk do przestrzeni AMW-A.
# =============================================================================

resource "azurerm_kubernetes_cluster" "aks" {
  name                = "aks-xyz-grafmon-lab"
  location            = var.location
  resource_group_name = azurerm_resource_group.rg.name
  dns_prefix          = "xyz-grafmon-lab"

  # Free = no SLA on API server; acceptable for lab.
  sku_tier = "Free"

  default_node_pool {
    name           = "system"
    node_count     = 1
    vm_size        = "Standard_B2ms"
    vnet_subnet_id = azurerm_subnet.snet_aks.id
    # Managed disk: B2ms temp disk (4 GiB) is too small for ephemeral OS.
    os_disk_type = "Managed"

    upgrade_settings {
      max_surge = "10%"
    }
  }

  identity {
    type = "SystemAssigned"
  }

  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    # Pods get addresses from this overlay CIDR, which is separate from the VNet.
    pod_cidr       = "192.168.0.0/16"
    service_cidr   = "10.240.0.0/16"
    dns_service_ip = "10.240.0.10"
  }

  # Włącza dodatek managed-Prometheus (agent ama-metrics). Pusty blok = ustawienia domyślne.
  # Enable managed-Prometheus add-on (ama-metrics agent). No extra config needed.
  monitor_metrics {}

  # Explicitly no OMS agent / Container Insights (would spin up a billed Log Analytics workspace).

  tags = local.tags
}

# ── Połączenie AKS → DCR-A (przepływ metryk managed-Prometheus do AMW-A) ──────
# ── Wire AKS → DCR-A (managed-Prometheus metrics flow to AMW-A) ───────────────

resource "azurerm_monitor_data_collection_rule_association" "dcra_aks_dcr_a" {
  name                    = "dcra-aks-amw-a"
  target_resource_id      = azurerm_kubernetes_cluster.aks.id
  data_collection_rule_id = azurerm_monitor_data_collection_rule.dcr_a.id
}

# Configuration-access-endpoint association: tells ama-metrics where to fetch its config.
# The name "configurationAccessEndpoint" is the value Azure expects for this association type.
resource "azurerm_monitor_data_collection_rule_association" "dcra_aks_dce_a" {
  name                        = "configurationAccessEndpoint"
  target_resource_id          = azurerm_kubernetes_cluster.aks.id
  data_collection_endpoint_id = azurerm_monitor_data_collection_endpoint.dce_a.id
}
