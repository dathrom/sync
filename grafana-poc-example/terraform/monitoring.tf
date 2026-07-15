# Świadomie stawiamy DWA niezależne źródła metryk Prometheus, żeby pokazać dwie
# różne ścieżki zbierania danych:
#
#   AMW-A  <- dodatek "managed Prometheus" w AKS (ama-metrics zbiera metryki sam
#             i wysyła je przez DCR-A). Tę przestrzeń później prywatyzujemy, dostęp
#             idzie przez Private Endpoint.
#
#   AMW-B  <- self-hosted Prometheus (Helm) gadający "remote_write" przez DCR-B.
#             Zostaje publiczna, instalowana już po apply skryptem k8s/deploy-k8s.sh.
#
# Każda przestrzeń chce pary:
#   DCE (Data Collection Endpoint) - punkt wejścia, którym wpadają dane,
#   DCR (Data Collection Rule)     - reguła "skąd strumień i dokąd go zapisać".

# ── AMW-A: karmiona przez dodatek managed-Prometheus w AKS
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

# DCR-A wpycha strumień "Microsoft-PrometheusMetrics" z dodatku AKS prosto do AMW-A.
# "kind" zostawiam pusty celowo — reguły DCR dla Prometheusa i tak nie korzystają
# z wariantów Linux/Windows/AgentDirectToStore.
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

# ── AMW-B: karmiona przez self-hosted Prometheusa (remote_write, Helm doinstalowany po apply)
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

# DCR-B: endpoint remote_write dla self-hosted Prometheusa. Uwierzytelnia się
# tożsamością kubeleta (węzła AKS), którą bierze z IMDS (169.254.169.254).
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
