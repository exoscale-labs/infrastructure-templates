# Production deployment outputs

output "router_public_ip" {
  description = "Public IP of the router VM"
  value       = exoscale_compute_instance.router.public_ip_address
}

output "router_private_ip" {
  description = "Private IP of the router VM"
  value       = local.current_network.router_ip
}

output "private_instance_ips" {
  description = "Private IP addresses of the instances"
  value       = [for instance in exoscale_compute_instance.private_instances : instance.ipv6_address]
}

output "network_configuration" {
  description = "Network configuration for the organization"
  value = {
    organization      = var.organization_name
    private_network   = local.current_network.private_network
    router_ip        = local.current_network.router_ip
    dhcp_range       = "${local.current_network.dhcp_start} - ${local.current_network.dhcp_end}"
    wireguard_tunnel = local.current_network.wg_tunnel_ip
    fortigate_ip     = var.fortigate_public_ip
  }
}

output "ssh_commands" {
  description = "SSH commands to access instances"
  value = {
    router = "ssh ubuntu@${exoscale_compute_instance.router.public_ip_address}"
    note   = "Private instances accessible only from router VM"
  }
}

output "deployment_summary" {
  description = "Summary of the production deployment"
  value = {
    architecture     = "Private Instances → Router → FortiGate → Internet"
    organization     = var.organization_name
    network         = local.current_network.private_network
    validation      = "Router enforces security policies, all traffic via FortiGate"
    security_groups = "Isolated security groups for router and private instances"
  }
}

output "testing_instructions" {
  description = "Production testing and validation commands"
  value = <<EOT

🔍 PRODUCTION DEPLOYMENT VALIDATION - ${upper(var.organization_name)}
============================================================

1. VERIFY ROUTER CONNECTIVITY
-----------------------------
ssh ubuntu@${exoscale_compute_instance.router.public_ip_address}

Expected: Should connect successfully to the router VM

2. VERIFY WIREGUARD TUNNEL TO FORTIGATE
----------------------------------------
ssh ubuntu@${exoscale_compute_instance.router.public_ip_address} "sudo wg show"

Expected: Should show established tunnel to FortiGate at ${var.fortigate_public_ip}

3. VERIFY ROUTER BLOCKS DIRECT INTERNET
----------------------------------------
ssh ubuntu@${exoscale_compute_instance.router.public_ip_address} "ping -c 3 8.8.8.8"

Expected: Should FAIL - router cannot reach internet directly

4. VERIFY ROUTER CAN REACH FORTIGATE VIA TUNNEL
------------------------------------------------
ssh ubuntu@${exoscale_compute_instance.router.public_ip_address} "ping -c 3 ${local.current_network.wg_fortigate_ip}"

Expected: Should succeed - router can reach FortiGate via Wireguard tunnel

5. VERIFY ROUTER HAS INTERNET VIA FORTIGATE
--------------------------------------------
ssh ubuntu@${exoscale_compute_instance.router.public_ip_address} "curl -s --max-time 10 https://httpbin.org/ip | jq -r .origin"

Expected: Should return FortiGate's public IP (${var.fortigate_public_ip})

6. VERIFY DHCP SERVER ON ROUTER
--------------------------------
ssh ubuntu@${exoscale_compute_instance.router.public_ip_address} "sudo systemctl status isc-dhcp-server"

Expected: Should be active and running, serving DHCP to private network

7. VERIFY PRIVATE INSTANCES VIA ROUTER
---------------------------------------
ssh ubuntu@${exoscale_compute_instance.router.public_ip_address} "ssh -o StrictHostKeyChecking=no ${local.current_network.dhcp_start} 'hostname'"

Expected: Should connect to private instance via router

8. VERIFY END-TO-END INTERNET ACCESS FOR PRIVATE INSTANCES
-----------------------------------------------------------
ssh ubuntu@${exoscale_compute_instance.router.public_ip_address} "ssh -o StrictHostKeyChecking=no ${local.current_network.dhcp_start} 'curl -s --max-time 15 https://httpbin.org/ip | jq -r .origin'"

Expected: Should return FortiGate's public IP, proving: Private → Router → FortiGate → Internet

✅ SUCCESS CRITERIA
===================
- Tests 1, 2, 4, 5, 6, 7, 8 should SUCCEED
- Test 3 should FAIL (demonstrating security isolation)
- All traffic from private instances to internet flows through: Private → Router → FortiGate → Internet
- No direct internet access bypasses the security architecture

🎯 PRODUCTION ARCHITECTURE VALIDATION
=====================================
This validates the production multi-organization architecture where:
- Organization ${upper(var.organization_name)} instances are isolated in private network ${local.current_network.private_network}
- All internet traffic is forced through the centralized FortiGate security gateway
- Router VM enforces network policies and provides DHCP services for the organization
- No direct internet access is possible, ensuring all traffic is monitored and filtered

Network Details:
- Private Network: ${local.current_network.private_network}
- Router IP: ${local.current_network.router_ip}
- DHCP Range: ${local.current_network.dhcp_start} - ${local.current_network.dhcp_end}
- Wireguard Tunnel: ${local.current_network.wg_tunnel_ip}
- FortiGate Endpoint: ${local.current_network.wg_fortigate_ip}

EOT
}