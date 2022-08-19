terraform {
  required_providers {
    local = {
      source  = "hashicorp/local"
      version = "~> 2.2.3"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.18.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.3.2"
    }
  }
}

provider "azurerm" {
  features {}

  subscription_id = var.subscription_id
  tenant_id       = var.tenant_id

}

locals {
  resource_group_name    = var.infrastructure_id
  location               = var.location
  azurerm_key_vault_name = "${var.infrastructure_id}kvt"
  admin_username         = random_id.random.id
  admin_password         = random_password.password.result
  vnet_name              = "${var.infrastructure_id}vnet"
  vm_nic_name            = "${var.infrastructure_id}nic"
  vm_name                = "${var.infrastructure_id}vm"
  vm_public_ip_name      = "${var.infrastructure_id}ip"
  vm_nsg_name            = "${var.infrastructure_id}nsg"
}

resource "random_id" "random" {
  byte_length = 6
}

resource "random_password" "password" {
  length  = 16
  special = true
}

data "azurerm_client_config" "current" {}

resource "azurerm_resource_group" "rg" {
  name     = local.resource_group_name
  location = local.location
}

resource "azurerm_virtual_network" "vnet" {
  name                = local.vnet_name
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

# Using azurerm_virtual_network.vnet.name as virtual_network_name instead of local.vnet_name
# To avoid "the resource vnet was not found" error
resource "azurerm_subnet" "vm_subnet" {
  name                 = "default"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.2.0/24"]
}

resource "azurerm_network_interface" "vm_nic" {
  name                = local.vm_nic_name
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "ipconfig"
    subnet_id                     = azurerm_subnet.vm_subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.vm_public_ip.id
  }
}

resource "azurerm_windows_virtual_machine" "vm" {
  name                = local.vm_name
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  size                = "Standard_E4s_v5"
  admin_username      = local.admin_username
  admin_password      = local.admin_password
  network_interface_ids = [
    azurerm_network_interface.vm_nic.id
  ]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
  }

  source_image_reference {
    publisher = "MicrosoftWindowsDesktop"
    offer     = "Windows-10"
    sku       = "win10-21h2-pro-g2"
    version   = "latest"
  }

  boot_diagnostics {
    storage_account_uri = ""
  }
}

resource "azurerm_public_ip" "vm_public_ip" {
  name                = local.vm_public_ip_name
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  allocation_method   = "Static"
}

resource "azurerm_network_security_group" "vm_nsg" {
  name                = local.vm_nsg_name
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  security_rule {
    name                       = "RDP"
    priority                   = 300
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3389"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "HTTP"
    priority                   = 320
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "HTTPS"
    priority                   = 340
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowHTTPOutBound"
    priority                   = 300
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "vm_nsg_associate" {
  subnet_id                 = azurerm_subnet.vm_subnet.id
  network_security_group_id = azurerm_network_security_group.vm_nsg.id
}

resource "azurerm_key_vault" "keyvault" {
  name                        = local.azurerm_key_vault_name
  location                    = azurerm_resource_group.rg.location
  resource_group_name         = azurerm_resource_group.rg.name
  enabled_for_disk_encryption = true
  tenant_id                   = data.azurerm_client_config.current.tenant_id
  soft_delete_retention_days  = 7
  purge_protection_enabled    = false

  sku_name = "standard"

  access_policy {
    tenant_id = data.azurerm_client_config.current.tenant_id
    object_id = data.azurerm_client_config.current.object_id

    key_permissions = [
      "Get", "List",
    ]

    secret_permissions = [
      "Get", "List", "Set", "Delete", "Purge", "Recover",
    ]

    storage_permissions = [
      "Get", "List",
    ]
  }
}

resource "azurerm_key_vault_secret" "username" {
  name         = "admin-username"
  value        = local.admin_username
  key_vault_id = azurerm_key_vault.keyvault.id
}

resource "azurerm_key_vault_secret" "password" {
  name         = "admin-password"
  value        = local.admin_password
  key_vault_id = azurerm_key_vault.keyvault.id
}

resource "azurerm_key_vault_secret" "vnet" {
  name         = "vnet-name"
  value        = local.vnet_name
  key_vault_id = azurerm_key_vault.keyvault.id
}

resource "azurerm_key_vault_secret" "nic" {
  name         = "vm-nic-name"
  value        = local.vm_nic_name
  key_vault_id = azurerm_key_vault.keyvault.id
}

resource "azurerm_key_vault_secret" "vm" {
  name         = "vm-name"
  value        = local.vm_name
  key_vault_id = azurerm_key_vault.keyvault.id
}

resource "azurerm_key_vault_secret" "public_ip" {
  name         = "vm-public-ip-name"
  value        = local.vm_public_ip_name
  key_vault_id = azurerm_key_vault.keyvault.id
}

resource "azurerm_key_vault_secret" "nsg" {
  name         = "vm-nsg-name"
  value        = local.vm_nsg_name
  key_vault_id = azurerm_key_vault.keyvault.id
}