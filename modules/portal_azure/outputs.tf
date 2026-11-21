output "resource_group_name" {
  value = azurerm_resource_group.this.name
}

output "vnet_cidr" {
  value = local.vnet_cidr
}

output "subnet_cidr" {
  value = local.subnet_cidr
}

output "vm_name" {
  value = azurerm_linux_virtual_machine.portal.name
}

output "vm_id" {
  value = azurerm_linux_virtual_machine.portal.virtual_machine_id
}

output "public_ip" {
  value = azurerm_public_ip.portal.ip_address
}

output "private_ip" {
  value = azurerm_network_interface.portal.private_ip_address
}
