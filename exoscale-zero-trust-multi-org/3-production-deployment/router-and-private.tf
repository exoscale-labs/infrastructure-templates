# Router and private instances component for production
# This creates the router and private instances with their own security groups

# Security group for router
resource "exoscale_security_group" "router" {
  name        = "${var.organization_name}-router-sg"
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

resource "exoscale_security_group_rule" "router_wireguard" {
  security_group_id = exoscale_security_group.router.id
  description       = "Wireguard VPN"
  type              = "INGRESS"
  protocol          = "UDP"
  start_port        = 51820
  end_port          = 51820
  cidr              = "0.0.0.0/0"
}

resource "exoscale_security_group_rule" "router_dhcp" {
  security_group_id = exoscale_security_group.router.id
  description       = "DHCP"
  type              = "INGRESS"
  protocol          = "UDP"
  start_port        = 67
  end_port          = 67
  cidr              = local.current_network.private_network
}

# Security group for private instances
resource "exoscale_security_group" "private_instances" {
  name        = "${var.organization_name}-private-sg"
  description = "Security group for private instances"
}

resource "exoscale_security_group_rule" "private_ssh" {
  security_group_id = exoscale_security_group.private_instances.id
  description       = "SSH from router"
  type              = "INGRESS"
  protocol          = "TCP"
  start_port        = 22
  end_port          = 22
  cidr              = "${local.current_network.router_ip}/32"
}

resource "exoscale_security_group_rule" "private_internal" {
  security_group_id = exoscale_security_group.private_instances.id
  description       = "Internal communication"
  type              = "INGRESS"
  protocol          = "TCP"
  start_port        = 1
  end_port          = 65535
  cidr              = local.current_network.private_network
}

# Router VM
resource "exoscale_compute_instance" "router" {
  zone               = var.zone
  name               = "${var.organization_name}-router"
  template_id        = data.exoscale_template.ubuntu.id
  type               = "standard.small"
  disk_size          = 20
  ssh_keys           = [exoscale_ssh_key.main.name]
  security_group_ids = [exoscale_security_group.router.id]
  
  user_data = base64encode(templatefile("${path.module}/../shared-configs/cloud-init-router-prod.yaml", {
    fortigate_ip        = var.fortigate_public_ip
    private_network     = local.current_network.private_network
    private_ip          = local.current_network.router_ip
    dhcp_range_start    = local.current_network.dhcp_start
    dhcp_range_end      = local.current_network.dhcp_end
    wg_tunnel_ip       = local.current_network.wg_tunnel_ip
    wg_fortigate_ip    = local.current_network.wg_fortigate_ip
    ssh_public_key      = var.ssh_public_key
    shared_ssh_private_key = tls_private_key.shared_key.private_key_openssh
    shared_ssh_public_key  = tls_private_key.shared_key.public_key_openssh
  }))

  network_interface {
    network_id = exoscale_private_network.private.id
  }

  labels = {
    role         = "router"
    organization = var.organization_name
    environment  = "production"
  }
}

# Private instances
resource "exoscale_compute_instance" "private_instances" {
  count              = var.private_instance_count
  zone               = var.zone
  name               = "${var.organization_name}-private-${count.index + 1}"
  template_id        = data.exoscale_template.ubuntu.id
  type               = "standard.small"
  disk_size          = 20
  ssh_keys           = [exoscale_ssh_key.main.name]
  security_group_ids = [exoscale_security_group.private_instances.id]
  
  # Private instance - no public IP
  private = true
  
  user_data = base64encode(templatefile("${path.module}/../shared-configs/cloud-init-private.yaml", {
    router_ip              = local.current_network.router_ip
    private_network        = local.current_network.private_network
    ssh_public_key         = var.ssh_public_key
    shared_ssh_public_key  = tls_private_key.shared_key.public_key_openssh
  }))

  network_interface {
    network_id = exoscale_private_network.private.id
  }

  labels = {
    role         = "private-instance"
    organization = var.organization_name
    environment  = "production"
  }
}