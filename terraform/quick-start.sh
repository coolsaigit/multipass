#!/bin/bash

# Quick Start Script for RKE2 Cluster Deployment
# This script helps you get started quickly

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}"
echo "╔════════════════════════════════════════════════════════╗"
echo "║     RKE2 Cluster Deployment - Quick Start             ║"
echo "╚════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# Check prerequisites
echo -e "${YELLOW}Checking prerequisites...${NC}\n"

if ! command -v terraform &> /dev/null; then
    echo -e "${RED}✗ Terraform not found${NC}"
    echo "Install with: brew install terraform"
    exit 1
fi
echo -e "${GREEN}✓ Terraform found${NC}"

if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}✗ kubectl not found${NC}"
    echo "Install with: brew install kubectl"
    exit 1
fi
echo -e "${GREEN}✓ kubectl found${NC}"

# Check Rancher
export KUBECONFIG="$SCRIPT_DIR/../scripts/_out/kubeconfig"
if ! kubectl get -n cattle-system svc rancher &> /dev/null; then
    echo -e "${RED}✗ Rancher not running${NC}"
    echo "Start Rancher with: cd ../scripts && ./install-rancher.sh"
    exit 1
fi
echo -e "${GREEN}✓ Rancher is running${NC}\n"

# Select environment
echo -e "${BLUE}Select environment:${NC}"
echo "  1) dev"
echo "  2) staging"
echo "  3) production"
read -p "Enter choice [1-3]: " ENV_CHOICE

case $ENV_CHOICE in
    1) ENV="dev" ;;
    2) ENV="staging" ;;
    3) ENV="production" ;;
    *) echo "Invalid choice"; exit 1 ;;
esac

cd "$SCRIPT_DIR/$ENV"

# Check if terraform.tfvars exists
if [ ! -f terraform.tfvars ]; then
    echo -e "\n${YELLOW}Creating terraform.tfvars from example...${NC}"
    cp terraform.tfvars.example terraform.tfvars
    
    echo -e "${YELLOW}"
    echo "╔════════════════════════════════════════════════════════╗"
    echo "║  ACTION REQUIRED: Configure Rancher API Token          ║"
    echo "╚════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo "Steps:"
    echo "  1. Open Rancher UI: https://localhost:8443"
    echo "  2. Click user icon (top right) → Account & API Keys"
    echo "  3. Create API Key → Copy the token"
    echo "  4. Edit terraform.tfvars and set rancher_token"
    echo ""
    echo -e "${BLUE}Opening editor...${NC}"
    sleep 2
    ${EDITOR:-vim} terraform.tfvars
fi

# Select deployment type
echo -e "\n${BLUE}Select cluster type:${NC}"
echo "  1) Local ARM (Multipass) - for Mac ARM, automated node creation"
echo "  2) Custom (Bring Your Own Nodes) - for existing VMs/bare metal"
echo "  3) AWS (Automated provisioning)"
read -p "Enter choice [1-3]: " CLUSTER_CHOICE

case $CLUSTER_CHOICE in
    1) 
        sed -i.bak 's/cloud_provider = .*/cloud_provider = "custom"/' terraform.tfvars
        echo -e "${GREEN}✓ Configured for local ARM cluster${NC}"
        
        # Check if multipass is installed
        if ! command -v multipass &> /dev/null; then
            echo -e "${YELLOW}⚠ Multipass not found. Install with: brew install --cask multipass${NC}"
            read -p "Continue anyway? (y/N): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                exit 1
            fi
        fi
        ;;
    2) 
        sed -i.bak 's/cloud_provider = .*/cloud_provider = "custom"/' terraform.tfvars
        echo -e "${GREEN}✓ Configured for custom cluster${NC}"
        ;;
    3) 
        sed -i.bak 's/cloud_provider = .*/cloud_provider = "aws"/' terraform.tfvars
        echo -e "${YELLOW}⚠ Make sure to configure AWS credentials in terraform.tfvars${NC}"
        ;;
esac

# Initialize Terraform
echo -e "\n${BLUE}Initializing Terraform...${NC}"
terraform init

# Plan
echo -e "\n${BLUE}Planning deployment...${NC}"
terraform plan -out=tfplan

# Confirm
echo -e "\n${YELLOW}Ready to deploy cluster. Continue? (yes/no)${NC}"
read -p "> " CONFIRM

if [[ ! $CONFIRM =~ ^[Yy][Ee][Ss]$ ]]; then
    echo "Deployment cancelled"
    exit 0
fi

# Apply
echo -e "\n${BLUE}Creating cluster...${NC}"
terraform apply tfplan

# Show outputs
echo -e "\n${GREEN}╔════════════════════════════════════════════════════════╗"
echo "║            Deployment Complete!                        ║"
echo "╚════════════════════════════════════════════════════════╝${NC}\n"

terraform output access_instructions

# For custom clusters, show registration command or offer automated registration
if [[ $CLUSTER_CHOICE == "1" ]]; then
    # Local ARM Multipass cluster
    echo -e "\n${YELLOW}╔════════════════════════════════════════════════════════╗"
    echo "║  NEXT STEP: Create and register ARM nodes            ║"
    echo "╚════════════════════════════════════════════════════════╝${NC}\n"
    
    if command -v multipass &> /dev/null && [ -f "./multipass-rke-nodes.sh" ]; then
        echo "Automated option:"
        echo -e "  ${BLUE}./multipass-rke-nodes.sh create${NC}  # Create ARM VMs"
        echo -e "  ${BLUE}./multipass-rke-nodes.sh register${NC}  # Register with Rancher"
        echo ""
        read -p "Create and register nodes now? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            echo -e "\n${BLUE}Creating ARM Multipass VMs...${NC}"
            ./multipass-rke-nodes.sh create
            
            echo -e "\n${BLUE}Registering nodes with Rancher...${NC}"
            ./multipass-rke-nodes.sh register
        fi
    else
        echo "Manual option:"
        echo "Run this command on each node:"
        echo -e "${BLUE}"
        terraform output -raw registration_command
        echo -e "${NC}\n"
    fi
elif [[ $CLUSTER_CHOICE == "2" ]]; then
    # Custom cluster (BYON)
    echo -e "\n${YELLOW}╔════════════════════════════════════════════════════════╗"
    echo "║  NEXT STEP: Register your nodes                       ║"
    echo "╚════════════════════════════════════════════════════════╝${NC}\n"
    echo "Run this command on each node:"
    echo -e "${BLUE}"
    terraform output -raw registration_command
    echo -e "${NC}\n"
fi

echo -e "${GREEN}✓ All done!${NC}\n"

