# Simple test to validate Exoscale credentials and basic connectivity

terraform {
  required_providers {
    exoscale = {
      source  = "exoscale/exoscale"
      version = "~> 0.64"
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

variable "ssh_public_key" {
  description = "SSH public key"
  type        = string
}

# Security group for simple test
resource "exoscale_security_group" "test_sg" {
  name        = "simple-test-sg"
  description = "Security group for simple test instance"
}

# Allow SSH access
resource "exoscale_security_group_rule" "ssh_access" {
  security_group_id = exoscale_security_group.test_sg.id
  description       = "SSH access from anywhere"
  type              = "INGRESS"
  protocol          = "TCP"
  start_port        = 22
  end_port          = 22
  cidr              = "0.0.0.0/0"
}

# Allow ICMP for ping
resource "exoscale_security_group_rule" "icmp_access" {
  security_group_id = exoscale_security_group.test_sg.id
  description       = "ICMP ping"
  type              = "INGRESS"
  protocol          = "ICMP"
  icmp_type         = 8
  icmp_code         = 0
  cidr              = "0.0.0.0/0"
}

# SSH keypair
resource "exoscale_ssh_key" "test_key" {
  name       = "simple-test-key"
  public_key = var.ssh_public_key
}

# Simple compute instance test
resource "exoscale_compute_instance" "test_instance" {
  zone               = var.zone
  name               = "simple-test-instance"
  template_id        = data.exoscale_template.ubuntu.id
  type               = "standard.small"
  disk_size          = 10
  ssh_keys           = [exoscale_ssh_key.test_key.name]
  security_group_ids = [exoscale_security_group.test_sg.id]
  
  labels = {
    purpose = "simple-connectivity-test"
    managed = "terraform"
  }
}

# Outputs
output "instance_ip" {
  description = "Instance public IP"
  value       = exoscale_compute_instance.test_instance.public_ip_address
}

output "ssh_command" {
  description = "SSH command to connect"
  value       = "ssh ubuntu@${exoscale_compute_instance.test_instance.public_ip_address}"
}

output "test_status" {
  description = "Test validation status"
  value = {
    credentials = "✅ Exoscale API credentials working"
    terraform   = "✅ Terraform configuration valid"
    instance    = "✅ Can create compute instances"
    next_step   = "Ready for full architecture deployment"
  }
}