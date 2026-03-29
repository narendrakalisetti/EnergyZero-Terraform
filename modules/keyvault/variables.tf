variable "resource_group_name"        { type = string }
variable "location"                   { type = string }
variable "project_name"               { type = string }
variable "environment"                { type = string }
variable "tenant_id"                  { type = string }
variable "object_id"                  { type = string }
variable "tags"                       { type = map(string) }
variable "key_vault_sku"              { type = string; default = "premium" }
variable "soft_delete_retention_days" { type = number; default = 90 }
variable "allowed_ip_ranges"          { type = list(string); default = [] }
