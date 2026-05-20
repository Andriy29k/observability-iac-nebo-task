# observability-iac-nebo-task

Azure infrastructure (Terraform) and application deployment (Ansible) for the NEBO observability lab.

## Repository layout

```
terraform/          # Azure RG, VNet, subnet, NSG, Linux VM
stress-app/         # Flask stress / metrics demo app
ansible/            # Playbook and role to deploy stress-app on the VM
```

## 1. Provision infrastructure (Terraform)

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars   # fill in values
terraform init
terraform plan -no-color -out=planfile
terraform apply planfile
```

Destroy when finished:

```bash
terraform destroy
```

Key outputs: `vm_public_ip`, `url_to_app`, `ssh_to_vm`.

## 2. Deploy application (Ansible)

See [ansible/README.md](ansible/README.md).

```bash
# edit ansible/inventory/hosts.ini — set VM IP (terraform output -raw vm_public_ip)

cd ansible
ansible observability -m ping
ansible-playbook playbooks/site.yml --check --diff
ansible-playbook playbooks/site.yml
```

## 3. Monitoring

Configure Application Insights in the Azure portal manually. Optional:

```bash
cd ansible
ansible-playbook playbooks/site.yml \
  -e "appinsights_connection_string=<your-connection-string>"
```

## Rollback

- **Infrastructure:** `git checkout <tag>` then `terraform apply`, or `terraform destroy`
- **Application:** re-run playbook from a previous git revision, or stop `stress-app` on the VM
