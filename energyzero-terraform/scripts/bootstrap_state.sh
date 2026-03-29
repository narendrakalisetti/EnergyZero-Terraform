#!/bin/bash
# =============================================================================
# Bootstrap Terraform Remote State Storage
# Run ONCE before first terraform init
# =============================================================================
set -e

RESOURCE_GROUP="rg-uks-energyzero-tfstate"
STORAGE_ACCOUNT="sauksenergyzerotfstate"
CONTAINER="tfstate"
LOCATION="uksouth"

echo "Creating Terraform state infrastructure in Azure..."

az group create \
  --name $RESOURCE_GROUP \
  --location $LOCATION \
  --tags Project=EnergyZero ManagedBy=Manual Purpose=TerraformState

az storage account create \
  --name $STORAGE_ACCOUNT \
  --resource-group $RESOURCE_GROUP \
  --location $LOCATION \
  --sku Standard_LRS \
  --encryption-services blob \
  --https-only true \
  --min-tls-version TLS1_2 \
  --allow-blob-public-access false

az storage container create \
  --name $CONTAINER \
  --account-name $STORAGE_ACCOUNT \
  --auth-mode login

# Enable versioning for state file recovery
az storage account blob-service-properties update \
  --account-name $STORAGE_ACCOUNT \
  --resource-group $RESOURCE_GROUP \
  --enable-versioning true

echo "Bootstrap complete. Terraform state backend ready."
echo "Storage Account : $STORAGE_ACCOUNT"
echo "Container       : $CONTAINER"
echo "State key       : prod/energyzero-de.tfstate"
