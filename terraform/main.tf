resource "azurerm_resource_group" "observability-task-rg" {
  name     = var.resource_group_name
  location = var.location
  tags     = { "env" = "prod", "project" = "observability-iac-task", "owner" = "akorot", "subscription" = "VSES" }
}

resource "azurerm_virtual_network" "observability-task-vnet" {
  name                = var.vnet_name
  location            = azurerm_resource_group.observability-task-rg.location
  resource_group_name = azurerm_resource_group.observability-task-rg.name
  address_space       = [var.vnet_address_space]
  tags                = { "env" = "prod", "project" = "observability-iac-task", "owner" = "akorot", "subscription" = "VSES" }
}

resource "azurerm_subnet" "public-subnet" {
  name                 = "${var.vnet_name}-public-subnet"
  resource_group_name  = azurerm_resource_group.observability-task-rg.name
  virtual_network_name = azurerm_virtual_network.observability-task-vnet.name
  address_prefixes     = [var.public_subnet_address_prefix]
}

resource "azurerm_public_ip" "observability-task-public-ip" {
  name                = "${var.vm_name}-public-ip"
  location            = azurerm_resource_group.observability-task-rg.location
  resource_group_name = azurerm_resource_group.observability-task-rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = { "env" = "prod", "project" = "observability-iac-task", "owner" = "akorot", "subscription" = "VSES" }
}

resource "azurerm_network_security_group" "observability-task-vm-nsg" {
  name                = "${var.vnet_name}-observability-task-vm-nsg"
  location            = azurerm_resource_group.observability-task-rg.location
  resource_group_name = azurerm_resource_group.observability-task-rg.name

  security_rule {
    name                       = "allow-ssh"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "allow-flask-app"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "5000"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "deny-all-inbound"
    priority                   = 4096
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  tags = { "env" = "prod", "project" = "observability-iac-task", "owner" = "akorot", "subscription" = "VSES" }


}

resource "azurerm_network_interface_security_group_association" "observability-task-vm-nic-nsg-association" {
  network_interface_id      = azurerm_network_interface.observability-task-nic.id
  network_security_group_id = azurerm_network_security_group.observability-task-vm-nsg.id
  depends_on = [ azurerm_network_security_group.observability-task-vm-nsg, azurerm_network_interface.observability-task-nic ]
}

resource "azurerm_network_interface" "observability-task-nic" {
  name                = "${var.vm_name}-nic"
  location            = azurerm_resource_group.observability-task-rg.location
  resource_group_name = azurerm_resource_group.observability-task-rg.name

  ip_configuration {
    name                          = "${var.vm_name}-ipconfig"
    subnet_id                     = azurerm_subnet.public-subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.observability-task-public-ip.id
  }

  tags = { "env" = "prod", "project" = "observability-iac-task", "owner" = "akorot", "subscription" = "VSES", "vm" = var.vm_name }

}

resource "azurerm_linux_virtual_machine" "observability-task-vm" {
  name                = var.vm_name
  resource_group_name = azurerm_resource_group.observability-task-rg.name
  location            = azurerm_resource_group.observability-task-rg.location
  size                = var.vm_size
  admin_username      = var.admin_username

  network_interface_ids = [
    azurerm_network_interface.observability-task-nic.id,
  ]

  admin_ssh_key {
    username   = var.admin_username
    public_key = file(var.ssh_key_path)
  }

  os_disk {
    caching              = var.caching_type
    storage_account_type = var.storage_account_type
  }

  source_image_reference {
    publisher = var.publisher
    offer     = var.offer
    sku       = var.sku
    version   = var.image_version
  }

  tags = { "env" = "prod", "project" = "observability-iac-task", "owner" = "akorot", "subscription" = "VSES" }

}
