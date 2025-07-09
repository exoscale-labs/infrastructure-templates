# Exoscale Zero Trust Multi-Organization Network Architecture

A complete **Zero Trust** network architecture solution for deploying multi-organization networks on Exoscale with centralized security control through FortiGate firewall.

## 🏗️ Quick Overview

```
Internet → FortiGate (Security Gateway) → Router (DHCP) → Private Instances
```

**Key Benefits:**
- 🔒 **Zero Trust**: Only FortiGate can access private instances
- ⚡ **Fast Deployment**: 2-3 minute boot times
- 🛡️ **Infrastructure Isolation**: No lateral movement possible
- 📊 **Centralized Monitoring**: All traffic through FortiGate

## 🚀 Quick Start

### 1. Setup Environment
```bash
git clone <repository-url>
cd sebastien-firewall
cp .env.example .env
# Edit .env with your Exoscale credentials
```

### 2. Test Architecture (Recommended)
```bash
cd 2-test-with-fortigate-sim/
terraform init
terraform apply -var="ssh_public_key=$(cat ~/.ssh/id_rsa.pub)"

# View testing instructions
terraform output testing_instructions
```

### 3. Production Deployment
```bash
cd 3-production-deployment/
export ORGANIZATION_NAME=er1
export FORTIGATE_PUBLIC_IP=your-fortigate-ip
terraform init
terraform apply -var="ssh_public_key=$(cat ~/.ssh/id_rsa.pub)"
```

## 📁 Project Structure

```
sebastien-firewall/
├── 2-test-with-fortigate-sim/  # 🎯 Complete test environment
├── 3-production-deployment/    # 🏭 Production deployment
│   └── fortigate-wireguard-config.txt  # FortiGate configuration
└── shared-configs/             # Cloud-init configurations
```

## 🧪 Testing

### SSH to Private Instances
```bash
# Get private IPs from DHCP leases
ssh -J ubuntu@<fortigate-ip> ubuntu@<router-ip> "sudo cat /var/lib/dhcp/dhcpd.leases | grep 'lease '"

# SSH via FortiGate
ssh ubuntu@<fortigate-ip> "sudo ssh -i /root/.ssh/shared_key ubuntu@<private-ip>"
```

### Validation Tests
```bash
# ✅ FortiGate can access private instances
ssh ubuntu@<fortigate-ip> "ping <private-ip>"

# ❌ Router cannot access private instances (security feature)
ssh -J ubuntu@<fortigate-ip> ubuntu@<router-ip> "ping <private-ip>"
```

## 🏢 Multi-Organization Support

| Organization | Private Network | Router IP | Tunnel |
|-------------|----------------|-----------|--------|
| ER1 | 10.18.11.0/24 | 10.18.11.1 | 192.168.100.2/30 |
| ER2 | 10.18.21.0/24 | 10.18.21.1 | 192.168.101.2/30 |
| ER3 | 10.18.31.0/24 | 10.18.31.1 | 192.168.102.2/30 |

## 🧹 Clean Up

```bash
terraform destroy -auto-approve
```

## 📝 Environment Variables

```bash
# Required
EXOSCALE_API_KEY=your-api-key
EXOSCALE_API_SECRET=your-api-secret

# For Production  
ORGANIZATION_NAME=er1
FORTIGATE_PUBLIC_IP=your-fortigate-ip
```

## 📚 Documentation

- **[ARCHITECTURE.md](ARCHITECTURE.md)** - Detailed technical documentation
- **[TESTING-GUIDE.md](TESTING-GUIDE.md)** - Complete testing procedures

## 🎯 Success Criteria

✅ FortiGate can SSH to private instances  
✅ Router cannot access private instances (Zero Trust)  
✅ Private instances have internet via FortiGate  

---

> **Note**: Router-to-private-instance isolation is an intentional Zero Trust security feature.
