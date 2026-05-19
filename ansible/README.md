# Ansible — deploy stress-app

Deploys the Flask `stress-app` to the Linux VM provisioned by Terraform.

## Prerequisites

- Terraform apply completed; VM reachable on port 22
- Ansible 2.14+ installed locally
- SSH private key matching the public key used in Terraform (`ssh_key_path` in tfvars)

## Setup inventory

From the repository root:

```bash
cp ansible/inventory/hosts.yml.example ansible/inventory/hosts.yml
cp ansible/group_vars/all.yml.example ansible/group_vars/all.yml
```

Edit `ansible/inventory/hosts.yml`:

- `ansible_host` — `terraform -chdir=terraform output -raw vm_public_ip`
- `ansible_user` — same as `admin_username` in `terraform.tfvars`
- `ansible_ssh_private_key_file` — path to **private** key (e.g. `~/.ssh/id_ed25519`, not `.pub`)

Optional: set `appinsights_connection_string` in `ansible/group_vars/all.yml` when Application Insights is configured.

## Commands

Run from the `ansible/` directory:

```bash
cd ansible

# Connectivity check
ansible all -m ping

# Dry-run (Task 1 artifact)
ansible-playbook playbooks/site.yml --check --diff

# Deploy / update (idempotent)
ansible-playbook playbooks/site.yml

# With App Insights connection string (avoid committing secrets)
ansible-playbook playbooks/site.yml \
  -e "appinsights_connection_string=InstrumentationKey=...;IngestionEndpoint=..."
```

## Validate

```bash
# On the VM
ansible all -m shell -a "systemctl status stress-app --no-pager"
ansible all -m shell -a "curl -sf http://127.0.0.1:5000/api/status"

# From your machine (use terraform output url_to_app)
curl http://<vm-public-ip>:5000/api/status
```

## Rollback

1. `git checkout <previous-commit> -- ansible/`
2. `ansible-playbook playbooks/site.yml`

Or stop the service on the VM:

```bash
ansible all -m shell -a "sudo systemctl stop stress-app" -b
```

## Layout

```
ansible/
├── ansible.cfg
├── inventory/hosts.yml.example
├── group_vars/all.yml.example
├── playbooks/site.yml
└── roles/stress_app/
```

`hosts.yml` and local `all.yml` with secrets are gitignored.
