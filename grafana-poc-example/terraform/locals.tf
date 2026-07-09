# =============================================================================
# locals.tf — Wartości lokalne (wyliczane)
# -----------------------------------------------------------------------------
# Wspólny zestaw tagów doklejany do KAŻDEGO zasobu (local.tags). Dzięki temu
# wszystkie zasoby są jednolicie oznaczone projektem, właścicielem i znacznikiem
# TTL ("destroy-after-demo"), co ułatwia ich odnalezienie i usunięcie po demie.
# =============================================================================

locals {
  tags = {
    project = var.project
    owner   = var.owner
    ttl     = var.ttl
  }
}
