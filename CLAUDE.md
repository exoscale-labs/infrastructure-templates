# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This repository contains infrastructure templates and reference architectures for deploying common customer setups on Exoscale cloud platform. The main template is a Zero Trust multi-organization network architecture with centralized security control.

## Environment Setup

### Prerequisites
- Valid Exoscale API credentials
- SSH key pair generated (required for all deployments)
- Terraform (for templates that use it)

### Environment Variables
```bash
# Create .env file in project root or template directory
cp exoscale-zero-trust-multi-org/.env.example .env

# Required for all deployments
EXOSCALE_API_KEY=your-api-key
EXOSCALE_API_SECRET=your-api-secret

# Template-specific variables (see individual template documentation)
ORGANIZATION_NAME=org1  # Generic organization naming
FORTIGATE_PUBLIC_IP=your-fortigate-ip
EXOSCALE_ZONE=ch-gva-2
PRIVATE_INSTANCE_COUNT=2
```

## Common Commands

### Development Workflow
```bash
# Load environment variables in deployment directories
set -a && source ../.env && set +a

# Standard deployment workflow (for Terraform-based templates)
terraform init
terraform plan -var="ssh_public_key=$(cat ~/.ssh/id_rsa.pub)"
terraform apply -var="ssh_public_key=$(cat ~/.ssh/id_rsa.pub)"
terraform destroy -var="ssh_public_key=$(cat ~/.ssh/id_rsa.pub)" -auto-approve
```

### Deployment Commands (Zero Trust Template)
```bash
# 1. Credential validation
cd exoscale-zero-trust-multi-org/1-simple-test
./deploy.sh

# 2. Complete test environment
cd exoscale-zero-trust-multi-org/2-test-with-fortigate-sim
./deploy.sh

# 3. Production deployment
cd exoscale-zero-trust-multi-org/3-production-deployment
./deploy.sh

# Destroy all deployments
cd exoscale-zero-trust-multi-org
./destroy-all.sh
```

### Testing Commands
```bash
# Get testing instructions after deployment
terraform output testing_instructions

# Test security isolation (should fail - security feature)
ssh -J ubuntu@<gateway-ip> ubuntu@<router-ip> "ping -c 3 <private-ip>"

# Test authorized access (should work)
ssh ubuntu@<gateway-ip> "sudo ssh -i /root/.ssh/shared_key ubuntu@<private-ip> 'hostname'"

# Check DHCP leases
ssh -J ubuntu@<gateway-ip> ubuntu@<router-ip> "sudo cat /var/lib/dhcp/dhcpd.leases | grep 'lease '"

# Monitor network tunnels
ssh ubuntu@<gateway-ip> "sudo wg show"
```

## Architecture Overview

### Zero Trust Network Model
```
Internet → Security Gateway → Router (DHCP) → Private Instances
```

**Key Security Principles:**
- **Infrastructure Isolation**: Router cannot access private instances (intentional)
- **Centralized Control**: Only security gateway can access private instances
- **No Lateral Movement**: Organizations cannot access each other's resources
- **Complete Traffic Visibility**: All internet traffic flows through security gateway

### Multi-Organization Support
Templates support multiple isolated organizations with separate networks and tunnel endpoints.

## Code Organization

### Template Structure
```
template-name/
├── 1-simple-test/              # Credential validation
├── 2-test-with-environment/    # Complete test environment
├── 3-production-deployment/    # Production deployment
├── shared-configs/             # Common configurations
├── README.md                   # Template documentation
├── ARCHITECTURE.md             # Technical architecture details
└── TESTING-GUIDE.md           # Testing procedures
```

### Configuration Files
- `shared.tf`: Common resources (networks, SSH keys, data sources)
- `*.tf`: Infrastructure definitions
- `outputs.tf`: Deployment outputs and connection information
- `cloud-init-*.yaml`: Instance initialization configurations
- `deploy.sh`: Automated deployment scripts
- `destroy.sh`: Clean resource destruction

## Performance Optimizations

### Deployment Times
- **Test Environment**: 2-3 minutes (minimal configuration)
- **Production Environment**: 2-3 minutes (secure + optimized)
- **Performance Focus**: Fast deployment with minimal overhead

### Network Performance
- **Tunnel Latency**: Sub-millisecond between components
- **Service Assignment**: Instant IP allocation
- **Persistent Connections**: Stable tunnel maintenance

## Security Features

### Zero Trust Validation
- Router-to-private connectivity is **intentionally blocked**
- Security gateway has exclusive access to private instances
- All security policies enforced at gateway level
- Complete traffic monitoring and logging

### Network Isolation
- Private instances have no public IP addresses
- Internet access only through security gateway monitoring
- No lateral movement between infrastructure components
- Organization-level network isolation

## Important Notes

- Router cannot access private instances - this is a **security feature**, not a bug
- All deployments require SSH public key variable
- Test environments use simulated security gateways for complete validation
- Production requires actual security appliances with public IP
- Environment variables are loaded from parent directory (.env)
- State files are automatically backed up during destruction
- **Use generic naming**: Avoid specific customer names or data in code and documentation
- Follow the contributing guidelines in README.md for consistent template structure

## Troubleshooting

### Common Issues
1. **Service not starting**: Check configuration file consistency
2. **Gateway timeout**: Verify forwarding rules and routing
3. **Private response timeout**: Ensure tunnel routing is configured
4. **Initialization failures**: Check cloud-init logs

### Diagnostic Commands
```bash
# Check tunnel status
sudo wg show

# Verify routing
ip route show
ip route get <tunnel-network>

# Monitor services
sudo systemctl status <service-name>
sudo cat /var/lib/dhcp/dhcpd.leases

# Check firewall rules
sudo iptables -L FORWARD -n -v
```

All common issues have been resolved and are included in current configurations.