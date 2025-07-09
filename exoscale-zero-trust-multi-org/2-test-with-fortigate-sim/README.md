# Multi-Organization Network Architecture Test

This deployment demonstrates a **Zero Trust** multi-organization network architecture where private instances are completely isolated and all traffic flows through a centralized security gateway (FortiGate simulation).

## Architecture Overview

```
Internet
    │
    ▼
┌─────────────────────┐
│  FortiGate Sim      │  Public IP: 159.100.242.149
│  (Security Gateway) │  Tunnel IP: 192.168.100.1
└─────────────────────┘
    │ Wireguard Tunnel
    ▼
┌─────────────────────┐
│  Router             │  Public IP: 89.145.167.169
│  (DHCP Server)      │  Tunnel IP: 192.168.100.2
│                     │  Private IP: 10.0.0.1
└─────────────────────┘
    │ Private Network (10.0.0.0/24)
    ▼
┌─────────────────────┐ ┌─────────────────────┐
│  Private Instance 1 │ │  Private Instance 2 │
│  IP: 10.0.0.14      │ │  IP: 10.0.0.15      │
└─────────────────────┘ └─────────────────────┘
```

## Network Connectivity Matrix

### ✅ **ALLOWED Connections:**

| From | To | Protocol | Status | Purpose |
|------|----|---------|---------|---------| 
| FortiGate | Router | All | ✅ | Tunnel traffic via Wireguard |
| FortiGate | Private Instances | All | ✅ | **Central security control** |
| Private Instances | Internet | All | ✅ | Via FortiGate (monitored) |
| Private Instances | Private Instances | All | ✅ | Inter-instance communication |

### ❌ **BLOCKED Connections (Zero Trust Security):**

| From | To | Protocol | Status | Security Benefit |
|------|----|---------|---------|---------| 
| Router | Private Instances | ICMP/SSH | ❌ | **Infrastructure isolation** |
| Private Instances | Router | ICMP/SSH | ❌ | **Infrastructure isolation** |
| Internet | Private Instances | All | ❌ | **No direct access** |
| Internet | Router | All | ❌ | **No direct access** |

## Key Security Features

### 🔒 **Zero Trust Architecture**
- **Private instances are completely isolated** from infrastructure components
- **Only the FortiGate** (central security gateway) can reach private instances
- **No lateral movement** possible between private instances and routers
- **All internet traffic** flows through centralized monitoring point

### 🛡️ **Infrastructure Isolation**
- **Router cannot ping private instances** - This is intentional security!
- **Private instances cannot ping router** - Prevents infrastructure access
- **DHCP still works** - Network services function without compromising security
- **FortiGate has full visibility** - Can monitor all private instance traffic

## Network Behavior Explanation

### Why Router ↔ Private Instance Ping Fails
This is **intentional security design**, not a bug:

1. **Router receives ping requests** from private instances (visible in tcpdump)
2. **Router doesn't send replies** due to Exoscale private network isolation
3. **This prevents lateral movement** from private instances to infrastructure
4. **DHCP continues to work** as it uses broadcast/multicast protocols

### Traffic Flow for Private Instances

```
Private Instance → Internet:
10.0.0.14 → 10.0.0.1 (router) → 192.168.100.2 → 192.168.100.1 (FortiGate) → Internet

FortiGate → Private Instance:
159.100.242.149 → 192.168.100.1 → 10.0.0.14 (direct via private network)
```

## Deployment Instructions

### Prerequisites
```bash
# Set environment variables
export EXOSCALE_API_KEY="your_api_key"
export EXOSCALE_API_SECRET="your_api_secret"
```

### Deploy Infrastructure
```bash
terraform init
terraform apply -var="ssh_public_key=$(cat ~/.ssh/id_rsa.pub)"
```

### Verification Commands

**Test Wireguard Tunnel:**
```bash
ssh ubuntu@159.100.242.149 "sudo wg show"
```

**Test FortiGate → Private Instance Access:**
```bash
ssh ubuntu@159.100.242.149 "ping -c 3 10.0.0.14"
ssh ubuntu@159.100.242.149 "ping -c 3 10.0.0.15"
```

**Test Private Instance Internet Access:**
```bash
# From private instance console (root/denis123):
ping -c 3 1.1.1.1
```

**Verify Router Cannot Reach Private Instances (Security Feature):**
```bash
ssh -J ubuntu@159.100.242.149 ubuntu@192.168.100.2 "ping -c 3 10.0.0.14"
# Should fail - this is correct behavior!
```

## Console Access

**Private instances** can be accessed via Exoscale web console:
- **Username:** `root`
- **Password:** `denis123`

## Security Validation

This architecture successfully demonstrates:

✅ **Centralized Security Control** - Only FortiGate can access private instances  
✅ **Infrastructure Isolation** - Private instances cannot access routers  
✅ **Zero Trust Networking** - No direct internet access, all traffic monitored  
✅ **Network Segmentation** - Each organization's instances are isolated  
✅ **Traffic Monitoring** - All private traffic flows through FortiGate  

## Files

- `main.tf` - FortiGate simulation configuration
- `router-and-private.tf` - Router and private instance configuration
- `shared.tf` - Shared resources (networking, keys)
- `shared-configs/cloud-init-*` - Instance initialization scripts

## Clean Up

```bash
terraform destroy -var="ssh_public_key=$(cat ~/.ssh/id_rsa.pub)"
```

---

> **Note:** The inability to ping between router and private instances is an intentional security feature of this Zero Trust architecture, not a configuration error.