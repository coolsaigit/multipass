#!/bin/bash
# Multipass k3s Cluster Management Script
# Usage:
#   ./scripts/multipass-cluster.sh create    - Create 3-node k3s cluster
#   ./scripts/multipass-cluster.sh delete    - Delete the cluster
#   ./scripts/multipass-cluster.sh status    - Show cluster status
#   ./scripts/multipass-cluster.sh kubeconfig - Show kubeconfig setup instructions

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
NODES=("node1" "node2" "node3")
MASTER_NODE="node1"
WORKER_NODES=("node2" "node3")
KUBECONFIG_FILE="$HOME/.kube/multipass-k3s.yaml"
# KUBECONFIG_FILE="~/.kube/multipass-k3s.yaml"
K3S_VERSION=""  # Empty = latest, or specify like "v1.28.0+k3s1"

# Node specifications
CPU_CORES=4
MEMORY="16G"
DISK="200G"
IMAGE="jammy"

# Functions
print_usage() {
    echo "Usage: $0 {create|delete|status|kubeconfig}"
    echo ""
    echo "Commands:"
    echo "  create     - Create a 3-node k3s cluster"
    echo "  delete     - Delete the entire cluster"
    echo "  status     - Show cluster status"
    echo "  kubeconfig - Show kubeconfig setup instructions"
    exit 1
}

check_multipass() {
    if ! command -v multipass &> /dev/null; then
        echo -e "${RED}Error: multipass is not installed${NC}"
        echo "Install with: brew install --cask multipass"
        exit 1
    fi
}

check_kubectl() {
    if ! command -v kubectl &> /dev/null; then
        echo -e "${YELLOW}Warning: kubectl is not installed${NC}"
        echo "Install with: brew install kubectl"
    fi
}

get_master_ip() {
    multipass info "$MASTER_NODE" 2>/dev/null | grep IPv4 | awk '{print $2}' || echo ""
}

