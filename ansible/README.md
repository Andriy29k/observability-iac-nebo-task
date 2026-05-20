# Ansible — deploy stress-app

Deploys the Flask `stress-app` to the Linux VM provisioned by Terraform.

## Prerequisites

- Terraform apply completed; VM reachable on port 22
- Ansible 2.14+
- SSH **private** key (same pair as `ssh_key_path` in Terraform tfvars)

## Setup

From the `ansible/` directory:

```bash
cp group_vars/all.yml.example group_vars/all.yml
```

Edit `inventory/hosts.ini` — replace `REPLACE_WITH_VM_IP` with:

`terraform -chdir=../terraform output -raw vm_public_ip`

Verify inventory (must show `observability_vm`, not `{}`):

```bash
ansible-inventory --list
```

Optional: `appinsights_connection_string` in `group_vars/all.yml` (do not commit real secrets).

## Commands

Run from `ansible/` — `ansible.cfg` sets inventory and `roles_path` automatically when the project lives on a normal filesystem (e.g. `~/taska/...`).

```bash
cd ansible

ansible observability -m ping
ansible-playbook playbooks/site.yml --check --diff   # dry-run; does not start systemd
ansible-playbook playbooks/site.yml                  # real deploy
```

In `--check` mode the last task cannot start `stress-app` (the unit file is not on the VM yet). That is expected; use a full run for apply.

With App Insights (extra-var, not in git):

```bash
ansible-playbook playbooks/site.yml \
  -e "appinsights_connection_string=InstrumentationKey=...;IngestionEndpoint=..."
```

If you prefer an explicit inventory path (always valid):

```bash
ansible -i inventory/hosts.ini observability -m ping
ansible-playbook -i inventory/hosts.ini playbooks/site.yml
```

## WSL: repo on `/mnt/c/...`

Windows mounts are often world-writable; Ansible **ignores** `ansible.cfg` there. Use either:

- clone/work under Linux home (`~/taska/...`), or
- pass `-i inventory/hosts.ini` on every command (no wrapper needed).

## Validate

```bash
ansible observability -m shell -a "systemctl status stress-app --no-pager"
ansible observability -m shell -a "curl -sf http://127.0.0.1:5000/api/status"
curl http://<vm-public-ip>:5000/api/status
```

## Rollback

```bash
git checkout <previous-commit> -- ansible/
ansible-playbook playbooks/site.yml
```

Or: `ansible observability -b -m systemd -a "name=stress-app state=stopped"`

## Layout

```
ansible/
├── ansible.cfg              # inventory/hosts.ini, roles_path, inventory plugins
├── inventory/hosts.ini
├── group_vars/all.yml.example
├── playbooks/site.yml
└── roles/stress_app/
```

App on VM: `/home/azureuser/stress-app` (systemd unit `stress-app`).

`group_vars/all.yml` (secrets) is gitignored. Set your VM IP in `inventory/hosts.ini` before deploy.
