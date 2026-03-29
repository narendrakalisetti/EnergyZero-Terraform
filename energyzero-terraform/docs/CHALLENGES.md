# Challenges & Lessons Learned

Real problems encountered while building the EnergyZero platform — and how they were solved.

---

## 1. ADF Managed Identity RBAC Propagation Delay (403 on First Run)

**The Problem:**
After running `terraform apply` and assigning `Storage Blob Data Contributor` to the ADF managed identity, the first ADF pipeline run immediately failed with a 403 Forbidden error — even though the Terraform output showed the role assignment as successful.

**Root Cause:**
Azure RBAC role assignments are eventually consistent. The assignment is recorded immediately in Azure Resource Manager, but the actual authorisation token cache on the storage account takes **up to 10 minutes** to propagate globally across Azure's distributed auth infrastructure.

**The Fix:**
Added a 10-minute sleep step to the `scripts/deploy_adf_pipelines.sh` CI/CD script between Terraform apply and the first pipeline trigger:
```bash
echo "Waiting 10 minutes for RBAC propagation before triggering pipeline..."
sleep 600
az datafactory pipeline create-run ...
```
Also documented this as a known Azure behaviour in the team runbook.

**Lesson:** Never assume RBAC assignments are immediately effective. In any automated deploy-then-run workflow, always build in a wait period or use a retry loop with exponential backoff.

---

## 2. Key Vault Soft-Delete Conflict on Destroy + Redeploy

**The Problem:**
During development, running `terraform destroy` followed by `terraform apply` in the same day caused Key Vault provisioning to fail with:
```
VaultAlreadyExists: A vault with the same name already exists in a deleted state.
```

**Root Cause:**
Azure Key Vault has mandatory soft-delete (cannot be disabled since Feb 2025). The vault name `kv-uks-energyzero-dev` was "deleted" but still in the 7-day soft-delete recovery window. Terraform tried to create a new vault with the same name — Azure blocked it.

**The Fix:**
Two changes:
1. Added `recover_soft_deleted_key_vaults = true` to the `azurerm` provider `features` block — Terraform now recovers the soft-deleted vault instead of creating a new one.
2. For emergency manual purge (dev only), documented the command:
```bash
az keyvault purge --name kv-uks-energyzero-dev --location uksouth
```
3. In prod, `purge_protection_enabled = true` means even this command is blocked — which is correct for GDPR data availability requirements.

**Lesson:** Design your Terraform destroy/redeploy workflow around Azure's soft-delete behaviour from day one. Don't fight it — work with it.

---

## 3. ADLS Gen2 Shared Key Disabled Breaking ADF Linked Service

**The Problem:**
Setting `shared_access_key_enabled = false` on the storage account (a security best practice) broke the initial ADF linked service which had been configured using a connection string (shared key auth).

ADF pipeline runs failed with:
```
AuthorizationFailure: The account being accessed does not support shared key auth.
```

**Root Cause:**
The ADF linked service `ls_adlsgen2_energyzero` was using connection string authentication, which relies on the storage account shared key. Disabling shared key auth at the storage level invalidated this.

**The Fix:**
Migrated the ADF linked service to use **Managed Identity authentication** — which does not require any keys at all. Updated the Terraform resource:
```hcl
resource "azurerm_data_factory_linked_service_azure_blob_storage" "adls" {
  use_managed_identity = true
  service_endpoint     = "https://${var.adls_account_name}.blob.core.windows.net"
}
```
Then ensured the ADF managed identity had `Storage Blob Data Contributor` on the storage account.

**Lesson:** Implement managed identity auth from day one — it is simultaneously more secure AND less maintenance than key rotation. Shared key auth should never reach production.

---

## 4. Terraform State Lock Contention in GitHub Actions

**The Problem:**
Two engineers pushed to `main` within seconds of each other, triggering two concurrent GitHub Actions runs. Both tried to acquire the Terraform state lock simultaneously. One succeeded; the other failed with:
```
Error: Error acquiring the state lock
Lock Info: ID: abc123... Operation: OperationTypeApply
```
The failed run left the GitHub Actions UI in an error state, causing confusion about whether the apply had succeeded.

**The Fix:**
Added GitHub Actions `concurrency` groups to ensure only one Terraform workflow runs at a time:
```yaml
concurrency:
  group: terraform-prod
  cancel-in-progress: false  # Don't cancel — queue instead
```
`cancel-in-progress: false` ensures the second run waits rather than being killed — important for infrastructure applies where partial state is dangerous.

**Lesson:** Terraform remote state locking and CI/CD concurrency controls must be designed together. State locking is your last line of defence — but preventing concurrent runs is the right first line of defence.

---

## 5. Databricks VNet Injection NSG Rules Conflict

**The Problem:**
Enabling VNet injection for Databricks initially failed with:
```
BadRequest: Subnet 'snet-databricks-public' has policies that conflict with Databricks requirements.
```

**Root Cause:**
The NSG attached to the Databricks subnets had a `DenyAllInbound` rule at priority 4096 that was blocking the Databricks control plane from communicating with worker nodes — a requirement for VNet-injected workspaces.

**The Fix:**
Databricks requires specific inbound rules to allow its control plane CIDRs. Added the required rules to the Databricks subnet NSGs:
```hcl
security_rule {
  name                       = "AllowDatabricksControlPlane"
  priority                   = 100
  direction                  = "Inbound"
  access                     = "Allow"
  protocol                   = "Tcp"
  source_address_prefix      = "AzureDatabricks"
  destination_port_ranges    = ["22", "5557"]
  destination_address_prefix = "VirtualNetwork"
}
```
Also set `no_public_ip = true` on the Databricks workspace to route all traffic through the private subnet.

**Lesson:** Read the Databricks VNet injection documentation in full before designing your NSG rules. The Databricks control plane has specific network requirements that override generic "deny all" policies.
