# Combined outputs and testing instructions

output "ssh_commands" {
  description = "SSH commands"
  value = {
    fortigate = "ssh ubuntu@${exoscale_compute_instance.fortigate_sim.public_ip_address}"
    router    = "ssh ubuntu@${exoscale_compute_instance.router.public_ip_address}"
    note      = "Private instances accessible only from router"
  }
}

output "test_summary" {
  description = "Test environment summary"
  value = {
    architecture = "Private Instances → Router → FortiGate Sim → Internet"
    validation   = "Router blocks direct internet, only routes through FortiGate"
    network      = local.config.private_network
  }
}

output "testing_instructions" {
  description = "Step-by-step testing guide"
  value = <<-EOT
    
    🔍 TESTING GUIDE - Zero Trust Multi-Organization Network Architecture
    =====================================================================
    
    1. VERIFY WIREGUARD TUNNEL ESTABLISHMENT
    ----------------------------------------
    ssh ubuntu@${exoscale_compute_instance.fortigate_sim.public_ip_address} "sudo wg show"
    
    Expected: Should show a peer with router's public key and allowed IPs: 192.168.100.2/32, 10.0.0.0/24
    
    2. GET PRIVATE INSTANCE IPS FROM DHCP LEASES
    ---------------------------------------------
    ssh -J ubuntu@${exoscale_compute_instance.fortigate_sim.public_ip_address} ubuntu@192.168.100.2 "sudo cat /var/lib/dhcp/dhcpd.leases | grep 'lease '"
    
    Expected: Should show lease entries like "lease 10.0.0.10 {" and "lease 10.0.0.11 {"
    
    3. VERIFY FORTIGATE CAN PING PRIVATE INSTANCES (ZERO TRUST)
    ------------------------------------------------------------
    # Replace with actual IPs from step 2:
    ssh ubuntu@${exoscale_compute_instance.fortigate_sim.public_ip_address} "ping -c 3 <PRIVATE_IP_1>"
    ssh ubuntu@${exoscale_compute_instance.fortigate_sim.public_ip_address} "ping -c 3 <PRIVATE_IP_2>"
    
    Expected: Should SUCCEED - FortiGate has direct access to private instances
    
    4. VERIFY ROUTER CANNOT ACCESS PRIVATE INSTANCES (SECURITY ISOLATION)
    -----------------------------------------------------------------------
    ssh -J ubuntu@${exoscale_compute_instance.fortigate_sim.public_ip_address} ubuntu@192.168.100.2 "ping -c 3 <PRIVATE_IP_1>"
    
    Expected: Should FAIL - This is correct Zero Trust behavior!
    
    5. VERIFY PRIVATE INSTANCES CANNOT ACCESS ROUTER (SECURITY ISOLATION)
    -----------------------------------------------------------------------
    # From private instance console (root/denis123):
    ping -c 3 ${local.config.router_ip}
    
    Expected: Should FAIL - Private instances isolated from infrastructure
    
    6. VERIFY PRIVATE INSTANCES HAVE INTERNET ACCESS VIA FORTIGATE
    ---------------------------------------------------------------
    # From private instance console (root/denis123):
    ping -c 3 1.1.1.1
    
    Expected: Should SUCCEED - Internet access through FortiGate monitoring
    
    7. VERIFY DHCP SERVER ON ROUTER
    --------------------------------
    ssh -J ubuntu@${exoscale_compute_instance.fortigate_sim.public_ip_address} ubuntu@192.168.100.2 "sudo systemctl status isc-dhcp-server"
    
    Expected: Should be active and running, serving DHCP to private network
    
    8. VERIFY PRIVATE INSTANCES GET DHCP ADDRESSES
    -----------------------------------------------
    # From private instance console (root/denis123):
    ip addr show eth0
    
    Expected: Should show 10.0.0.x/24 address from DHCP
    
    9. VERIFY ROUTER SETUP COMPLETED
    ---------------------------------
    ssh -J ubuntu@${exoscale_compute_instance.fortigate_sim.public_ip_address} ubuntu@192.168.100.2 "sudo cat /var/log/test-router-setup.log | tail -10"
    
    Expected: Should show "Test router setup completed" and Wireguard status
    
    10. VERIFY ROUTER CAN REACH FORTIGATE VIA TUNNEL
    ------------------------------------------------
    ssh -J ubuntu@${exoscale_compute_instance.fortigate_sim.public_ip_address} ubuntu@192.168.100.2 "ping -c 3 192.168.100.1"
    
    Expected: Should succeed - router can reach FortiGate via Wireguard tunnel
    
    11. VERIFY PRIVATE INSTANCES INTER-COMMUNICATION
    -------------------------------------------------
    # From private instance 1 console (root/denis123):
    ping -c 3 <OTHER_PRIVATE_IP>
    
    Expected: Should SUCCEED - Private instances can communicate with each other
    
    ✅ SUCCESS CRITERIA (ZERO TRUST ARCHITECTURE)
    ==============================================
    - Tests 1, 2, 3, 6, 7, 8, 9, 10, 11 should SUCCEED
    - Tests 4, 5 should FAIL (demonstrating Zero Trust security isolation)
    - Only FortiGate can access private instances directly
    - Private instances are completely isolated from infrastructure components
    - All internet traffic from private instances flows through FortiGate monitoring
    
    🎯 ZERO TRUST ARCHITECTURE VALIDATION
    ======================================
    This setup validates a Zero Trust multi-organization cloud architecture where:
    - Private instances are completely isolated from infrastructure components
    - Only the FortiGate (central security gateway) can access private instances
    - Router provides DHCP services but cannot access private instances
    - All internet traffic is monitored and filtered through FortiGate
    - No lateral movement is possible between private instances and infrastructure
    
    🔒 SECURITY FEATURES CONFIRMED
    ==============================
    ✅ Infrastructure Isolation: Router ↔ Private Instance ping fails (intentional)
    ✅ Centralized Security Control: Only FortiGate can access private instances
    ✅ Zero Trust Networking: No direct internet access, all traffic monitored
    ✅ Network Segmentation: Private instances isolated from infrastructure
    ✅ Traffic Monitoring: All private traffic flows through FortiGate
    
    📝 CONSOLE ACCESS
    =================
    Private instances can be accessed via Exoscale web console:
    - Username: root
    - Password: denis123
    
    🔗 SSH ACCESS TO PRIVATE INSTANCES
    ==================================
    After getting private instance IPs from DHCP leases (step 2), you can SSH to them:
    
    # Direct SSH from FortiGate (using shared key):
    ssh ubuntu@${exoscale_compute_instance.fortigate_sim.public_ip_address} "sudo ssh -i /root/.ssh/shared_key ubuntu@<PRIVATE_IP>"
    
    # Example for 10.0.0.10:
    ssh ubuntu@${exoscale_compute_instance.fortigate_sim.public_ip_address} "sudo ssh -i /root/.ssh/shared_key ubuntu@10.0.0.10"
    
    # Or using FortiGate as jump host:
    ssh -J ubuntu@${exoscale_compute_instance.fortigate_sim.public_ip_address} -i ~/.ssh/id_rsa ubuntu@<PRIVATE_IP>
    
  EOT
}