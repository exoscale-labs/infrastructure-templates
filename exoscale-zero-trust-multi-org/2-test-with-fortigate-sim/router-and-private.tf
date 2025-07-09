# Router and private instances component
# This creates the router and private instances with their own security groups

# Security group for router
resource "exoscale_security_group" "router" {
  name        = "${local.clean_org_name}-router-sg"
  description = "Security group for router"
}

resource "exoscale_security_group_rule" "router_ssh" {
  security_group_id = exoscale_security_group.router.id
  description       = "SSH access"
  type              = "INGRESS"
  protocol          = "TCP"
  start_port        = 22
  end_port          = 22
  cidr              = "0.0.0.0/0"
}

resource "exoscale_security_group_rule" "router_dhcp" {
  security_group_id = exoscale_security_group.router.id
  description       = "DHCP"
  type              = "INGRESS"
  protocol          = "UDP"
  start_port        = 67
  end_port          = 67
  cidr              = local.config.private_network
}

# Security group for private instances
resource "exoscale_security_group" "private_instances" {
  name        = "${local.clean_org_name}-private-sg"
  description = "Security group for private instances"
}

resource "exoscale_security_group_rule" "private_ssh" {
  security_group_id = exoscale_security_group.private_instances.id
  description       = "SSH from router"
  type              = "INGRESS"
  protocol          = "TCP"
  start_port        = 22
  end_port          = 22
  cidr              = "${local.config.router_ip}/32"
}

resource "exoscale_security_group_rule" "private_internal" {
  security_group_id = exoscale_security_group.private_instances.id
  description       = "Internal communication"
  type              = "INGRESS"
  protocol          = "TCP"
  start_port        = 1
  end_port          = 65535
  cidr              = local.config.private_network
}

# Router VM (blocks direct internet, only through FortiGate)
resource "exoscale_compute_instance" "router" {
  zone               = var.zone
  name               = "${local.clean_org_name}-router"
  template_id        = data.exoscale_template.ubuntu.id
  type               = "standard.small"
  disk_size          = 20
  ssh_keys           = [exoscale_ssh_key.test_key.name]
  security_group_ids = [exoscale_security_group.router.id]
  
  user_data = base64encode(templatefile("${path.module}/../shared-configs/cloud-init-router-test.yaml", {
    private_network          = local.config.private_network
    private_ip               = local.config.router_ip
    dhcp_range_start         = local.config.dhcp_start
    dhcp_range_end           = local.config.dhcp_end
    fortigate_sim_ip         = exoscale_compute_instance.fortigate_sim.public_ip_address
    ssh_public_key           = var.ssh_public_key
    shared_ssh_private_key   = jsonencode(tls_private_key.shared_key.private_key_pem)
    shared_ssh_public_key    = tls_private_key.shared_key.public_key_openssh
  }))

  network_interface {
    network_id = exoscale_private_network.test_network.id
  }

  labels = {
    role = "router"
    environment = "test"
  }
}

# Private instances (no public IP)
resource "exoscale_compute_instance" "private_instances" {
  count              = var.instance_count
  zone               = var.zone
  name               = "${local.clean_org_name}-private-${count.index + 1}"
  template_id        = data.exoscale_template.ubuntu.id
  type               = "standard.small"
  disk_size          = 20
  ssh_keys           = [exoscale_ssh_key.test_key.name]
  security_group_ids = [exoscale_security_group.private_instances.id]
  
  # Private instance - no public IP
  private = true
  
  user_data = base64encode(templatefile("${path.module}/../shared-configs/cloud-init-private-minimal-test.yaml", {
    router_ip = local.config.router_ip
    ssh_public_key = var.ssh_public_key
    shared_ssh_public_key = tls_private_key.shared_key.public_key_openssh
  }))

  network_interface {
    network_id = exoscale_private_network.test_network.id
  }

  labels = {
    role = "private-instance"
    environment = "test"
  }
}

# Router and private instance outputs
output "router_ip" {
  description = "Router IP"
  value       = exoscale_compute_instance.router.public_ip_address
}

output "private_instance_ips" {
  description = "Private instance IPs"
  value       = [for instance in exoscale_compute_instance.private_instances : instance.ipv6_address]
}