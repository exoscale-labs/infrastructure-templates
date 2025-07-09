# Zero Trust Architecture Testing Guide

Comprehensive testing guide for the Zero Trust multi-organization network architecture.

## Prerequisites

### 1. Environment Setup
```bash
# Copy environment template
cp .env.example .env

# Edit .env with your credentials
EXOSCALE_API_KEY=your-api-key
EXOSCALE_API_SECRET=your-api-secret
```

### 2. Load Environment Variables
```bash
# From any deployment directory
set -a                    # Auto-export all variables
source ../.env           # Load variables from parent directory
set +a                   # Turn off auto-export

# Or set SSH key variable
export TF_VAR_ssh_public_key=$(cat ~/.ssh/id_rsa.pub)
```

### 3. SSH Key
```bash
# Generate if needed
ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa
```

## Quick Architecture Test

### Deploy Test Environment

#### Option A: Using Deploy Script (Recommended)
```bash
cd 2-test-with-fortigate-sim/
./deploy.sh

# Get comprehensive testing instructions
terraform output testing_instructions
```

#### Option B: Manual Terraform Commands
```bash
cd 2-test-with-fortigate-sim/
terraform init
terraform apply -var="ssh_public_key=$(cat ~/.ssh/id_rsa.pub)"

# Get comprehensive testing instructions
terraform output testing_instructions
```

## Zero Trust Architecture Validation

### ✅ What Should Work (Allowed Connections)

#### 1. FortiGate Can Access Private Instances
```bash
# Get private instance IPs from DHCP leases
ssh -J ubuntu@<fortigate-ip> ubuntu@192.168.100.2 "sudo cat /var/lib/dhcp/dhcpd.leases | grep 'lease '"

# Test FortiGate → Private instance ping
ssh ubuntu@<fortigate-ip> "ping -c 3 <private-ip>"
# Expected: SUCCESS

# Test FortiGate → Private instance SSH
ssh ubuntu@<fortigate-ip> "sudo ssh -i /root/.ssh/shared_key ubuntu@<private-ip> 'hostname'"
# Expected: SUCCESS (returns hostname)
```

#### 2. Private Instances Have Internet Access
```bash
# From private instance console (root/denis123)
ping -c 3 1.1.1.1
curl -s https://httpbin.org/ip
# Expected: SUCCESS, shows FortiGate's public IP
```

#### 3. Wireguard Tunnel Working
```bash
# Check tunnel status
ssh ubuntu@<fortigate-ip> "sudo wg show"
ssh -J ubuntu@<fortigate-ip> ubuntu@192.168.100.2 "sudo wg show"
# Expected: Shows active peer connections

# Test tunnel connectivity
ssh -J ubuntu@<fortigate-ip> ubuntu@192.168.100.2 "ping -c 3 192.168.100.1"
# Expected: SUCCESS
```

#### 4. DHCP Server Operational
```bash
# Check DHCP service
ssh -J ubuntu@<fortigate-ip> ubuntu@192.168.100.2 "sudo systemctl status isc-dhcp-server"
# Expected: Active and running

# Check lease assignments
ssh -J ubuntu@<fortigate-ip> ubuntu@192.168.100.2 "sudo cat /var/lib/dhcp/dhcpd.leases | grep -A 5 'lease '"
# Expected: Shows active IP leases
```

#### 5. Inter-Private Instance Communication
```bash
# From one private instance to another
# (via console access: root/denis123)
ping -c 3 <other-private-ip>
# Expected: SUCCESS
```

### ❌ What Should NOT Work (Zero Trust Security)

#### 1. Router Cannot Access Private Instances
```bash
# Test router → private instance ping
ssh -J ubuntu@<fortigate-ip> ubuntu@192.168.100.2 "ping -c 3 <private-ip>"
# Expected: TIMEOUT (Zero Trust security feature)

# Test router → private instance SSH
ssh -J ubuntu@<fortigate-ip> ubuntu@192.168.100.2 "ssh ubuntu@<private-ip>"
# Expected: TIMEOUT (Zero Trust security feature)
```

#### 2. Private Instances Cannot Access Router
```bash
# From private instance console (root/denis123)
ping -c 3 10.0.0.1
ssh ubuntu@10.0.0.1
# Expected: TIMEOUT (Zero Trust security feature)
```

#### 3. No Direct Internet Access
```bash
# Direct access to private instances should be impossible
ssh ubuntu@<private-ip>
# Expected: FAIL (no public IP)
```

## Comprehensive Testing Sequence

### Step 1: Deploy and Verify Basic Connectivity
```bash
cd 2-test-with-fortigate-sim/

# Deploy using script (recommended)
./deploy.sh

# Or deploy manually
terraform init
terraform apply -var="ssh_public_key=$(cat ~/.ssh/id_rsa.pub)"

# Test basic SSH access
ssh ubuntu@<fortigate-ip>
ssh -J ubuntu@<fortigate-ip> ubuntu@192.168.100.2
```

### Step 2: Verify Wireguard Tunnel
```bash
# Check tunnel establishment
ssh ubuntu@<fortigate-ip> "sudo wg show"
ssh -J ubuntu@<fortigate-ip> ubuntu@192.168.100.2 "sudo wg show"

# Test tunnel connectivity
ssh -J ubuntu@<fortigate-ip> ubuntu@192.168.100.2 "ping -c 3 192.168.100.1"
```

