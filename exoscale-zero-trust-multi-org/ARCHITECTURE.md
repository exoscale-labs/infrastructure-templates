# Zero Trust Multi-Organization Network Architecture

## Architecture Overview

This architecture provides a **Zero Trust** security model for multi-organization networks with centralized security control through FortiGate.

```
┌─── Organization ER1 ────┐    ┌─── Organization ER2 ────┐    ┌─── Organization ER3 ────┐
│ Private Network         │    │ Private Network         │    │ Private Network         │
│ 10.18.11.0/24          │    │ 10.18.21.0/24          │    │ 10.18.31.0/24          │
│                        │    │                        │    │                        │
│ ┌─────────────────┐    │    │ ┌─────────────────┐    │    │ ┌─────────────────┐    │
│ │ Private Instance│    │    │ │ Private Instance│    │    │ │ Private Instance│    │
│ │ 10.18.11.10     │    │    │ │ 10.18.21.10     │    │    │ │ 10.18.31.10     │    │
│ │ ❌ No Public IP │    │    │ │ ❌ No Public IP │    │    │ │ ❌ No Public IP │    │
│ │ 🔒 Isolated     │    │    │ │ 🔒 Isolated     │    │    │ │ 🔒 Isolated     │    │
│ └─────────────────┘    │    │ └─────────────────┘    │    │ └─────────────────┘    │
│          │             │    │          │             │    │          │             │
│          v             │    │          v             │    │          v             │
│ ┌─────────────────┐    │    │ ┌─────────────────┐    │    │ ┌─────────────────┐    │
│ │ Router VM       │    │    │ │ Router VM       │    │    │ │ Router VM       │    │
│ │ 10.18.11.1      │    │    │ │ 10.18.21.1      │    │    │ │ 10.18.31.1      │    │
│ │ ✅ Public IP    │    │    │ │ ✅ Public IP    │    │    │ │ ✅ Public IP    │    │
│ │ 🔒 Cannot SSH   │    │    │ │ 🔒 Cannot SSH   │    │    │ │ 🔒 Cannot SSH   │    │
│ │    to Private   │    │    │ │    to Private   │    │    │ │    to Private   │    │
│ └─────────────────┘    │    │ └─────────────────┘    │    │ └─────────────────┘    │
└─────────────┬──────────┘    └─────────────┬──────────┘    └─────────────┬──────────┘
              │                             │                             │
              │ WireGuard Tunnel            │ WireGuard Tunnel            │ WireGuard Tunnel
              │ 192.168.100.0/30            │ 192.168.101.0/30            │ 192.168.102.0/30
              │                             │                             │
              └─────────────┬───────────────┴─────────────┬───────────────┘
                            │                             │
                            v                             v
                       ┌─────────────────────────────────────┐
                       │         FortiGate Gateway          │
                       │      (Centralized Security)        │
                       │                                     │
                       │  ✅ All tunnel termination         │
                       │  ✅ Security policy enforcement    │
                       │  ✅ Traffic monitoring             │
                       │  ✅ Single internet access point   │
                       │  🔒 Direct SSH to private instances│
                       └─────────────────┬───────────────────┘
                                         │
                                         v
                                   [ Internet ]
```

## Zero Trust Security Model

### **Key Zero Trust Principles**

1. **🛡️ Infrastructure Isolation**
   - Private instances are **completely isolated** from infrastructure components
   - Router VMs cannot access private instances (intentional security feature)
   - No lateral movement possible between infrastructure and workloads

2. **🎯 Centralized Security Control**
   - **Only FortiGate** can access private instances directly
   - All security policies enforced at the FortiGate level
   - Single point of security control and monitoring

3. **🚫 No Lateral Movement**
   - Private instances cannot access router infrastructure
   - Router cannot access private instances
   - Organizations cannot access each other's resources

4. **👁️ Complete Traffic Visibility**
   - All internet traffic flows through FortiGate
   - Comprehensive logging and monitoring
   - No security bypass routes possible

### **Network Connectivity Matrix**

| **From** | **To** | **Status** | **Security Benefit** |
|----------|--------|------------|----------------------|
| **FortiGate** | Private Instances | ✅ **ALLOWED** | Centralized security control |
| **Private Instances** | Internet | ✅ **ALLOWED** | Via FortiGate (monitored) |
| **Private Instances** | Private Instances | ✅ **ALLOWED** | Inter-workload communication |
| **Router** | Private Instances | ❌ **BLOCKED** | **Infrastructure isolation** |
| **Private Instances** | Router | ❌ **BLOCKED** | **Infrastructure isolation** |
| **Internet** | Private Instances | ❌ **BLOCKED** | No direct access |

> **Important**: Router-to-private-instance connectivity is **intentionally blocked** for security. This is not a bug - it's a Zero Trust feature.


## 🔧 Technical Implementation

### **Router VM Configuration**

```bash
# Key iptables rules enabling Zero Trust
iptables -A FORWARD -i eth1 -o wg0 -j ACCEPT          # Private → FortiGate
iptables -A FORWARD -i wg0 -o eth1 -j ACCEPT          # FortiGate → Private
iptables -t nat -A POSTROUTING -o wg0 -j MASQUERADE   # NAT via tunnel

# Block direct internet access
iptables -A OUTPUT -o eth0 -j DROP                     # Block direct internet
iptables -I OUTPUT -o eth0 -p tcp --dport 22 -j ACCEPT # Allow SSH management
```

