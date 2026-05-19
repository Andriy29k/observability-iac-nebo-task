output "rg_name" {
  value = azurerm_resource_group.observability-task-rg.name
}

output "vnet_name" {
  value = azurerm_virtual_network.observability-task-vnet.name
}

output "public_subnet_name" {
  value = azurerm_subnet.public-subnet.name
}

output "user" {
  value = var.admin_username
}

output "vm_name" {
  value = azurerm_linux_virtual_machine.observability-task-vm.name
}

output "vm_public_ip" {
  value = azurerm_public_ip.observability-task-vm-pip.ip_address
}

output "ssh_to_vm" {
  value = "ssh ${var.admin_username}@${azurerm_public_ip.observability-task-vm-pip.ip_address} -i ${var.ssh_key_path}"
}

output "url_to_app" {
    value = "http://${azurerm_public_ip.observability-task-vm-pip.ip_address}:5000"
}