create_cluster() {
    echo -e "${BLUE}=== Creating 3-node k3s Cluster ===${NC}\n"
    
    check_multipass
    check_kubectl
    
    # Check if nodes already exist
    EXISTING_NODES=$(multipass list --format csv 2>/dev/null | grep -E "node1|node2|node3" | cut -d, -f1 || echo "")
    if [ -n "$EXISTING_NODES" ]; then
        echo -e "${RED}Error: Nodes already exist:${NC}"
        echo "$EXISTING_NODES"
        echo -e "${YELLOW}Run '$0 delete' first to remove existing nodes${NC}"
        exit 1
    fi
    
    # Step 1: Launch all nodes in parallel
    echo -e "${YELLOW}Step 1: Creating all Multipass VMs in parallel...${NC}"
    echo -e "  Launching ${#NODES[@]} nodes simultaneously...\n"
    
    # Function to launch a single node
    launch_node() {
        local node=$1
        local temp_file=$(mktemp)
        
        echo -e "  [${node}] Starting creation (${CPU_CORES} CPUs, ${MEMORY} RAM, ${DISK} disk)..."
        
        # Launch node (suppress deprecated warning)
        multipass launch "$IMAGE" \
            --name "$node" \
            --cpus "$CPU_CORES" \
            --memory "$MEMORY" \
            --disk "$DISK" > "$temp_file" 2>&1
        
        local exit_code=$?
        
        # Check result
        if [ $exit_code -eq 0 ]; then
            # Verify node actually exists
            sleep 2  # Give multipass a moment to register the node
            if multipass list --format csv 2>/dev/null | grep -q "^$node,"; then
                echo -e "  [${node}] ${GREEN}✓ Created successfully${NC}"
                echo "SUCCESS" > "${temp_file}.status"
            else
                echo -e "  [${node}] ${YELLOW}⚠  Created but not registered yet${NC}"
                echo "SUCCESS" > "${temp_file}.status"  # Assume success, will verify later
            fi
        else
            local error_msg=$(cat "$temp_file" | grep -v "deprecated" | head -5)
            echo -e "  [${node}] ${RED}✗ Failed to create${NC}"
            if [ -n "$error_msg" ]; then
                echo -e "  [${node}] Error: $error_msg"
            fi
            echo "FAILED" > "${temp_file}.status"
        fi
        
        rm -f "$temp_file"
    }
    
    # Launch all nodes in parallel
    PIDS=()
    STATUS_FILES=()
    
    for node in "${NODES[@]}"; do
        launch_node "$node" &
        PIDS+=($!)
        STATUS_FILES+=("/tmp/multipass_${node}_$$.status")
    done
    
    # Wait for all background jobs to complete
    echo -e "\n  Waiting for all nodes to be created...\n"
    FAILED_NODES=()
    
    for i in "${!NODES[@]}"; do
        node="${NODES[$i]}"
        pid="${PIDS[$i]}"
        
        # Wait for this specific job
        wait $pid
        exit_code=$?
        
        # Check if node exists (final verification)
        sleep 1
        if multipass list --format csv 2>/dev/null | grep -q "^$node,"; then
            echo -e "  [${node}] ${GREEN}✓ Verified and ready${NC}"
        else
            if [ $exit_code -ne 0 ]; then
                echo -e "  [${node}] ${RED}✗ Creation failed${NC}"
                FAILED_NODES+=("$node")
            else
                # Give it a bit more time
                sleep 3
                if multipass list --format csv 2>/dev/null | grep -q "^$node,"; then
                    echo -e "  [${node}] ${GREEN}✓ Verified and ready${NC}"
                else
                    echo -e "  [${node}] ${RED}✗ Creation incomplete${NC}"
                    FAILED_NODES+=("$node")
                fi
            fi
        fi
    done
    
    # Check for failures
    if [ ${#FAILED_NODES[@]} -gt 0 ]; then
        echo -e "\n${RED}✗ Step 1 Failed: The following nodes failed to create:${NC}"
        for node in "${FAILED_NODES[@]}"; do
            echo -e "  - $node"
        done
        echo -e "\n${YELLOW}Cleaning up failed nodes...${NC}"
        for node in "${FAILED_NODES[@]}"; do
            multipass delete "$node" --purge 2>/dev/null || true
        done
        exit 1
    fi
    
    echo -e "\n${GREEN}✓ Step 1 Complete: All ${#NODES[@]} nodes created successfully${NC}\n"
    
    # Step 2: Install k3s on master (node1)
    echo -e "${YELLOW}Step 2: Installing k3s on master node ($MASTER_NODE)...${NC}"
    
    # Wait for node to be fully ready
    sleep 3
    
    # Get master IP first
    MASTER_IP=$(get_master_ip)
    if [ -z "$MASTER_IP" ]; then
        echo -e "${YELLOW}  Waiting for master IP assignment...${NC}"
        sleep 5
        MASTER_IP=$(get_master_ip)
        if [ -z "$MASTER_IP" ]; then
            echo -e "${RED}Error: Could not get master IP${NC}"
            exit 1
        fi
    fi
    echo -e "  Master IP: ${GREEN}$MASTER_IP${NC}"
    
    # Install k3s server
    if [ -n "$K3S_VERSION" ]; then
        multipass exec "$MASTER_NODE" -- sh -c "curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION=$K3S_VERSION sh -s - server --write-kubeconfig-mode 644"
    else
        multipass exec "$MASTER_NODE" -- sh -c "curl -sfL https://get.k3s.io | sh -s - server --write-kubeconfig-mode 644"
    fi
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Step 2 Complete: k3s installed on master${NC}\n"
    else
        echo -e "${RED}✗ Step 2 Failed: k3s installation on master failed${NC}"
        exit 1
    fi
    
    # Step 3: Install k3s-agent on worker nodes (node2, node3)
    echo -e "${YELLOW}Step 3: Installing k3s-agent on worker nodes...${NC}"
    
    # Get node token
    echo -e "  Getting node token from master..."
    NODE_TOKEN=$(multipass exec "$MASTER_NODE" -- sudo cat /var/lib/rancher/k3s/server/node-token)
    if [ -z "$NODE_TOKEN" ]; then
        echo -e "${RED}Error: Could not get node token${NC}"
        exit 1
    fi
    echo -e "  ${GREEN}✓ Token retrieved${NC}"
    
    # Install k3s-agent on each worker
    for node in "${WORKER_NODES[@]}"; do
        echo -e "  Installing k3s-agent on $node..."
        if [ -n "$K3S_VERSION" ]; then
            multipass exec "$node" -- sh -c "curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION=$K3S_VERSION K3S_URL=https://${MASTER_IP}:6443 K3S_TOKEN=${NODE_TOKEN} sh -"
        else
            multipass exec "$node" -- sh -c "curl -sfL https://get.k3s.io | K3S_URL=https://${MASTER_IP}:6443 K3S_TOKEN=${NODE_TOKEN} sh -"
        fi
        
        if [ $? -eq 0 ]; then
            echo -e "    ${GREEN}✓ $node joined cluster${NC}"
        else
            echo -e "    ${RED}✗ Failed to install k3s-agent on $node${NC}"
            exit 1
        fi
    done
    echo -e "${GREEN}✓ Step 3 Complete: All worker nodes joined cluster${NC}\n"
    
    # Step 4: Get kubeconfig
    echo -e "${YELLOW}Step 4: Setting up kubeconfig...${NC}"
    mkdir -p "$(dirname "$KUBECONFIG_FILE")"
    multipass exec "$MASTER_NODE" -- sudo cat /etc/rancher/k3s/k3s.yaml > "$KUBECONFIG_FILE"
    
    # Replace localhost with master IP
    if [[ "$OSTYPE" == "darwin"* ]]; then
        sed -i '' "s/127.0.0.1/$MASTER_IP/g" "$KUBECONFIG_FILE"
    else
        sed -i "s/127.0.0.1/$MASTER_IP/g" "$KUBECONFIG_FILE"
    fi
    
    echo -e "${GREEN}✓ Kubeconfig saved to: $KUBECONFIG_FILE${NC}\n"
    
    # Step 5: Verify cluster
    echo -e "${YELLOW}Step 5: Verifying cluster...${NC}"
    sleep 5  # Wait for nodes to register
    export KUBECONFIG="$KUBECONFIG_FILE"
    if kubectl get nodes &>/dev/null; then
        echo -e "${GREEN}✓ Cluster is ready!${NC}\n"
        kubectl get nodes
    else
        echo -e "${YELLOW}⚠  Cluster created but not fully ready yet${NC}"
        echo -e "   Run 'kubectl get nodes' in a few seconds${NC}\n"
    fi
    
    echo -e "${GREEN}=== Cluster Creation Complete ===${NC}\n"
    echo -e "${BLUE}Next steps:${NC}"
    echo -e "1. Set kubeconfig: export KUBECONFIG=$KUBECONFIG_FILE"
    echo -e "2. Or use: kubectl --kubeconfig=$KUBECONFIG_FILE get nodes"
    echo -e "3. Check status: $0 status"
}

delete_cluster() {
    echo -e "${BLUE}=== Deleting k3s Cluster ===${NC}\n"
    
    check_multipass
    
    # Check if nodes exist
    EXISTING_NODES=$(multipass list --format csv 2>/dev/null | grep -E "node1|node2|node3" | cut -d, -f1 || echo "")
    if [ -z "$EXISTING_NODES" ]; then
        echo -e "${GREEN}No nodes found. Cluster already deleted.${NC}"
        exit 0
    fi
    
    echo -e "${YELLOW}This will delete all nodes:${NC}"
    for node in "${NODES[@]}"; do
        if multipass list --format csv 2>/dev/null | grep -q "^$node,"; then
            echo -e "  - $node"
        fi
    done
    echo ""
    read -p "Are you sure? (yes/no): " -r
    echo ""
    
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        echo -e "${YELLOW}Deletion cancelled.${NC}"
        exit 0
    fi
    
    # Stop and delete nodes
    echo -e "${YELLOW}Deleting nodes...${NC}"
    for node in "${NODES[@]}"; do
        if multipass list --format csv 2>/dev/null | grep -q "^$node,"; then
            echo -e "  Deleting $node..."
            multipass delete "$node" --purge 2>/dev/null || true
        fi
    done
    
    # Remove kubeconfig file
    if [ -f "$KUBECONFIG_FILE" ]; then
        echo -e "  Removing kubeconfig file..."
        rm -f "$KUBECONFIG_FILE"
    fi
    
    echo -e "${GREEN}✓ Cluster deleted${NC}\n"
}

show_status() {
    echo -e "${BLUE}=== Cluster Status ===${NC}\n"
    
    check_multipass
    
    # Check nodes
    EXISTING_NODES=$(multipass list --format csv 2>/dev/null | grep -E "node1|node2|node3" || echo "")
    if [ -z "$EXISTING_NODES" ]; then
        echo -e "${YELLOW}No cluster nodes found.${NC}"
        echo -e "Run '$0 create' to create a cluster.${NC}"
        exit 0
    fi
    
    echo -e "${YELLOW}Multipass Nodes:${NC}"
    multipass list | grep -E "NAME|node" || echo "  (none)"
    echo ""
    
    # Check k3s status
    if multipass list --format csv 2>/dev/null | grep -q "^$MASTER_NODE,"; then
        echo -e "${YELLOW}k3s Status:${NC}"
        echo -e "  Master ($MASTER_NODE):"
        multipass exec "$MASTER_NODE" -- sudo systemctl is-active k3s 2>/dev/null && \
            echo -e "    ${GREEN}✓ k3s is running${NC}" || \
            echo -e "    ${RED}✗ k3s is not running${NC}"
        
        for node in "${WORKER_NODES[@]}"; do
            if multipass list --format csv 2>/dev/null | grep -q "^$node,"; then
                echo -e "  Worker ($node):"
                multipass exec "$node" -- sudo systemctl is-active k3s-agent 2>/dev/null && \
                    echo -e "    ${GREEN}✓ k3s-agent is running${NC}" || \
                    echo -e "    ${RED}✗ k3s-agent is not running${NC}"
            fi
        done
        echo ""
        
        # Check Kubernetes cluster
        if [ -f "$KUBECONFIG_FILE" ]; then
            export KUBECONFIG="$KUBECONFIG_FILE"
            if kubectl get nodes &>/dev/null 2>&1; then
                echo -e "${YELLOW}Kubernetes Cluster:${NC}"
                kubectl get nodes
            else
                echo -e "${YELLOW}Kubernetes Cluster:${NC}"
                echo -e "  ${RED}✗ Cannot connect to cluster${NC}"
            fi
        else
            echo -e "${YELLOW}Kubeconfig:${NC}"
            echo -e "  ${YELLOW}⚠  Kubeconfig file not found${NC}"
        fi
    fi
    echo ""
}

show_kubeconfig() {
    echo -e "${BLUE}=== Kubeconfig Setup ===${NC}\n"
    
    if [ ! -f "$KUBECONFIG_FILE" ]; then
        echo -e "${RED}Kubeconfig file not found: $KUBECONFIG_FILE${NC}"
        echo -e "${YELLOW}Run '$0 create' first to create the cluster.${NC}"
        exit 1
    fi
    
    MASTER_IP=$(get_master_ip)
    if [ -z "$MASTER_IP" ]; then
        echo -e "${RED}Error: Could not get master IP${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}Kubeconfig file: $KUBECONFIG_FILE${NC}\n"
    echo -e "${YELLOW}To use this cluster, run one of the following:${NC}\n"
    echo -e "${BLUE}Option 1: Export KUBECONFIG (temporary)${NC}"
    echo -e "  export KUBECONFIG=$KUBECONFIG_FILE"
    echo ""
    echo -e "${BLUE}Option 2: Use --kubeconfig flag${NC}"
    echo -e "  kubectl --kubeconfig=$KUBECONFIG_FILE get nodes"
    echo ""
    echo -e "${BLUE}Option 3: Set as default context${NC}"
    echo -e "  kubectl config view --kubeconfig=$KUBECONFIG_FILE"
    echo -e "  kubectl config use-context default --kubeconfig=$KUBECONFIG_FILE"
    echo ""
    echo -e "${BLUE}Option 4: Merge with existing kubeconfig${NC}"
    echo -e "  KUBECONFIG=~/.kube/config:$KUBECONFIG_FILE kubectl config view --flatten > ~/.kube/config.tmp"
    echo -e "  mv ~/.kube/config.tmp ~/.kube/config"
    echo ""
}

# Main
case "${1:-}" in
    create)
        create_cluster
        ;;
    delete)
        delete_cluster
        ;;
    status)
        show_status
        ;;
    kubeconfig)
        show_kubeconfig
        ;;
    *)
        print_usage
        ;;
esac

