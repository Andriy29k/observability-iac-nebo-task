# observability-iac-nebo-task

NEBO DevOps lab: Azure infrastructure (Terraform), Flask stress-app deployment (Ansible), and observability (Application Insights, Log Analytics, metric alerts).

## Architecture

See [docs/architecture-diagram.md](docs/architecture-diagram.md) for a draw.io–friendly diagram (components and connections).

High-level flow:

1. **Terraform** provisions network, VM, App Insights, Log Analytics, alerts.
2. **Ansible** installs the app on the VM and injects the App Insights connection string.
3. **stress-app** sends traces/events to App Insights; Azure Monitor collects VM metrics and fires alerts.

## Repository layout

```
terraform/              # Azure IaC (RG, VNet, VM, monitoring, alerts)
stress-app/             # Flask app (CPU/RAM stress + OpenCensus telemetry)
ansible/                # Playbook and role to deploy stress-app
docs/                   # Architecture diagram reference for draw.io
```

## Prerequisites

- Azure subscription and CLI login (`az login`)
- Terraform ~> 1.0, AzureRM provider ~> 4.0
- Ansible 2.14+
- SSH key pair (public key path in tfvars; private key for Ansible/SSH)
- Python 3 on the control machine (optional, for local tests)

## 1. Provision infrastructure (Terraform)

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars   # fill subscription, region, vm_size, email_receiver, etc.
terraform init
terraform plan -no-color -out=planfile
terraform apply planfile
```

Use `terraform plan -no-color > plan.txt` for dry-run artifacts (avoid ANSI in redirected files).

### Terraform creates

| Resource | Purpose |
|----------|---------|
| Resource group | Container for all resources |
| VNet + public subnet | Network `10.0.0.0/16` / `10.0.0.0/24` |
| NSG | SSH (22), Flask (5000), deny other inbound |
| Public IP + NIC + Linux VM | Ubuntu 22.04, `stress-app` host |
| Log Analytics workspace | Backend for workspace-based App Insights |
| Application Insights | App telemetry (connection string output) |
| Monitor action group | Email notifications |
| Metric alerts | VM CPU, memory, disk; App Insights failed requests |

### Key outputs

```bash
terraform output vm_public_ip
terraform output url_to_app
terraform output ssh_to_vm
terraform output -raw app_insights_connection_string   # sensitive
```

### Destroy

```bash
terraform destroy
```

## 2. Deploy application (Ansible)

See [ansible/README.md](ansible/README.md).

```bash
# Set VM IP in inventory
# Edit ansible/inventory/hosts.ini: ansible_host = <vm_public_ip>

cd ansible
ansible observability -m ping
ansible-playbook playbooks/site.yml --check --diff
ansible-playbook playbooks/site.yml \
  -e "appinsights_connection_string=$(terraform -chdir=../terraform output -raw app_insights_connection_string)"
```

Ansible installs Python venv, copies `stress-app/` to `/home/<user>/stress-app`, configures systemd unit `stress-app`, and writes `.env` with `APPINSIGHTS_CONNECTION_STRING`.

### Verify on VM

```bash
journalctl -u stress-app -n 20 | grep -i AppInsights
# Expect: Handler attached, FlaskMiddleware attached

curl http://<vm_public_ip>:5000/api/status
```

## 3. Monitoring and alerts

### Infrastructure metrics (Azure Monitor)

- Portal → **Virtual machine** → **Metrics** (CPU, memory, disk, network).
- Alerts created by Terraform (CPU > 80%, low memory, disk I/O, availability, failed requests on App Insights).

Confirm email subscription for the action group (Azure sends a confirmation link).

### Application Insights

Telemetry from **OpenCensus** (`opencensus-ext-azure`, `opencensus-ext-flask`):

- HTTP requests (Flask middleware)
- Custom events (`cpu_stress_started`, `ram_stress_started`, …)
- Traces and exceptions

**Logs** (workspace-based — use `App*` tables if classic tables are empty):

```kusto
AppTraces
| where TimeGenerated > ago(1h)
| order by TimeGenerated desc

AppRequests
| where TimeGenerated > ago(1h)
| order by TimeGenerated desc

AppTraces
| where Message contains "stress" or Message contains "EVENT"
| where TimeGenerated > ago(1h)
```

Allow **5–15 minutes** after generating traffic for batch export.

**Live Metrics** requires [Azure Monitor OpenTelemetry](https://learn.microsoft.com/azure/azure-monitor/app/live-stream); OpenCensus does not provide the Live Metrics stream.

### Generate load for demos

Open `http://<vm_public_ip>:5000`, trigger CPU/RAM stress, or:

```bash
curl -X POST http://<vm_public_ip>:5000/api/stress/cpu/high
```

## System Monitoring

### Data Collection

System-level telemetry is collected via **Azure Monitor Agent (AMA)** and routed
through a **Data Collection Rule (DCR)** to the Log Analytics workspace.

