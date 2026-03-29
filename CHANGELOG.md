# Changelog

## [1.2.0] - 2026-03-29
### Added
- Databricks workspace module with VNet injection and cluster policy
- Monitoring module: Log Analytics, pipeline failure alerts, ADLS auth alerts
- Private endpoints for ADLS Gen2 and Key Vault (production only)
- Customer-Managed Key (CMK) encryption on ADLS Gen2
- Microsoft Defender for Storage
- Pre-commit hooks (terraform fmt, tflint, checkov)
- ADF pipeline JSON: pl_ingest_ofgem_bronze (end-to-end trigger)
- PySpark notebooks: 01_bronze_to_silver, 02_silver_to_gold
- Gold layer SQL views (4 views for Power BI)
- Challenges & Lessons Learned documentation
- Cost estimate documentation
- Bootstrap state script

## [1.1.0] - 2026-02-15
### Added
- ADLS Gen2 module with lifecycle management policies
- Key Vault module with secrets and RBAC
- ADF module with linked services
- GitHub Actions CI/CD (plan on PR, apply on merge)
- Environment separation (dev/prod tfvars)

## [1.0.0] - 2026-01-20
### Added
- Initial project structure
- Root module with resource group
- Basic ADLS Gen2 provisioning
