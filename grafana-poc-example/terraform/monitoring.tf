# ── AMW-A: fed by AKS managed-Prometheus add-on ──────────────────────────────

resource "azurerm_monitor_workspace" "amw_a" {
  name                = "amw-a"
  resource_group_name = azurerm_resource_group.rg.name
  location            = var.location
  tags                = local.tags
}

resource "azurerm_monitor_data_collection_endpoint" "dce_a" {
  name                = "dce-amw-a"
  resource_group_name = azurerm_resource_group.rg.name
  location            = var.location
  kind                = "Linux"
  tags                = local.tags
}

# DCR-A: routes the Microsoft-PrometheusMetrics stream from the AKS add-on into AMW-A.
# kind is intentionally unset: Prometheus DCRs do not use the Linux/Windows/AgentDirectToStore kinds.
resource "azurerm_monitor_data_collection_rule" "dcr_a" {
  name                        = "dcr-amw-a"
  resource_group_name         = azurerm_resource_group.rg.name
  location                    = var.location
  data_collection_endpoint_id = azurerm_monitor_data_collection_endpoint.dce_a.id

  destinations {
    monitor_account {
      monitor_account_id = azurerm_monitor_workspace.amw_a.id
      name               = "amw-a-dest"
    }
  }

  data_flow {
    streams      = ["Microsoft-PrometheusMetrics"]
    destinations = ["amw-a-dest"]
  }

  data_sources {
    prometheus_forwarder {
      name    = "prom-fwd-a"
      streams = ["Microsoft-PrometheusMetrics"]
    }
  }

  tags = local.tags
}

# ── AMW-B: fed by self-hosted Prometheus remote_write (post-apply Helm step) ──

resource "azurerm_monitor_workspace" "amw_b" {
  name                = "amw-b"
  resource_group_name = azurerm_resource_group.rg.name
  location            = var.location
  tags                = local.tags
}

resource "azurerm_monitor_data_collection_endpoint" "dce_b" {
  name                = "dce-amw-b"
  resource_group_name = azurerm_resource_group.rg.name
  location            = var.location
  kind                = "Linux"
  tags                = local.tags
}

# DCR-B: self-hosted Prometheus remote_write endpoint; auth via kubelet IMDS identity.
resource "azurerm_monitor_data_collection_rule" "dcr_b" {
  name                        = "dcr-amw-b"
  resource_group_name         = azurerm_resource_group.rg.name
  location                    = var.location
  data_collection_endpoint_id = azurerm_monitor_data_collection_endpoint.dce_b.id

  destinations {
    monitor_account {
      monitor_account_id = azurerm_monitor_workspace.amw_b.id
      name               = "amw-b-dest"
    }
  }

  data_flow {
    streams      = ["Microsoft-PrometheusMetrics"]
    destinations = ["amw-b-dest"]
  }

  data_sources {
    prometheus_forwarder {
      name    = "prom-fwd-b"
      streams = ["Microsoft-PrometheusMetrics"]
    }
  }

  tags = local.tags
}
