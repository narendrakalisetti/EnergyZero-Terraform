/*
=============================================================================
Locals – shared computed values and common tags
=============================================================================
*/

locals {
  # UK South abbreviation used in all resource names
  region_abbr = "uks"

  # Standard name prefix: <region>-<project>-<env>
  name_prefix = "${local.region_abbr}-${var.project_name}-${var.environment}"

  # Common tags applied to ALL resources
  # GDPR requires data controller and data classification tags for Purview auto-classification
  common_tags = merge(
    {
      Project            = "EnergyZero"
      Environment        = var.environment
      Region             = var.location
      ManagedBy          = "Terraform"
      DataController     = "EnergyZero Ltd"                   # GDPR Art. 4(7)
      DataClassification = "Confidential"
      GDPRCompliant      = "true"
      NetZero2050        = "true"                             # renewable-energy region commitment
      CostCentre         = "DATA-ENGINEERING"
      Owner              = "data-platform-team@energyzero.co.uk"
      LastUpdated        = timestamp()
    },
    var.tags_additional
  )
}
