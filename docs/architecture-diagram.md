# Architecture diagram 

[![Architecture diagram ](docs\Diagram.png)](docs\Diagram.png). 
---

## Components (boxes)

| ID | Label | Type / notes |
|----|--------|----------------|
| DEV | Developer workstation | Terraform CLI, Ansible, browser, SSH |
| RG | Resource group `observability-app-rg` | Azure container |
| VNET | Virtual network `10.0.0.0/16` | |
| SUB | Subnet `10.0.0.0/24` | public |
| NSG | Network Security Group | In: 22, 5000; Deny rest |
| PIP | Public IP (Static) | |
| VM | Linux VM `application-vm` | Ubuntu 22.04 |
| APP | stress-app (Flask :5000) | systemd `stress-app` |
| VENV | Python venv + OpenCensus | opencensus-ext-azure, flask_middleware |
| LA | Log Analytics workspace | PerGB2018 |
| AI | Application Insights | workspace-based, web |
| AG | Action group | email receiver |
| AL1 | Alert: CPU > 80% | scope: VM |
| AL2 | Alert: Memory low | scope: VM |
| AL3 | Alert: Disk read high | scope: VM |
| AL4 | Alert: VM availability | scope: VM |
| AL5 | Alert: Failed requests | scope: App Insights |

---