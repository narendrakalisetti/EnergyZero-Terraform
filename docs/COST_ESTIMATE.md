# Monthly Cost Estimate — EnergyZero Platform (Production, UK South)

Estimates based on Azure Pricing Calculator (March 2026, Pay-as-you-go, GBP).

| Service | Tier / Config | Est. Monthly (£) |
|---|---|---|
| ADLS Gen2 (GRS, 1TB stored) | Standard, GRS replication | £18 |
| ADLS Gen2 (read/write ops) | 10M operations/month | £5 |
| Azure Data Factory | 1,000 pipeline runs + 500 Databricks activity runs | £22 |
| Azure Databricks | Standard_DS3_v2, 4 nodes, 8hr/day, 22 days/month | £148 |
| Azure Key Vault | Premium SKU, 50k operations/month | £6 |
| Log Analytics | 5GB/day ingestion, 90-day retention | £28 |
| Virtual Network | Private endpoints (ADLS + KV) | £8 |
| Azure Monitor Alerts | 10 alert rules | £3 |
| Microsoft Defender for Storage | Per-storage-account | £12 |
| **Total Estimated** | | **~£250/month** |

## Cost Optimisation Applied

- Databricks auto-terminates after 20 min idle → saves ~£60/month vs. always-on
- ADLS lifecycle tiers bronze to cool (30d) and archive (60d) → saves ~£8/month
- ADF trigger windows scheduled off-peak (02:00–04:00 UTC) → lower grid carbon intensity
- Log Analytics 90-day retention (not 730-day default) → saves ~£15/month

## Dev Environment Cost

Dev uses LRS replication, standard Key Vault SKU, and single-node Databricks cluster:
**~£65/month**
