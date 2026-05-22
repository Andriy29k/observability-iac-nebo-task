resource "azurerm_resource_group" "observability-task-rg" {
  name     = var.resource_group_name
  location = var.location
  tags     = { "env" = var.env, "project" = "observability-iac-task", "owner" = "akorot", "subscription" = "VSES" }
}

resource "azurerm_virtual_network" "observability-task-vnet" {
  name                = var.vnet_name
  location            = azurerm_resource_group.observability-task-rg.location
  resource_group_name = azurerm_resource_group.observability-task-rg.name
  address_space       = [var.vnet_address_space]
  tags                = { "env" = var.env, "project" = "observability-iac-task", "owner" = "akorot", "subscription" = "VSES" }
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
  tags                = { "env" = var.env, "project" = "observability-iac-task", "owner" = "akorot", "subscription" = "VSES" }
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

  tags = { "env" = var.env, "project" = "observability-iac-task", "owner" = "akorot", "subscription" = "VSES" }


}

resource "azurerm_network_interface_security_group_association" "observability-task-vm-nic-nsg-association" {
  network_interface_id      = azurerm_network_interface.observability-task-nic.id
  network_security_group_id = azurerm_network_security_group.observability-task-vm-nsg.id
  depends_on                = [azurerm_network_security_group.observability-task-vm-nsg, azurerm_network_interface.observability-task-nic]
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

  tags = { "env" = var.env, "project" = "observability-iac-task", "owner" = "akorot", "subscription" = "VSES", "vm" = var.vm_name }

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

  tags = { "env" = var.env, "project" = "observability-iac-task", "owner" = "akorot", "subscription" = "VSES" }

}

resource "azurerm_application_insights" "observability-task-app-insights" {
  name                = "${var.vm_name}-app-insights"
  location            = azurerm_resource_group.observability-task-rg.location
  resource_group_name = azurerm_resource_group.observability-task-rg.name
  application_type    = "web"
  workspace_id        = azurerm_log_analytics_workspace.observability-task-log-analytics.id
  tags                = { "env" = var.env, "project" = "observability-iac-task", "owner" = "akorot", "subscription" = "VSES", "vm" = var.vm_name }
  depends_on          = [azurerm_log_analytics_workspace.observability-task-log-analytics]
}

resource "azurerm_log_analytics_workspace" "observability-task-log-analytics" {
  name                = "${var.vm_name}-log-analytics"
  location            = azurerm_resource_group.observability-task-rg.location
  resource_group_name = azurerm_resource_group.observability-task-rg.name
  sku                 = "PerGB2018"
  tags                = { "env" = var.env, "project" = "observability-iac-task", "owner" = "akorot", "subscription" = "VSES", "vm" = var.vm_name }
}

resource "azurerm_monitor_action_group" "observability-task-action-group" {
  name                = "task-group"
  resource_group_name = azurerm_resource_group.observability-task-rg.name
  short_name          = "task-ag"
  tags                = { "env" = var.env, "project" = "observability-iac-task", "owner" = "akorot", "subscription" = "VSES", "vm" = var.vm_name }

  email_receiver {
    name                    = "email-receiver"
    email_address           = var.email_receiver
    use_common_alert_schema = true
  }
}

resource "azurerm_monitor_metric_alert" "cpu-metric-alert" {
  name                = "${var.vm_name}-cpu-alert"
  resource_group_name = azurerm_resource_group.observability-task-rg.name
  scopes              = [azurerm_linux_virtual_machine.observability-task-vm.id]
  description         = "Alert for high CPU usage"
  severity            = 2
  enabled             = true
  tags                = { "env" = var.env, "project" = "observability-iac-task", "owner" = "akorot", "subscription" = "VSES", "vm" = var.vm_name }

  criteria {
    metric_namespace = "Microsoft.Compute/virtualMachines"
    metric_name      = "Percentage CPU"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 80
  }

  frequency   = "PT5M"
  window_size = "PT5M"

  action {
    action_group_id = azurerm_monitor_action_group.observability-task-action-group.id
  }
}

resource "azurerm_monitor_metric_alert" "memory-metric-alert" {
  name                = "${var.vm_name}-memory-alert"
  resource_group_name = azurerm_resource_group.observability-task-rg.name
  scopes              = [azurerm_linux_virtual_machine.observability-task-vm.id]
  description         = "Alert for high Memory usage"
  severity            = 2
  enabled             = true
  tags                = { "env" = var.env, "project" = "observability-iac-task", "owner" = "akorot", "subscription" = "VSES", "vm" = var.vm_name }

  criteria {
    metric_namespace = "Microsoft.Compute/virtualMachines"
    metric_name      = "Available Memory Bytes"
    aggregation      = "Average"
    operator         = "LessThan"
    threshold        = 1073741824
  }

  frequency   = "PT5M"
  window_size = "PT5M"

  action {
    action_group_id = azurerm_monitor_action_group.observability-task-action-group.id
  }
}

resource "azurerm_monitor_metric_alert" "disk-metric-alert" {
  name                = "${var.vm_name}-disk-alert"
  resource_group_name = azurerm_resource_group.observability-task-rg.name
  scopes              = [azurerm_linux_virtual_machine.observability-task-vm.id]
  description         = "Alert for high Disk usage"
  severity            = 2
  enabled             = true
  tags                = { "env" = var.env, "project" = "observability-iac-task", "owner" = "akorot", "subscription" = "VSES", "vm" = var.vm_name }

  criteria {
    metric_namespace = "Microsoft.Compute/virtualMachines"
    metric_name      = "OS Disk Read Bytes/sec"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 104857600
  }

  frequency   = "PT5M"
  window_size = "PT5M"

  action {
    action_group_id = azurerm_monitor_action_group.observability-task-action-group.id
  }
}

resource "azurerm_monitor_metric_alert" "availability-metric-alert" {
  name                = "${var.vm_name}-availability-alert"
  resource_group_name = azurerm_resource_group.observability-task-rg.name
  scopes              = [azurerm_linux_virtual_machine.observability-task-vm.id]
  description         = "Alert when VM availability metric drops"
  severity            = 1
  enabled             = true
  tags                = { "env" = var.env, "project" = "observability-iac-task", "owner" = "akorot", "subscription" = "VSES", "vm" = var.vm_name }

  criteria {
    metric_namespace = "Microsoft.Compute/virtualMachines"
    metric_name      = "VmAvailabilityMetric"
    aggregation      = "Average"
    operator         = "LessThan"
    threshold        = 1
  }

  frequency   = "PT5M"
  window_size = "PT5M"

  action {
    action_group_id = azurerm_monitor_action_group.observability-task-action-group.id
  }
}

resource "azurerm_monitor_metric_alert" "failed-requests-metric-alert" {
  name                = "${var.vm_name}-failed-requests-alert"
  resource_group_name = azurerm_resource_group.observability-task-rg.name
  scopes              = [azurerm_application_insights.observability-task-app-insights.id]
  description         = "Alert for failed requests in the application"
  severity            = 2
  enabled             = true
  tags                = { "env" = var.env, "project" = "observability-iac-task", "owner" = "akorot", "subscription" = "VSES", "vm" = var.vm_name }

  criteria {
    metric_namespace = "Microsoft.Insights/components"
    metric_name      = "requests/failed"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = 10
  }

  frequency   = "PT5M"
  window_size = "PT5M"

  action {
    action_group_id = azurerm_monitor_action_group.observability-task-action-group.id
  }

}