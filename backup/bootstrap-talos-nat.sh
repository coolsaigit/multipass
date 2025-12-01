#!/bin/bash
set -euo pipefail

# Talos Bootstrap Script for NAT Networking
# This script bootstraps a single-node Talos cluster using NAT with port forwarding

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration - single node for simplicity
NODE_NAME="rancher-server-1"
TALOS_PORT="50010"  # localhost port forwarded to VM's 50000
CLUSTER_NAME="talos-cluster"
OUTPUT_DIR="_out"
TALOS_VERSION="${TALOS_VERSION:-v1.11.5}"
# For NAT, the VM gets 10.0.2.15 internally, but we access via localhost
CLUSTER_ENDPOINT="https://localhost:6443"

echo -e "${BLUE}=== Talos Single-Node Cluster Bootstrap (NAT) ===${NC}\n"

# Check prerequisites
command -v talosctl >/dev/null 2>&1 || { 
    echo -e "${RED}Error: talosctl is required${NC}"
    echo "Install with: brew install siderolabs/tap/talosctl"
    exit 1
}

command -v kubectl >/dev/null 2>&1 || {
    echo -e "${RED}Error: kubectl is required${NC}"
    exit 1
}

# Check if VM is running
echo -e "${YELLOW}Checking VM...${NC}"
RUNNING_VMS=$(VBoxManage list runningvms | grep -c "$NODE_NAME" || echo "0")
if [ "$RUNNING_VMS" -lt 1 ]; then
    echo -e "${RED}Error: $NODE_NAME is not running${NC}"
    echo -e "${YELLOW}Run: ./vbox-talos.sh start${NC}"
    exit 1
fi
echo -e "${GREEN}✓ $NODE_NAME is running${NC}\n"

# Step 1: Generate machine configurations
echo -e "${BLUE}=== Step 1: Generating Machine Configurations ===${NC}\n"
mkdir -p "$OUTPUT_DIR"

talosctl gen config "$CLUSTER_NAME" "$CLUSTER_ENDPOINT" --output-dir "$OUTPUT_DIR" --force

if [ $? -ne 0 ]; then
    echo -e "${RED}✗ Failed to generate configurations${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Configurations generated${NC}\n"

# Step 2: Apply config to node
echo -e "${BLUE}=== Step 2: Configuring Talos Node ===${NC}\n"
echo -e "${YELLOW}Waiting for VM to boot with NAT DHCP (10.0.2.15)...${NC}"
sleep 20

echo -e "${YELLOW}Applying configuration via localhost:${TALOS_PORT}...${NC}"

# Apply config - NAT VMs get 10.0.2.15 automatically
# We access via localhost:50010 which forwards to VM's 50000
talosctl apply-config --insecure --nodes "127.0.0.1:${TALOS_PORT}" \
    --file "$OUTPUT_DIR/controlplane.yaml"

if [ $? -ne 0 ]; then
    echo -e "${RED}✗ Failed to apply configuration${NC}"
    echo -e "${YELLOW}Make sure port ${TALOS_PORT} is forwarded to VM's port 50000${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Configuration applied${NC}"
echo -e "${YELLOW}VM will reboot and install Talos. This may take 2-3 minutes...${NC}\n"

# Step 3: Bootstrap etcd
echo -e "${BLUE}=== Step 3: Bootstrapping etcd ===${NC}\n"
echo -e "${YELLOW}Waiting for node to be ready...${NC}"

max_attempts=60
attempt=0
while [ $attempt -lt $max_attempts ]; do
    if talosctl --talosconfig "$OUTPUT_DIR/talosconfig" \
        --nodes "127.0.0.1:${TALOS_PORT}" bootstrap 2>/dev/null; then
        echo -e "${GREEN}✓ etcd bootstrapped${NC}\n"
        break
    fi
    sleep 5
    attempt=$((attempt + 1))
    if [ $((attempt % 6)) -eq 0 ]; then
        echo -e "  Waiting... ($attempt/$max_attempts)"
    fi
done

if [ $attempt -eq $max_attempts ]; then
    echo -e "${YELLOW}⚠  Bootstrap may have failed, but continuing...${NC}\n"
fi

# Step 4: Get kubeconfig
echo -e "${BLUE}=== Step 4: Retrieving Kubeconfig ===${NC}\n"
sleep 30

talosctl --talosconfig "$OUTPUT_DIR/talosconfig" \
    --nodes "127.0.0.1:${TALOS_PORT}" kubeconfig .

if [ $? -eq 0 ]; then
    export KUBECONFIG="$(pwd)/kubeconfig"
    echo -e "${GREEN}✓ Kubeconfig retrieved${NC}\n"
    
    # Step 5: Verify cluster
    echo -e "${BLUE}=== Step 5: Verifying Cluster ===${NC}\n"
    echo -e "${YELLOW}Waiting for node to be ready...${NC}"
    
    max_attempts=40
    attempt=0
    while [ $attempt -lt $max_attempts ]; do
        READY_NODES=$(kubectl get nodes --no-headers 2>/dev/null | grep -c " Ready " || echo "0")
        if [ "$READY_NODES" -ge 1 ]; then
            break
        fi
        sleep 5
        attempt=$((attempt + 1))
        if [ $((attempt % 4)) -eq 0 ]; then
            echo -e "  Ready nodes: $READY_NODES/1 ($attempt/$max_attempts)"
        fi
    done
    
    echo ""
    kubectl get nodes
    echo ""
    
    echo -e "${BLUE}=== Setup Complete! ===${NC}\n"
    echo -e "${GREEN}Kubeconfig:${NC} $(pwd)/kubeconfig"
    echo -e "${GREEN}To use:${NC} export KUBECONFIG=$(pwd)/kubeconfig"
    echo -e "${GREEN}Talos API:${NC} talosctl --nodes 127.0.0.1:${TALOS_PORT}"
    echo ""
else
    echo -e "${RED}✗ Failed to retrieve kubeconfig${NC}"
    exit 1
fi

