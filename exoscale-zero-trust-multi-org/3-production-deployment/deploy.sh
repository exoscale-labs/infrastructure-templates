#!/bin/bash

# Production deployment script

set -e

echo "🚀 Production Deployment"
echo "========================"
echo "This deploys the production router and private instances for your organization."
echo ""

# Check if .env file exists in parent directory
if [ ! -f ../.env ]; then
    echo "❌ Error: .env file not found in parent directory"
    echo "Please create ../.env with production credentials"
    exit 1
fi

# Load environment variables
set -a
source ../.env
set +a

# Check credentials
if [ -z "$EXOSCALE_API_KEY" ] || [ -z "$EXOSCALE_API_SECRET" ]; then
    echo "❌ Error: API credentials not set"
    exit 1
fi

# Check required production variables
if [ -z "$ORGANIZATION_NAME" ]; then
    echo "❌ Error: ORGANIZATION_NAME not set in .env"
    echo "Set to one of: er1, er2, er3"
    exit 1
fi

if [ -z "$FORTIGATE_PUBLIC_IP" ]; then
    echo "❌ Error: FORTIGATE_PUBLIC_IP not set in .env"
    echo "Set to your FortiGate's public IP address"
    exit 1
fi

# Check SSH key
if [ ! -f ~/.ssh/id_rsa.pub ]; then
    echo "❌ Error: SSH public key not found"
    exit 1
fi

# Export for Terraform
export EXOSCALE_API_KEY
export EXOSCALE_API_SECRET

# Configuration
ZONE=${EXOSCALE_ZONE:-"ch-gva-2"}
INSTANCE_COUNT=${PRIVATE_INSTANCE_COUNT:-"2"}

echo "📋 Production Configuration:"
echo "   Zone: $ZONE"
echo "   Organization: $ORGANIZATION_NAME"
echo "   FortiGate IP: $FORTIGATE_PUBLIC_IP"
echo "   Private instances: $INSTANCE_COUNT"
echo ""

# Confirmation prompt
echo "⚠️  WARNING: This will deploy production infrastructure!"
echo "   This will create real resources and incur costs."
echo ""
read -p "Continue with production deployment? (yes/no): " confirm

if [ "$confirm" != "yes" ]; then
    echo "Deployment cancelled."
    exit 0
fi

echo ""
echo "🔧 Initializing Terraform..."
terraform init

echo "📋 Planning production deployment..."
terraform plan \
    -var="zone=$ZONE" \
    -var="organization_name=$ORGANIZATION_NAME" \
    -var="ssh_public_key=$(cat ~/.ssh/id_rsa.pub)" \
    -var="fortigate_public_ip=$FORTIGATE_PUBLIC_IP" \
    -var="private_instance_count=$INSTANCE_COUNT"

echo ""
echo "🚀 Deploying production infrastructure..."
terraform apply -auto-approve \
    -var="zone=$ZONE" \
    -var="organization_name=$ORGANIZATION_NAME" \
    -var="ssh_public_key=$(cat ~/.ssh/id_rsa.pub)" \
    -var="fortigate_public_ip=$FORTIGATE_PUBLIC_IP" \
    -var="private_instance_count=$INSTANCE_COUNT"

# Get outputs
ROUTER_IP=$(terraform output -raw router_public_ip)

echo ""
echo "📊 Production Deployment Results:"
terraform output

echo ""
echo "⏳ Waiting for instances to initialize (90 seconds)..."
sleep 90

echo ""
echo "🔧 Getting router's Wireguard public key..."
ROUTER_PUBKEY=$(ssh -o ConnectTimeout=20 -o StrictHostKeyChecking=no ubuntu@$ROUTER_IP "sudo cat /etc/wireguard/public.key" 2>/dev/null || echo "")

if [ -n "$ROUTER_PUBKEY" ]; then
    echo "✅ Router public key: $ROUTER_PUBKEY"
    echo ""
    echo "📋 FortiGate Configuration Required:"
    echo "   1. Add this router's public key to your FortiGate"
    echo "   2. Configure FortiGate to accept connections from: $ROUTER_IP"
    echo "   3. Set allowed IPs for this router's private network"
    echo ""
    echo "   See ../docs/fortigate-configuration.md for detailed instructions"
else
    echo "⚠️  Could not get router public key. Instance may still be initializing."
    echo "   Get it later with: ssh ubuntu@$ROUTER_IP 'sudo cat /etc/wireguard/public.key'"
fi

echo ""
echo "✅ Production Infrastructure Deployed!"
echo "====================================="
echo ""
echo "🌐 Access Information:"
echo "   Router: ssh ubuntu@$ROUTER_IP"
echo "   Private instances: Accessible only from router"
echo ""
echo "📋 Next Steps:"
echo "   1. Configure FortiGate with router's public key"
echo "   2. Update router with FortiGate's public key"
echo "   3. Start Wireguard tunnel: sudo systemctl start wg-quick@wg0"
echo "   4. Test connectivity from private instances"
echo ""
echo "📚 Documentation:"
echo "   - See ../docs/ for detailed configuration guides"
echo "   - Check router logs: ssh ubuntu@$ROUTER_IP 'sudo cat /var/log/production-router-setup.log'"
echo ""
echo "⚠️  Remember: This is production infrastructure!"
echo "   Monitor resources and costs in the Exoscale console"