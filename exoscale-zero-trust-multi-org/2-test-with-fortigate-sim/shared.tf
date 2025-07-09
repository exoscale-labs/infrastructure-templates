# Shared configuration for test deployment
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
  description = "Exoscale zone for testing"
  type        = string
  default     = "ch-gva-2"
}

variable "org_name" {
  description = "Test organization name"
  type        = string
  default     = "test-org"
}

variable "ssh_public_key" {
  description = "SSH public key for test instances"
  type        = string
}

variable "instance_count" {
  description = "Number of test private instances"
  type        = number
  default     = 2
}

# Test network configuration
locals {
  config = {
    private_network    = "10.0.0.0/24"
    router_ip         = "10.0.0.1"
    dhcp_start        = "10.0.0.10"
    dhcp_end          = "10.0.0.200"
    fortigate_tunnel  = "192.168.100.1/30"
    router_tunnel     = "192.168.100.2/30"
  }
  
  # Clean organization name for resource naming
  clean_org_name = replace(lower(var.org_name), "_", "-")
}

# Private network
resource "exoscale_private_network" "test_network" {
  zone        = var.zone
  name        = "${local.clean_org_name}-test-network"
  description = "Test private network"
}

# Generate shared SSH key for inter-instance communication
resource "tls_private_key" "shared_key" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

# SSH keypair with unique name
resource "exoscale_ssh_key" "test_key" {
  name       = "${local.clean_org_name}-test-key-${formatdate("YYYYMMDDHHmmss", timestamp())}"
  public_key = var.ssh_public_key
}