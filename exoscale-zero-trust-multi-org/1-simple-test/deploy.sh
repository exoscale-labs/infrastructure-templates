#!/bin/bash

# Simple test deployment script

set -e

echo "🧪 Simple Test Deployment"
echo "========================="
echo "This validates your Exoscale credentials and basic setup."
echo ""

# Check if .env file exists in parent directory
if [ ! -f ../.env ]; then
    echo "❌ Error: .env file not found in parent directory"
    echo "Please create ../.env with your credentials:"
    echo "  EXOSCALE_API_KEY=your-key"
    echo "  EXOSCALE_API_SECRET=your-secret"
    exit 1
fi

# Load environment variables
set -a
source ../.env
set +a

# Check credentials
if [ -z "$EXOSCALE_API_KEY" ] || [ -z "$EXOSCALE_API_SECRET" ]; then
    echo "❌ Error: API credentials not set in .env file"
    exit 1
fi

# Check SSH key
if [ ! -f ~/.ssh/id_rsa.pub ]; then
    echo "❌ Error: SSH public key not found"
    echo "Generate with: ssh-keygen -t rsa"
    exit 1
fi

# Export for Terraform
export EXOSCALE_API_KEY
export EXOSCALE_API_SECRET

echo "✅ Credentials loaded"
echo "✅ SSH key found"
echo ""

# Initialize and deploy
echo "🔧 Initializing Terraform..."
terraform init

echo "📋 Planning deployment..."
terraform plan -var="ssh_public_key=$(cat ~/.ssh/id_rsa.pub)"

echo "🚀 Deploying simple test instance..."
terraform apply -auto-approve -var="ssh_public_key=$(cat ~/.ssh/id_rsa.pub)"

echo ""
echo "📊 Results:"
terraform output

echo ""
echo "✅ Simple test completed successfully!"
echo ""
echo "This validates that:"
echo "  - Your Exoscale API credentials work"
echo "  - Terraform can create instances"
echo "  - SSH access is configured"
echo ""
echo "🎯 Next steps:"
echo "  - Test SSH connection to the instance"
echo "  - Run full architecture test: cd ../test-with-fortigate-sim && ./deploy.sh"
echo "  - Deploy production: cd ../production-deployment && ./deploy.sh"
echo ""
echo "🧹 To clean up: terraform destroy -auto-approve"