### Step 3: Verify DHCP and Private Instance Setup
```bash
# Check DHCP server
ssh -J ubuntu@<fortigate-ip> ubuntu@192.168.100.2 "sudo systemctl status isc-dhcp-server"

# Get private instance IPs
ssh -J ubuntu@<fortigate-ip> ubuntu@192.168.100.2 "sudo cat /var/lib/dhcp/dhcpd.leases | grep 'lease '"
```

### Step 4: Test Zero Trust Security
```bash
# Test FortiGate access (should work)
ssh ubuntu@<fortigate-ip> "ping -c 3 <private-ip>"
ssh ubuntu@<fortigate-ip> "sudo ssh -i /root/.ssh/shared_key ubuntu@<private-ip> 'hostname'"

# Test router isolation (should fail)
ssh -J ubuntu@<fortigate-ip> ubuntu@192.168.100.2 "ping -c 3 <private-ip>"
```

### Step 5: Verify Internet Access Through FortiGate
```bash
# From private instance console (root/denis123)
ping -c 3 1.1.1.1
curl -s https://httpbin.org/ip

# Should show FortiGate's public IP, confirming monitored internet access
```

## Performance Testing

### Boot Time Validation
```bash
# Time private instance deployment
time terraform apply -target='exoscale_compute_instance.private_instances[0]'

# Expected: ~2-3 minutes for private instance to be SSH accessible
```

### Network Performance
```bash
# Test FortiGate → Private latency
ssh ubuntu@<fortigate-ip> "ping -c 10 <private-ip>"
# Expected: Sub-millisecond latency

# Test throughput via tunnel
ssh -J ubuntu@<fortigate-ip> ubuntu@192.168.100.2 "iperf3 -s" &
ssh ubuntu@<fortigate-ip> "iperf3 -c 192.168.100.2 -t 10"
```

## Troubleshooting Common Issues

### DHCP Server Not Starting
```bash
# Check netplan configuration
ssh -J ubuntu@<fortigate-ip> ubuntu@192.168.100.2 "sudo netplan try"

# Check interface status
ssh -J ubuntu@<fortigate-ip> ubuntu@192.168.100.2 "ip addr show eth1"

# Restart DHCP service
ssh -J ubuntu@<fortigate-ip> ubuntu@192.168.100.2 "sudo systemctl restart isc-dhcp-server"
```

### FortiGate Cannot SSH to Private Instances
```bash
# Check iptables forwarding rules
ssh -J ubuntu@<fortigate-ip> ubuntu@192.168.100.2 "sudo iptables -L FORWARD -n -v"

# Check routing
ssh ubuntu@<fortigate-ip> "ip route show | grep 10.0.0"
```

### Private Instance Cannot Respond to FortiGate
```bash
# From private instance console, check routing
ip route show
ip route get 192.168.100.1

# Should show route via 10.0.0.1
```

### Cloud-Init Issues
```bash
# Check cloud-init status
ssh ubuntu@<instance-ip> "sudo cloud-init status --long"

# Check logs
ssh ubuntu@<instance-ip> "sudo cat /var/log/cloud-init-output.log"
ssh -J ubuntu@<fortigate-ip> ubuntu@192.168.100.2 "sudo cat /var/log/test-router-setup.log"
```

## Production Deployment Testing

### Multi-Organization Deployment
```bash
cd 3-production-deployment/

# Deploy for ER1 using script
export ORGANIZATION_NAME=er1
export FORTIGATE_PUBLIC_IP=your-fortigate-ip
./deploy.sh

# Or deploy manually
terraform init
terraform apply -var="ssh_public_key=$(cat ~/.ssh/id_rsa.pub)"

# Test same Zero Trust validation steps
```

### Organization Isolation Testing
```bash
# Deploy multiple organizations using script
export ORGANIZATION_NAME=er2
./deploy.sh

# Or deploy manually
terraform apply -var="ssh_public_key=$(cat ~/.ssh/id_rsa.pub)"

# Verify organizations cannot access each other's resources
```

## Success Criteria Checklist

### ✅ Security Validation
- [ ] FortiGate can ping private instances
- [ ] FortiGate can SSH to private instances  
- [ ] Router cannot ping private instances (Zero Trust)
- [ ] Router cannot SSH to private instances (Zero Trust)
- [ ] Private instances cannot access router (Zero Trust)
- [ ] Private instances have internet access via FortiGate
- [ ] All internet traffic shows FortiGate's public IP as origin

### ✅ Performance Validation
- [ ] Private instances boot in 2-3 minutes
- [ ] DHCP assigns IP addresses immediately
- [ ] FortiGate → Private latency is sub-millisecond
- [ ] Wireguard tunnel is persistent and stable

### ✅ Operational Validation
- [ ] DHCP server starts reliably
- [ ] Cloud-init completes without errors
- [ ] SSH access works as expected
- [ ] Terraform deployment is repeatable

## Clean Up

### Option A: Using Destroy Script (Recommended)
```bash
# Destroy test environment
./destroy.sh
```

### Option B: Manual Terraform Commands
```bash
# Destroy test environment
terraform destroy -var="ssh_public_key=$(cat ~/.ssh/id_rsa.pub)" -auto-approve

# Clean up state files
rm -f terraform.tfstate*
```

---

> **Note**: The Zero Trust architecture intentionally blocks router-to-private-instance connectivity. This is a security feature that ensures only the FortiGate security gateway can access private instances, preventing lateral movement and maintaining centralized security control.

This testing guide validates the complete Zero Trust architecture with comprehensive security and performance testing! 🚀