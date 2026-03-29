# Contributing to EnergyZero Terraform

## Branching Strategy
- `main` — production-ready, protected. CI applies to Azure prod on merge.
- `develop` — integration branch. Terraform plan runs on every push.
- `feature/*` — individual features. Always branch from `develop`.

## Before Committing
Install pre-commit hooks:
```bash
pip install pre-commit
pre-commit install
```
These run `terraform fmt`, `tflint`, and `checkov` automatically on every commit.

## Pull Request Checklist
- [ ] `terraform fmt -check` passes
- [ ] `terraform validate` passes
- [ ] `tflint` passes with no errors
- [ ] Checkov security scan passes
- [ ] New resources include all required tags
- [ ] Sensitive values use Key Vault references (never hardcoded)
- [ ] Module README updated if variables/outputs changed

## Naming Convention
All resources follow: `<type>-uks-<project>-<environment>`
Example: `adf-uks-energyzero-prod`
