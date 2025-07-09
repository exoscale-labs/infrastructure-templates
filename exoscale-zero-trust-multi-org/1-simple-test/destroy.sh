#!/bin/bash

# Destroy script for simple-test deployment
# This script safely destroys all resources created by the simple test

set -e

echo "🗑️  Destroying simple-test deployment..."

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

# Destroy resources
echo ""
echo "🚀 Destroying resources..."
terraform destroy -auto-approve -var="ssh_public_key=$TF_VAR_ssh_public_key" || {
    echo "⚠️  Warning: Some resources may not have been destroyed properly."
    echo "Please check the Exoscale console and clean up manually if needed."
}

echo ""
echo "✅ Simple test destruction completed!"
echo "💡 To deploy again, run: ./deploy.sh"