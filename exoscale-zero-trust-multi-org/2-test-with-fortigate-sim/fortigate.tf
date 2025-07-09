# FortiGate simulation component
# This creates the FortiGate simulation instance with its own security group

# Security group for FortiGate simulation
resource "exoscale_security_group" "fortigate_sim" {
  name        = "${local.clean_org_name}-fortigate-sim-sg"
  description = "Security group for FortiGate simulation"
}

resource "exoscale_security_group_rule" "fortigate_ssh" {
  security_group_id = exoscale_security_group.fortigate_sim.id
  description       = "SSH access"
  type              = "INGRESS"
  protocol          = "TCP"
  start_port        = 22
  end_port          = 22
  cidr              = "0.0.0.0/0"
}

resource "exoscale_security_group_rule" "fortigate_wireguard" {
  security_group_id = exoscale_security_group.fortigate_sim.id
  description       = "Wireguard"
  type              = "INGRESS"
  protocol          = "UDP"
  start_port        = 51820
  end_port          = 51820
  cidr              = "0.0.0.0/0"
}

# FortiGate simulation instance
resource "exoscale_compute_instance" "fortigate_sim" {
  zone               = var.zone
  name               = "${local.clean_org_name}-fortigate-sim"
  template_id        = data.exoscale_template.ubuntu.id
  type               = "standard.small"
  disk_size          = 20
  ssh_keys           = [exoscale_ssh_key.test_key.name]
  security_group_ids = [exoscale_security_group.fortigate_sim.id]
  
  user_data = base64encode(templatefile("${path.module}/../shared-configs/cloud-init-fortigate-sim.yaml", {
    ssh_public_key           = var.ssh_public_key
    shared_ssh_private_key   = jsonencode(tls_private_key.shared_key.private_key_pem)
    shared_ssh_public_key    = tls_private_key.shared_key.public_key_openssh
  }))

  labels = {
    role = "fortigate-sim"
    environment = "test"
  }
}

# FortiGate outputs
output "fortigate_sim_ip" {
  description = "FortiGate simulation IP"
  value       = exoscale_compute_instance.fortigate_sim.public_ip_address
}