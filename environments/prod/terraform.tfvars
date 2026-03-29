# Production environment – UK South
# EnergyZero Data Engineering Platform
# GDPR Compliant | Net Zero 2050 Aligned

project_name              = "energyzero"
environment               = "prod"
location                  = "uksouth"
adls_replication_type     = "GRS"
key_vault_sku             = "premium"
soft_delete_retention_days = 90

# Restrict to corporate VPN CIDRs in production
allowed_ip_ranges = []

tags_additional = {
  CostCentre  = "DATA-ENGINEERING"
  Criticality = "High"
}
