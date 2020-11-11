###########################
# Let's deploy that PAN VM
# Replace any occurance of !!!CHANGE ME!!! with the appropriate values
###########################

# PAN FW Resource Group
resource "azurerm_resource_group" "PAN_FW_RG" {
  name     = join("", list(var.prefix, "-fw-rg"))
  location = var.location
}

# Storage Acct for FW disk
resource "azurerm_storage_account" "PAN_FW_STG_AC" {
  name                = join("", list(var.StorageAccountName, substr(md5(azurerm_resource_group.PAN_FW_RG.id), 0, 4)))
  resource_group_name = azurerm_resource_group.PAN_FW_RG.name
  location            = azurerm_resource_group.PAN_FW_RG.location
  account_replication_type = "LRS"
  account_tier        = "Standard" 
}

# Public IP for PAN mgmt Intf
resource "azurerm_public_ip" "pan_mgmt" {
  name                = join("", list(var.prefix, "-fw-mgmt"))
  location            = azurerm_resource_group.PAN_FW_RG.location
  resource_group_name = azurerm_resource_group.PAN_FW_RG.name
  allocation_method   = "Static"
  # Handy to give it a Domain name
  domain_name_label   = join("", list(var.FirewallDnsName, substr(md5(azurerm_resource_group.PAN_FW_RG.id), 0, 4)))
}

# Public IP for PAN untrust interface
resource "azurerm_public_ip" "pan_untrust" {
  name                = join("", list(var.prefix, "-fw-untrust"))
  location            = azurerm_resource_group.PAN_FW_RG.location
  resource_group_name = azurerm_resource_group.PAN_FW_RG.name
  allocation_method   = "Static"
}

# NSG For PAN Mgmt Interface
resource "azurerm_network_security_group" "pan_mgmt" {
  name                = join("", list(var.prefix, "-panmgmt"))
  location            = azurerm_resource_group.PAN_FW_RG.location
  resource_group_name = azurerm_resource_group.PAN_FW_RG.name

# Permit inbound access to the mgmt VNIC from permitted IPs
  security_rule {
    name                       = "Allow-Intra"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    # Add the source IP address that will be used to access the FW mgmt interface
    source_address_prefixes      = ["!!!CHANGE ME!!!"]                         
    destination_address_prefix = "*"
  }
  
  security_rule {
    name                       = "AllowInternetOutbound"
    priority                   = 100
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "0.0.0.0/0"
  }
}

# Associated the NSG with PAN's mgmt subnet
resource "azurerm_subnet_network_security_group_association" "pan_mgmt" {
  subnet_id      = azurerm_subnet.fwmgmt.id
  network_security_group_id = azurerm_network_security_group.pan_mgmt.id
}

# PAN mgmt VNIC
resource "azurerm_network_interface" "FW_VNIC0" {
  name                = join("", list(var.prefix, "-fwmgmt0"))
  location            = azurerm_resource_group.PAN_FW_RG.location
  resource_group_name = azurerm_resource_group.PAN_FW_RG.name
 
  enable_accelerated_networking = true
  
  ip_configuration {
    name                          = "ipconfig0"
    subnet_id                     = azurerm_subnet.fwmgmt.id
    private_ip_address_allocation = "Dynamic"
    # Mgmt VNIC has static public IP address
    public_ip_address_id          = azurerm_public_ip.pan_mgmt.id
  }

  tags = {
    panInterface = "mgmt0"
  }
}

# PAN untrust VNIC
resource "azurerm_network_interface" "FW_VNIC1" {
  name                = join("", list(var.prefix, "-fwethernet1_1"))
  location            = azurerm_resource_group.PAN_FW_RG.location
  resource_group_name = azurerm_resource_group.PAN_FW_RG.name

# Accelerated networking supported by PAN OS image
  enable_accelerated_networking = true
  enable_ip_forwarding          = true

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = azurerm_subnet.fwuntrust.id
    private_ip_address_allocation = "Static"
    private_ip_address            = join("", list(var.IPAddressPrefix, ".2.4"))
    # Untrusted interface has static public IP address
    public_ip_address_id          = azurerm_public_ip.pan_untrust.id
  }

  tags = {
    panInterface = "ethernet1/1"
  }
}

