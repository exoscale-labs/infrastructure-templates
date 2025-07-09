# Shared configuration for production deployment
# This contains common resources used by all components

terraform {
  required_providers {
    exoscale = {
      source  = "exoscale/exoscale"
      version = "~> 0.64"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

provider "exoscale" {
  # API credentials from environment variables
}

# Data sources
data "exoscale_template" "ubuntu" {
  zone = var.zone
  name = "Linux Ubuntu 22.04 LTS 64-bit"
}

# Variables
variable "zone" {
  description = "Exoscale zone"
  type        = string
  default     = "ch-gva-2"
}

variable "organization_name" {
  description = "Organization name (er1, er2, er3)"
  type        = string
  
  validation {
    condition     = can(regex("^(er1|er2|er3)$", var.organization_name))
    error_message = "Organization name must be one of: er1, er2, er3."
  }
}

variable "fortigate_public_ip" {
  description = "Public IP address of the FortiGate instance"
  type        = string
}

variable "private_instance_count" {
  description = "Number of private instances to create"
  type        = number
  default     = 2
}

variable "ssh_public_key" {
  description = "SSH public key for instance access"
  type        = string
}

# Network configuration based on organization
locals {
  network_config = {
    er1 = {
      private_network = "10.18.11.0/24"
      router_ip      = "10.18.11.1"
      dhcp_start     = "10.18.11.10"
      dhcp_end       = "10.18.11.200"
      wg_tunnel_ip   = "192.168.100.2/30"
      wg_fortigate_ip = "192.168.100.1"
    }
    er2 = {
      private_network = "10.18.21.0/24"
      router_ip      = "10.18.21.1"
      dhcp_start     = "10.18.21.10"
      dhcp_end       = "10.18.21.200"
      wg_tunnel_ip   = "192.168.101.2/30"
      wg_fortigate_ip = "192.168.101.1"
    }
    er3 = {
      private_network = "10.18.31.0/24"
      router_ip      = "10.18.31.1"
      dhcp_start     = "10.18.31.10"
      dhcp_end       = "10.18.31.200"
      wg_tunnel_ip   = "192.168.102.2/30"
      wg_fortigate_ip = "192.168.102.1"
    }
  }
  
  current_network = local.network_config[var.organization_name]
}

# Private network
resource "exoscale_private_network" "private" {
  zone        = var.zone
  name        = "${var.organization_name}-private-network"
  description = "Private network for ${var.organization_name}"
  netmask     = "255.255.255.0"
  start_ip    = cidrhost(local.current_network.private_network, 2)
  end_ip      = cidrhost(local.current_network.private_network, 254)
}

# SSH keypair
resource "exoscale_ssh_key" "main" {
  name       = "${var.organization_name}-key-${formatdate("YYYYMMDDhhmm", timestamp())}"
  public_key = var.ssh_public_key
}

# Shared SSH key for inter-instance communication
resource "tls_private_key" "shared_key" {
  algorithm = "RSA"
  rsa_bits  = 2048
}