### **Private Instance Configuration**

```bash
# Essential network setup
ip route add default via 10.0.0.1 dev eth0           # Default via router
ip route add 192.168.100.0/24 via 10.0.0.1 dev eth0  # FortiGate tunnel access

# Minimal firewall (all firewalls disabled for testing)
systemctl disable ufw
iptables -P INPUT ACCEPT
iptables -P FORWARD ACCEPT
iptables -P OUTPUT ACCEPT
```

### **FortiGate Integration**

```bash
# Wireguard configuration
[Interface]
PrivateKey = <private-key>
Address = 192.168.100.1/30
ListenPort = 51820

[Peer]
PublicKey = <router-public-key>
AllowedIPs = 192.168.100.2/32, 10.0.0.0/24
Endpoint = <router-public-ip>:51820
PersistentKeepalive = 25
```

## 🧪 Testing & Validation

### **Comprehensive Testing Framework**

The architecture includes a complete testing suite that validates:

#### **✅ Working Scenarios**
1. **Wireguard Tunnel**: `sudo wg show` shows active tunnel
2. **FortiGate → Private SSH**: Direct SSH access for security control
3. **Private → Internet**: Traffic flows through FortiGate monitoring
4. **DHCP Service**: Automatic IP assignment to private instances
5. **Inter-Private Communication**: Workload-to-workload connectivity

#### **❌ Blocked Scenarios (Security Validation)**
1. **Router → Private SSH**: Confirms infrastructure isolation
2. **Private → Router SSH**: Confirms no lateral movement
3. **Direct Internet Access**: Confirms centralized control

### **Testing Commands**

```bash
# 1. Verify Zero Trust isolation
ssh -J ubuntu@<fortigate-ip> ubuntu@<router-ip> "ping -c 3 <private-ip>"
# Expected: TIMEOUT (security feature)

# 2. Verify FortiGate can access private instances
ssh ubuntu@<fortigate-ip> "sudo ssh -i /root/.ssh/shared_key ubuntu@<private-ip> 'hostname'"
# Expected: SUCCESS

# 3. Verify internet access monitoring
ssh ubuntu@<fortigate-ip> "curl -s https://httpbin.org/ip | jq -r .origin"
# Expected: FortiGate's public IP

# 4. Verify DHCP lease management
ssh -J ubuntu@<fortigate-ip> ubuntu@<router-ip> "sudo cat /var/lib/dhcp/dhcpd.leases | grep 'lease '"
# Expected: Active IP leases
```

## 🏢 Production Deployment

### **Multi-Organization Networks**

| Organization | Private Network | Router IP | Tunnel Endpoint |
|-------------|----------------|-----------|-----------------|
| ER1 | 10.18.11.0/24 | 10.18.11.1 | 192.168.100.2/30 |
| ER2 | 10.18.21.0/24 | 10.18.21.1 | 192.168.101.2/30 |
| ER3 | 10.18.31.0/24 | 10.18.31.1 | 192.168.102.2/30 |

### **Deployment Commands**
```bash
cd 3-production-deployment/
export ORGANIZATION_NAME=er1  # or er2, er3
export FORTIGATE_PUBLIC_IP=your-fortigate-ip
terraform apply -var="ssh_public_key=$(cat ~/.ssh/id_rsa.pub)"
```

## 🛠️ Troubleshooting Guide

### **Common Issues & Solutions**

#### **1. DHCP Server Not Starting**
```bash
# Symptoms
sudo systemctl status isc-dhcp-server
# Status: failed

# Root Cause
# Netplan configuration error: dhcp4/dhcp6 overrides mismatch

# Solution (already fixed in configs)
# Changed dhcp6-overrides: use-routes: false to true
```

#### **2. FortiGate Cannot SSH to Private Instances**
```bash
# Symptoms
ssh ubuntu@<fortigate-ip> "ssh <private-ip>"
# Connection timeout

# Root Cause
# Router blocking NEW connections from wg0 to eth1

# Solution (already fixed)
iptables -A FORWARD -i wg0 -o eth1 -j ACCEPT
```

#### **3. Private Instance Cannot Respond to FortiGate**
```bash
# Symptoms
# SSH connections timeout, no response packets

# Root Cause
# Missing route to FortiGate tunnel network

# Solution (already fixed)
ip route add 192.168.100.0/24 via 10.0.0.1 dev eth0
```

### **Diagnostic Commands**

```bash
# Check DHCP leases
sudo cat /var/lib/dhcp/dhcpd.leases | grep 'lease '

# Verify tunnel connectivity
sudo wg show
ping -c 3 192.168.100.1

# Check routing tables
ip route show
ip route get 192.168.100.1

# Monitor tunnel traffic
sudo wg show all transfer

# Check firewall rules
sudo iptables -L FORWARD -n -v
```

---

> **Note**: This Zero Trust architecture intentionally blocks router-to-private-instance connectivity.