#!/bin/bash

# Master destroy script for all deployments
# This script destroys all test environments safely

set -e

echo "🗑️  Master Destroy Script - All Deployments"
echo "============================================="
echo ""

# Get the directory of this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Load environment variables
if [ -f ".env" ]; then
    echo "📝 Loading environment variables..."
    set -a
    source .env
    set +a
else
    echo "❌ Error: .env file not found"
    echo "Please ensure .env exists with your Exoscale credentials"
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

# List of deployment directories
DEPLOYMENTS=(
    "1-simple-test"
    "2-test-with-fortigate-sim"
    "3-production-deployment"
)

echo "🔍 Checking for active deployments..."
echo ""

# Check which deployments have active resources
ACTIVE_DEPLOYMENTS=()
for deployment in "${DEPLOYMENTS[@]}"; do
    if [ -f "$deployment/terraform.tfstate" ]; then
        # Check if state file has resources
        if [ -s "$deployment/terraform.tfstate" ]; then
            echo "📋 Found active deployment: $deployment"
            ACTIVE_DEPLOYMENTS+=("$deployment")
        fi
    fi
done

if [ ${#ACTIVE_DEPLOYMENTS[@]} -eq 0 ]; then
    echo "✅ No active deployments found. Nothing to destroy."
    exit 0
fi

echo ""
echo "⚠️  The following deployments will be DESTROYED:"
for deployment in "${ACTIVE_DEPLOYMENTS[@]}"; do
    echo "   - $deployment"
done

echo ""
echo "❗ This action is IRREVERSIBLE and will destroy ALL resources!"
echo ""
read -p "❓ Are you absolutely sure you want to destroy all deployments? (yes/no): " confirm

if [ "$confirm" != "yes" ]; then
    echo "❌ Destruction cancelled."
    exit 0
fi

echo ""
echo "🚀 Starting destruction of all deployments..."
echo ""

# Destroy each deployment
for deployment in "${ACTIVE_DEPLOYMENTS[@]}"; do
    echo "🗑️  Destroying $deployment..."
    cd "$deployment"
    
    # Run terraform destroy
    terraform destroy -auto-approve -var="ssh_public_key=$TF_VAR_ssh_public_key" || {
        echo "⚠️  Warning: Some resources in $deployment may not have been destroyed properly."
        echo "Please check the Exoscale console and clean up manually if needed."
    }
    
    # Back up state files
    if [ -f "terraform.tfstate" ]; then
        mv terraform.tfstate terraform.tfstate.backup.$(date +%Y%m%d_%H%M%S)
        echo "✅ $deployment state file backed up"
    fi
    
    if [ -f "terraform.tfstate.backup" ]; then
        mv terraform.tfstate.backup terraform.tfstate.backup.$(date +%Y%m%d_%H%M%S)
        echo "✅ $deployment backup state file archived"
    fi
    
    cd ..
    echo "✅ $deployment destroyed"
    echo ""
done

echo ""
echo "🎉 All deployments destroyed successfully!"
echo ""
echo "📝 Summary:"
echo "   - All Exoscale resources destroyed"
echo "   - State files backed up with timestamps"
echo "   - Ready for fresh deployments"
echo ""
echo "💡 To deploy again:"
echo "   - Simple test: cd 1-simple-test && ./deploy.sh"
echo "   - Full test: cd 2-test-with-fortigate-sim && ./deploy.sh"
echo "   - Production: cd 3-production-deployment && ./deploy.sh"