# PAN trust VNIC
resource "azurerm_network_interface" "FW_VNIC2" {
  name                = join("", list(var.prefix, "-fwethernet1_2"))
  location            = azurerm_resource_group.PAN_FW_RG.location
  resource_group_name = azurerm_resource_group.PAN_FW_RG.name
  
  # Accelerated networking supported by PAN OS image
  enable_accelerated_networking = true
  enable_ip_forwarding          = true

  ip_configuration {
    name                          = "ipconfig2"
    subnet_id                     = azurerm_subnet.fwtrust.id
    private_ip_address_allocation = "Static"
    private_ip_address            = join("", list(var.IPAddressPrefix, ".3.4"))
  }

  tags = {
    panInterface = "ethernet1/2"
  }
}

# Create the firewall VM
resource "azurerm_virtual_machine" "PAN_FW_FW" {
  name                  = var.FirewallVmName
  location              = azurerm_resource_group.PAN_FW_RG.location
  resource_group_name   = azurerm_resource_group.PAN_FW_RG.name
  # The ARM templates for PAN OS VM use specific machine size - using same here
  vm_size               = "Standard_D3_v2"
  
  plan {
    # Using a pay as you go license set sku to "bundle2"
    # To use a purchased license change sku to "byol"
    name      = "bundle2"
    publisher = "paloaltonetworks"
    product   = "vmseries1"
  }

  storage_image_reference {
    publisher = "paloaltonetworks"
    offer     = "vmseries1"
    # Using a pay as you go license set sku to "bundle2"
    # To use a purchased license change sku to "byol"
    sku       = "bundle2"
    version   = "Latest"
  }

  storage_os_disk {
    name          = join("", list(var.FirewallVmName, "-osDisk"))
    vhd_uri       = "${azurerm_storage_account.PAN_FW_STG_AC.primary_blob_endpoint}vhds/${var.FirewallVmName}-osdisk1.vhd"
    caching       = "ReadWrite"
    create_option = "FromImage"
  }

  os_profile {
    computer_name  = var.FirewallVmName
    admin_username = "panzadmins"
    admin_password = "!!!CHANGE ME!!!"
    # Required to use the Panaroma bootstrap process
    # If you don't plan to use the bootstrap process comment out the custom_data field
    custom_data = join(
      ",",
      [
       # The bootstrap azure storage account and config files are not created via tf
       # The init-cfg.txt is the only mandatory file for the bootstrap process 
       # init-cfg must be stored in the "bootstrap" file share in the "config" folder
       # These paramters must be correct for the PAN to download the init-cfg.txt
       # init-cfg.txt requires 2 paramters the panorama IP address and authorization key
       "storage-account=!!!CHANGE ME!!!",
       "access-key=!!!CHANGE ME!!!",
       "file-share=bootstrap",
       "share-directory=None"
      ],
    )
  }
  # The ordering of interaces assignewd here controls the PAN OS device mapping
  # 1st = mgmt0, 2nd = Ethernet1/1, 3rd = Ethernet 1/2 
  primary_network_interface_id = azurerm_network_interface.FW_VNIC0.id
  network_interface_ids = [azurerm_network_interface.FW_VNIC0.id,
                           azurerm_network_interface.FW_VNIC1.id,
                           azurerm_network_interface.FW_VNIC2.id ]

  os_profile_linux_config {
    disable_password_authentication = false
  }
}

output "FirewallMgmtFQDN" {
  value = join("", list("https://", azurerm_public_ip.pan_mgmt.fqdn))
}

output "FirewallMgmtIP" {
  value = join("", list("https://", azurerm_public_ip.pan_mgmt.ip_address))
}