To enable monitoring:

1. Portal → **Monitor** → **Data Collection Rules** → **Create**.
2. Fill in name, region; set platform type to **Linux**.
3. On the **Resources** tab → **Add resources** → select `application-vm`.
4. On the **Data sources** tab → **Add data source**:
   - Type: **Linux Syslog**
   - Set minimum log level per facility
5. On the **Destination** tab → select your **Log Analytics workspace**.
6. **Review + Create**.

Agent status check — run on the VM:
```bash
systemctl status azuremonitoragent
journalctl -u azuremonitoragent -n 30
```

---

### Available Log Tables

Once the DCR is active, logs are queryable in Log Analytics:

| Table | Contents |
|-------|----------|
| `Heartbeat` | Agent liveness, one record per minute |
| `Syslog` | All Linux syslog facilities (auth, daemon, kern, …) |
| `InsightsMetrics` | CPU, memory, disk, network (numeric time-series) |

Allow **5–10 minutes** after DCR creation for the first records to appear.

---

### Useful KQL Queries

**Agent heartbeat — confirm VM is reachable:**
```kusto
Heartbeat
| where TimeGenerated > ago(5m)
| summarize LastHeartbeat = max(TimeGenerated) by Computer
```

**CPU and memory over time:**
```kusto
InsightsMetrics
| where TimeGenerated > ago(1h)
| where Name in ("UtilizationPercentage", "availableMB")
| summarize avg(Val) by bin(TimeGenerated, 5m), Name
| render timechart
```

**SSH logins:**
```kusto
Syslog
| where TimeGenerated > ago(24h)
| where Facility in ("auth", "authpriv")
| where SyslogMessage has_any ("Accepted password", "Accepted publickey", "session opened")
| project TimeGenerated, Computer, SeverityLevel, SyslogMessage
| order by TimeGenerated desc
```

**stress-app service logs**  
> The systemd unit runs under the `python` process name — filter by that:
```kusto
Syslog
| where TimeGenerated > ago(1h)
| where ProcessName == "python"
| project TimeGenerated, SeverityLevel, SyslogMessage
| order by TimeGenerated desc
```

---

### Data Retention

Retention is configured at the **Log Analytics workspace** level, per table.

Default: **90 days free**, up to **730 days** (additional cost beyond 90 days).

```bash
az monitor log-analytics workspace table update \
  --resource-group  \
  --workspace-name  \
  --name Syslog \
  --retention-time 91
```

Or via Portal: **Log Analytics workspace** → **Tables** → select table
→ **Manage table** → set *Interactive retention* and *Total retention*.

---

### Observability Dashboard

A unified dashboard combining VM metrics, application telemetry, and system logs
is available as an **Azure Workbook**.

Portal → **Application Insights** → **Workbooks** → **New**.

Recommended structure:

| Section | Visualization | Source |
|---------|--------------|--------|
| VM Health (heartbeat) | Tiles | `Heartbeat` |
| CPU & Memory | Line chart | `InsightsMetrics` |
| HTTP Requests (success/fail) | Bar chart | `AppRequests` |
| Response Time (avg / p95) | Line chart | `AppRequests` |
| Exceptions | Grid | `AppExceptions` |
| stress-app Logs | Grid | `Syslog` |
| SSH Logins | Grid | `Syslog` |
| Errors & Warnings | Grid | `AppTraces` |

---

## Rollback

| Layer | Procedure |
|-------|-----------|
| Infrastructure | `git checkout <tag>` → `terraform apply`, or `terraform destroy` |
| Application | `git checkout <commit> -- ansible/ stress-app/` → re-run playbook, or `systemctl stop stress-app` on VM |
| App Insights secret | Rotate connection string in portal → update Ansible extra-var → redeploy |

## Versioning (Git)

- Meaningful commits; tag stable releases: `git tag -a v1.0.0 -m "First stable version"`
- Do not commit `terraform.tfvars`, `terraform.tfstate`, or secrets in `group_vars/all.yml`
- `inventory/hosts.ini` may contain IP only (no keys)

## Troubleshooting

| Symptom | Check |
|---------|--------|
| Ansible: empty inventory | `inventory/hosts.ini` exists; fix CRLF: `sed -i 's/\r$//' inventory/hosts.ini` |
| `[AppInsights] Import failed` | `venv/bin/pip install -r requirements.txt`; see `app.py` import paths |
| No data in Portal | journal shows `Handler attached`; wait 5–15 min; query `AppTraces` / `AppRequests` |
| `ZonalAllocationFailed` | Remove VM `zone` or change `vm_size` / region |
| Metric alert 400 | Use exact metric names (`OS Disk Read Bytes/sec`, `VmAvailabilityMetric`, `Count` for failed requests) |

## References

- [Terraform AzureRM](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)
- [Application Insights Live Metrics](https://learn.microsoft.com/azure/azure-monitor/app/live-stream)
- [Ansible documentation](https://docs.ansible.com/)
