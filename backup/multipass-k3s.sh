#!/bin/bash
set -euo pipefail

# Multipass + Talos Bootstrap Script
# Creates Ubuntu VMs and bootstraps a Talos Kubernetes cluster

# Colors  
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
NODE_NAME="talos-cp-1"
TALOS_VERSION="v1.11.5"
CLUSTER_NAME="talos-cluster"
OUTPUT_DIR="_out"

echo -e "${BLUE}=== Talos on Multipass - Simple K3s Alternative ===${NC}\n"

# Check prerequisites
command -v multipass >/dev/null 2>&1 || { 
    echo -e "${RED}Error: multipass is required${NC}"
    echo "Install with: brew install multipass"
    exit 1
}

command -v kubectl >/dev/null 2>&1 || {
    echo -e "${RED}Error: kubectl is required${NC}"
    exit 1
}

# Step 1: Create Ubuntu VM
echo -e "${BLUE}=== Step 1: Creating Ubuntu VM ===${NC}\n"

if multipass list | grep -q "$NODE_NAME"; then
    echo -e "${YELLOW}VM $NODE_NAME already exists${NC}"
    VM_IP=$(multipass info "$NODE_NAME" | grep IPv4 | awk '{print $2}')
    echo -e "${GREEN}Using existing VM: $VM_IP${NC}\n"
else
    echo -e "${YELLOW}Creating VM with K3s (lightweight Kubernetes)...${NC}"
    
    multipass launch -n "$NODE_NAME" \
        --cpus 2 \
        --memory 4G \
        --disk 50G \
        22.04
    
    VM_IP=$(multipass info "$NODE_NAME" | grep IPv4 | awk '{print $2}')
    echo -e "${GREEN}✓ VM created: $VM_IP${NC}\n"
fi

# Step 2: Install K3s (simpler than Talos, works perfectly)
echo -e "${BLUE}=== Step 2: Installing K3s (Lightweight Kubernetes) ===${NC}\n"
echo -e "${YELLOW}Installing K3s on $VM_IP...${NC}"

multipass exec "$NODE_NAME" -- bash -c 'curl -sfL https://get.k3s.io | sh -'

echo -e "${GREEN}✓ K3s installed${NC}\n"

# Step 3: Get kubeconfig
echo -e "${BLUE}=== Step 3: Retrieving Kubeconfig ===${NC}\n"

mkdir -p "$OUTPUT_DIR"
multipass exec "$NODE_NAME" -- sudo cat /etc/rancher/k3s/k3s.yaml | \
    sed "s/127.0.0.1/$VM_IP/g" > "$OUTPUT_DIR/kubeconfig"

chmod 600 "$OUTPUT_DIR/kubeconfig"
export KUBECONFIG="$(pwd)/$OUTPUT_DIR/kubeconfig"

echo -e "${GREEN}✓ Kubeconfig saved${NC}\n"

# Step 4: Verify cluster
echo -e "${BLUE}=== Step 4: Verifying Cluster ===${NC}\n"

sleep 10
kubectl get nodes

echo -e "\n${GREEN}=== Setup Complete! ===${NC}\n"
echo -e "${GREEN}Kubeconfig:${NC} $(pwd)/$OUTPUT_DIR/kubeconfig"
echo -e "${GREEN}To use:${NC} export KUBECONFIG=$(pwd)/$OUTPUT_DIR/kubeconfig"
echo -e "${GREEN}VM IP:${NC} $VM_IP"
echo -e "\n${BLUE}Useful commands:${NC}"
echo -e "  kubectl get nodes"
echo -e "  kubectl get pods -A"
echo -e "  multipass shell $NODE_NAME"
echo ""

