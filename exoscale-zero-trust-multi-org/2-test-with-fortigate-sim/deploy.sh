#!/bin/bash

# Deploy script for test-with-fortigate-sim
# This script deploys the complete test architecture with FortiGate simulation

set -e

echo "🚀 Deploying test-with-fortigate-sim architecture..."

# Get the directory of this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Load environment variables
if [ -f "../.env" ]; then
    echo "📝 Loading environment variables..."
    set -a
    source ../.env
    set +a
else
    echo "❌ Error: .env file not found in parent directory"
    echo "Please ensure ../.env exists with your Exoscale credentials"
    exit 1
fi

# Verify environment variables
if [ -z "$EXOSCALE_API_KEY" ] || [ -z "$EXOSCALE_API_SECRET" ]; then
    echo "❌ Error: Missing Exoscale credentials in .env file"
    echo "Please set EXOSCALE_API_KEY and EXOSCALE_API_SECRET"
    exit 1
fi

# Set SSH key variable
if [ -f ~/.ssh/id_rsa.pub ]; then
    export TF_VAR_ssh_public_key=$(cat ~/.ssh/id_rsa.pub)
else
    echo "❌ Error: SSH public key not found at ~/.ssh/id_rsa.pub"
    echo "Please generate an SSH key with: ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa"
    exit 1
fi

# Initialize terraform if needed
if [ ! -d ".terraform" ]; then
    echo "🔧 Initializing Terraform..."
    terraform init
fi

# Validate configuration
echo ""
echo "✅ Validating Terraform configuration..."
terraform validate

# Show plan
echo ""
echo "📋 Deployment plan:"
terraform plan -var="ssh_public_key=$TF_VAR_ssh_public_key"

# Confirm deployment
echo ""
read -p "❓ Do you want to proceed with deployment? (yes/no): " confirm

if [ "$confirm" != "yes" ]; then
    echo "❌ Deployment cancelled."
    exit 0
fi

# Deploy
echo ""
echo "🚀 Deploying infrastructure..."
terraform apply -auto-approve -var="ssh_public_key=$TF_VAR_ssh_public_key"

# Show outputs
echo ""
echo "📋 Deployment completed! Here are the connection details:"
echo ""
terraform output

echo ""
echo "🎉 Deployment successful!"
echo ""
echo "📝 What was deployed:"
echo "   - FortiGate simulation (with Wireguard)"
echo "   - Router VM (blocks direct internet access)"
echo "   - 2 Private instances (no public IP)"
echo "   - Wireguard tunnel between FortiGate and Router"
echo ""
echo "🔧 Architecture:"
echo "   Private Instances → Router → FortiGate Sim → Internet"
echo ""
echo "⏳ Note: Cloud-init setup may take 2-3 minutes to complete"
echo "   Check setup logs with: sudo cat /var/log/test-router-setup.log"
echo ""
echo "🧪 To test the architecture, follow the TESTING-GUIDE.md"
echo "🗑️  To destroy resources, run: ./destroy.sh"