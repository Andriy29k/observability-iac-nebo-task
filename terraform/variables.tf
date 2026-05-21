variable "subscription" {
  type = string
}

variable "resource_group_name" {
  type    = string
  default = "observability-task-rg"
}

variable "location" {
  type = string
}

variable "vnet_name" {
  type = string
}

variable "vnet_address_space" {
  type = string
}

variable "public_subnet_address_prefix" {
  type = string
}

variable "vm_name" {
  type = string
}

variable "vm_size" {
  type = string
}

variable "admin_username" {
  type = string
}

variable "ssh_key_path" {
  type = string
}

variable "publisher" {
  type = string
}

variable "offer" {
  type = string
}

variable "sku" {
  type = string
}

variable "image_version" {
  type = string
}

variable "storage_account_type" {
  type = string
}

variable "caching_type" {
  type = string
}

variable "env" {
  type    = string
  default = "staging"
}

variable "email_receiver" {
  type = string
}