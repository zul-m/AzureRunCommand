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

locals {
  resource_group_name = var.infrastructure_id
  location            = var.location
}

resource "azurerm_resource_group" "rg" {
  name     = local.resource_group_name
  location = local.location
}

# Using values from resource "azurerm_resource_group" instead of local.resource_group_name and local.location
# To avoid the "Resource group could not be found." error
module "secrets" {
  source              = "./modules/secrets"
  infrastructure_id   = var.infrastructure_id
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
}

resource "azurerm_virtual_network" "vnet" {
  name                = module.secrets.vnet_name
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
  name                = module.secrets.nic_name
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "ipconfig"
    subnet_id                     = azurerm_subnet.vm_subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = module.secrets.vm_public_ip_id
  }
}

resource "azurerm_windows_virtual_machine" "vm" {
  name                = module.secrets.vm_name
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  size                = "Standard_E4s_v5"
  admin_username      = module.secrets.admin_username
  admin_password      = module.secrets.admin_password
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

resource "azurerm_network_security_group" "vm_nsg" {
  name                = module.secrets.vm_nsg_name
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