# Wspólne tagi doklejane do każdego zasobu (local.tags). Dzięki temu wszystko jest
# oznaczone projektem, właścicielem i TTL-em ("destroy-after-demo") — łatwiej to
# potem odnaleźć i posprzątać po demie.

locals {
  tags = {
    project = var.project
    owner   = var.owner
    ttl     = var.ttl
  }
}
