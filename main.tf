provider "azurerm" {
  # The "feature" block is required for AzureRM provider 2.x. 
  # If you are using version 1.x, the "features" block is not allowed.
  version = "~>2.0"
  features {}
}

###########################
# Resource group for all network related resources
###########################

resource "azurerm_resource_group" "vnet" {
  name     = join("", list(var.prefix, "-rg"))
  location = var.location
}

###########################
# Create VNET
###########################

resource "azurerm_virtual_network" "vnet" {
  name                = join("", list(var.prefix, "-vnet"))
  address_space       = [ join("", list(var.IPAddressPrefix, ".0.0/16")) ]
  location            = azurerm_resource_group.vnet.location
  resource_group_name = azurerm_resource_group.vnet.name
 # dns_servers = [ "10.54.0.100","10.51.255.164"]
}

###########################
# Define subnets 
###########################

# PAN mgmt interface
resource "azurerm_subnet" "fwmgmt" {
  name                 = "fwmgmt"
  resource_group_name  = azurerm_resource_group.vnet.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = [ join("", list(var.IPAddressPrefix, ".1.0/24")) ]
}

# PAN FW outside
resource "azurerm_subnet" "fwuntrust" {
  name                 = "fwuntrust"
  resource_group_name  = azurerm_resource_group.vnet.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = [ join("", list(var.IPAddressPrefix, ".2.0/24")) ]
}

# PAN FW inside
resource "azurerm_subnet" "fwtrust" {
  name                 = "fwtrust"
  resource_group_name  = azurerm_resource_group.vnet.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = [ join("", list(var.IPAddressPrefix, ".3.0/24")) ]
}

# private server subnet
# All Internet outbound traffic will be routed to the PAN FW
resource "azurerm_subnet" "private" {
  name                 = "private"
  resource_group_name  = azurerm_resource_group.vnet.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = [ join("", list(var.IPAddressPrefix, ".4.0/24")) ]
# Add Azure service endpoints needed in this subnet
  service_endpoints    = [ "Microsoft.Storage" ]
}

# Will be configured with a route table that does not use the PAN FW
# For VMs directly accessed from the Internet
resource "azurerm_subnet" "public" {
  name                 = "public"
  resource_group_name  = azurerm_resource_group.vnet.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = [ join("", list(var.IPAddressPrefix, ".5.0/24")) ]
  # Add Azure service endpoints needed in this subnet
  service_endpoints    = [ "Microsoft.Storage" ]

}

# Workstations subnet
# All Internet outbound traffic will be routed to the PAN FW
resource "azurerm_subnet" "vdesktop" {
  name                 = "vdesktop"
  resource_group_name  = azurerm_resource_group.vnet.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = [ join("", list(var.IPAddressPrefix, ".6.0/24")) ]
  # Add Azure service endpoints needed in this subnet
  service_endpoints    = [ "Microsoft.Storage" ]
}

# Required by Azure Basiton service
resource "azurerm_subnet" "bastion" {
  name                 = "AzureBastionSubnet"
  resource_group_name  = azurerm_resource_group.vnet.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = [ join("", list(var.IPAddressPrefix, ".7.0/24")) ]
}

###########################
# Create bastion service
###########################

# Create a public IP address for the bastion service
resource "azurerm_public_ip" "bastion" {
  name                = join("", list(var.prefix, "-bastion"))
  resource_group_name = azurerm_resource_group.vnet.name
  location            = azurerm_resource_group.vnet.location
  allocation_method   = "Static"
  sku                 = "Standard"
  domain_name_label   = join("", list("scb", substr(md5(azurerm_resource_group.vnet.id), 0, 4)))
}

# Create the bastion service
resource "azurerm_bastion_host" "bastion" {
  name                = join("", list(var.prefix, "-bastion"))
  resource_group_name = azurerm_resource_group.vnet.name
  location            = azurerm_resource_group.vnet.location
    
  ip_configuration {
    name                 = "configuration"
    subnet_id            = azurerm_subnet.bastion.id
    public_ip_address_id = azurerm_public_ip.bastion.id
  }
}

###########################
# Create route table and bind to required to subnets
###########################

# This table sends all non-vnet local traffic to the PAN firewall
resource "azurerm_route_table" "pan_fw1" {
  name                          = join("", list(var.prefix, "-panfw"))
  location                      = azurerm_resource_group.vnet.location
  resource_group_name           = azurerm_resource_group.vnet.name
  disable_bgp_route_propagation = false

  route {
    name           = "to-inet-pan"
    address_prefix = "0.0.0.0/0"
    next_hop_type  = "VirtualAppliance"
    # Nexthop is the PAN virtual appliance VNIC2 aka the trust interface
    next_hop_in_ip_address = azurerm_network_interface.FW_VNIC2.private_ip_address
  }
}

# Bind route table to subnets
# In only the VDI and server subnet will be forced to route Internet traffic to the PAN
resource "azurerm_subnet_route_table_association" "server_fw1_map" {
  subnet_id      = azurerm_subnet.private.id
  route_table_id = azurerm_route_table.pan_fw1.id
}

resource "azurerm_subnet_route_table_association" "vdesktop_fw1_map" {
  subnet_id      =  azurerm_subnet.vdesktop.id
  route_table_id = azurerm_route_table.pan_fw1.id
}

###########################
# NSG For public subnet 
###########################
resource "azurerm_network_security_group" "public" {
  name                = join("", list(var.prefix, "-publicdmz"))
  location            = azurerm_resource_group.vnet.location
  resource_group_name = azurerm_resource_group.vnet.name
  
  # Allow traffic from the Internet to port 443 
  security_rule {
    name                       = "Allow-Internet"
    priority                   = 500
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"                               
    destination_address_prefix = "*"
  }

  # Restrict access to the rest of the subnets in the VNET
  security_rule {
    name                       = "Block-VNET"
    priority                   = 1000
    direction                  = "Outbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = join("", list(var.IPAddressPrefix, ".0.0/16"))
  }
}

# Associated the NSG with publicdmz subnet
resource "azurerm_subnet_network_security_group_association" "public" {
  subnet_id      = azurerm_subnet.public.id
  network_security_group_id = azurerm_network_security_group.public.id
}
