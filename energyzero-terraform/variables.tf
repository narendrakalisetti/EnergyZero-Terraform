/*
=============================================================================
EnergyZero – Input Variables
=============================================================================
*/

variable "project_name" {
  description = "Short project name used in all resource names. Must be lowercase alphanumeric."
  type        = string
  default     = "energyzero"

  validation {
    condition     = can(regex("^[a-z0-9]{1,12}$", var.project_name))
    error_message = "project_name must be 1–12 lowercase alphanumeric characters."
  }
}

variable "environment" {
  description = "Deployment environment: dev | staging | prod"
  type        = string
  default     = "prod"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

variable "location" {
  description = "Azure region. Default UK South for Net Zero 2050 renewable energy alignment."
  type        = string
  default     = "uksouth"

  validation {
    condition     = var.location == "uksouth"
    error_message = "EnergyZero policy mandates UK South for all production resources (renewable energy, data sovereignty, GDPR)."
  }
}

variable "adls_replication_type" {
  description = "ADLS Gen2 replication. GRS for prod (BCDR), LRS acceptable for dev/staging."
  type        = string
  default     = "GRS"

  validation {
    condition     = contains(["LRS", "GRS", "ZRS", "GZRS"], var.adls_replication_type)
    error_message = "adls_replication_type must be LRS, GRS, ZRS, or GZRS."
  }
}

variable "key_vault_sku" {
  description = "Key Vault SKU. Use 'premium' for HSM-backed keys (recommended for GDPR)."
  type        = string
  default     = "premium"
}

variable "soft_delete_retention_days" {
  description = "Key Vault soft-delete retention (7–90 days). 90 days recommended for GDPR data controllers."
  type        = number
  default     = 90
}

variable "allowed_ip_ranges" {
  description = "List of CIDR blocks allowed to access ADLS Gen2 and Key Vault (corporate network ranges)."
  type        = list(string)
  default     = []
}

variable "adf_integration_runtime_size" {
  description = "ADF Managed Integration Runtime node size."
  type        = string
  default     = "Standard_D4_v3"
}

variable "tags_additional" {
  description = "Additional tags to merge with common tags."
  type        = map(string)
  default     = {}
}
