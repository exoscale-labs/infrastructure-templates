#!/bin/bash

# Destroy script for test-with-fortigate-sim deployment
# This script safely destroys all resources created by the terraform configuration

set -e

echo "🗑️  Destroying test-with-fortigate-sim deployment..."

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

# Check if terraform state exists
if [ ! -f "terraform.tfstate" ]; then
    echo "⚠️  No terraform state found. Nothing to destroy."
    exit 0
fi

# Show what will be destroyed
echo ""
echo "🔍 Checking current resources..."
terraform refresh -var="ssh_public_key=$TF_VAR_ssh_public_key" || {
    echo "⚠️  Warning: Could not refresh state. Continuing with destroy..."
}

# Show plan
echo ""
echo "📋 Destruction plan:"
terraform plan -destroy -var="ssh_public_key=$TF_VAR_ssh_public_key" || {
    echo "⚠️  Warning: Could not generate destroy plan. Continuing..."
}

# Confirm destruction
echo ""
read -p "❓ Are you sure you want to destroy all resources? (yes/no): " confirm

if [ "$confirm" != "yes" ]; then
    echo "❌ Destruction cancelled."
    exit 0
fi

# Destroy resources
echo ""
echo "🚀 Destroying resources..."
terraform destroy -auto-approve -var="ssh_public_key=$TF_VAR_ssh_public_key" || {
    echo "⚠️  Warning: Some resources may not have been destroyed properly."
    echo "Please check the Exoscale console and clean up manually if needed."
}

# Clean up state files
echo ""
echo "🧹 Cleaning up state files..."
if [ -f "terraform.tfstate" ]; then
    mv terraform.tfstate terraform.tfstate.backup.$(date +%Y%m%d_%H%M%S)
    echo "✅ State file backed up"
fi

if [ -f "terraform.tfstate.backup" ]; then
    mv terraform.tfstate.backup terraform.tfstate.backup.$(date +%Y%m%d_%H%M%S)
    echo "✅ Backup state file archived"
fi

# Remove lock file if it exists
if [ -f ".terraform.lock.hcl" ]; then
    rm -f .terraform.lock.hcl
    echo "✅ Lock file removed"
fi

echo ""
echo "✅ Destruction completed successfully!"
echo ""
echo "📝 Summary:"
echo "   - All Exoscale resources destroyed"
echo "   - State files backed up with timestamp"
echo "   - Ready for fresh deployment"
echo ""
echo "💡 To deploy again, run: ./deploy.sh"