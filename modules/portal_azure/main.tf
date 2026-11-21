# Modulo Azure: VNet 172.20.X.0/24, subred 172.20.X.0/26 y una VM Linux con el Portal v1.
# Sin peering, replicacion ni failover con AWS. No se abre SSH.

locals {
  vnet_cidr   = "172.20.${var.x}.0/24"
  subnet_cidr = "172.20.${var.x}.0/26"
}

resource "azurerm_resource_group" "this" {
  name     = "${var.name_prefix}-az-rg"
  location = var.location
  tags     = var.tags
}

resource "azurerm_virtual_network" "this" {
  name                = "${var.name_prefix}-az-vnet"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  address_space       = [local.vnet_cidr]
  tags                = var.tags
}

resource "azurerm_subnet" "portal" {
  name                 = "${var.name_prefix}-az-snet"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [local.subnet_cidr]
}

resource "azurerm_network_security_group" "portal" {
  name                = "${var.name_prefix}-az-nsg"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = var.tags

  security_rule {
    name                       = "allow-http-80"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefixes    = var.allowed_http_cidrs
    destination_address_prefix = "*"
  }
  # Sin regla para 22: no se exige SSH ni acceso administrativo publico.
}

resource "azurerm_subnet_network_security_group_association" "portal" {
  subnet_id                 = azurerm_subnet.portal.id
  network_security_group_id = azurerm_network_security_group.portal.id
}

resource "azurerm_public_ip" "portal" {
  name                = "${var.name_prefix}-az-pip"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

resource "azurerm_network_interface" "portal" {
  name                = "${var.name_prefix}-az-nic"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = var.tags

  ip_configuration {
    name                          = "primary"
    subnet_id                     = azurerm_subnet.portal.id
    private_ip_address_allocation = "Dynamic" # IP real asignada por Azure
    public_ip_address_id          = azurerm_public_ip.portal.id
  }
}

resource "azurerm_linux_virtual_machine" "portal" {
  name                            = "${var.name_prefix}-az-vm"
  location                        = azurerm_resource_group.this.location
  resource_group_name             = azurerm_resource_group.this.name
  size                            = var.vm_size
  admin_username                  = var.admin_username
  disable_password_authentication = true
  network_interface_ids           = [azurerm_network_interface.portal.id]
  custom_data                     = base64encode(var.bootstrap)
  tags                            = var.tags

  admin_ssh_key {
    username   = var.admin_username
    public_key = var.admin_ssh_public_key
  }

  os_disk {
    name                 = "${var.name_prefix}-az-osdisk"
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  # Azure conserva v1 en U2 (no se exige actualizarla). custom_data incluye
  # el build_ref del commit, que cambia con cada commit; sin esto, cada
  # commit nuevo reemplazaria la VM. La VM conserva el build con el que se creo.
  lifecycle {
    ignore_changes = [custom_data]
  }

  depends_on = [azurerm_subnet_network_security_group_association.portal]
}
