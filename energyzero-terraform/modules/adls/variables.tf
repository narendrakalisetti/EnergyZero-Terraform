variable "resource_group_name"        { type = string }
variable "location"                   { type = string }
variable "project_name"               { type = string }
variable "environment"                { type = string }
variable "tags"                       { type = map(string) }
variable "replication_type"           { type = string; default = "GRS" }
variable "allowed_ip_ranges"          { type = list(string); default = [] }
variable "private_endpoint_subnet_id" { type = string; default = "" }
variable "log_analytics_workspace_id" { type = string }
