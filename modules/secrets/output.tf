output "admin_username" {
  value = random_string.username.result
}

output "admin_password" {
  value = random_password.password.result
}

output "vnet_name" {
  value = "${var.infrastructure_id}vnet"
}

output "nic_name" {
  value = "${var.infrastructure_id}nic"
}

output "vm_name" {
  value = "${var.infrastructure_id}vm"
}

output "vm_nsg_name" {
  value = "${var.infrastructure_id}nsg"
}

output "vm_public_ip_id" {
  value = azurerm_public_ip.vm_public_ip.id
}