#!/bin/bash
# Multipass Nodes Management Script (without k3s)
# Usage:
#   ./scripts/multipass-nodes.sh create    - Create Multipass VMs
#   ./scripts/multipass-nodes.sh delete    - Delete all VMs
#   ./scripts/multipass-nodes.sh status    - Show VM status
#   ./scripts/multipass-nodes.sh list      - List all VMs

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration (same as multipass-cluster.sh)
NODES=("node1" "node2" "node3")

# Node specifications
CPU_CORES=4
# MEMORY="16G"
# DISK="200G"
MEMORY="4G"
DISK="50G"
IMAGE="jammy"

# Functions
print_usage() {
    echo "Usage: $0 {create|delete|status|list}"
    echo ""
    echo "Commands:"
    echo "  create     - Create Multipass VMs"
    echo "  delete     - Delete all VMs"
    echo "  status     - Show VM status"
    echo "  list       - List all VMs"
    exit 1
}

check_multipass() {
    if ! command -v multipass &> /dev/null; then
        echo -e "${RED}Error: multipass is not installed${NC}"
        echo "Install with: brew install --cask multipass"
        exit 1
    fi
}

create_nodes() {
    echo -e "${BLUE}=== Creating Multipass VMs ===${NC}\n"
    
    check_multipass
    
    # Check if nodes already exist
    EXISTING_NODES=$(multipass list --format csv 2>/dev/null | grep -E "node1|node2|node3" | cut -d, -f1 || echo "")
    if [ -n "$EXISTING_NODES" ]; then
        echo -e "${RED}Error: Nodes already exist:${NC}"
        echo "$EXISTING_NODES"
        echo -e "${YELLOW}Run '$0 delete' first to remove existing nodes${NC}"
        exit 1
    fi
    
    # Launch all nodes in parallel
    echo -e "${YELLOW}Creating ${#NODES[@]} VMs in parallel...${NC}"
    echo -e "  Configuration: ${CPU_CORES} CPUs, ${MEMORY} RAM, ${DISK} disk per VM\n"
    
    # Function to launch a single node
    launch_node() {
        local node=$1
        local temp_file=$(mktemp)
        
        echo -e "  [${node}] Starting creation..."
        
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
            else
                echo -e "  [${node}] ${YELLOW}⚠  Created but not registered yet${NC}"
            fi
        else
            local error_msg=$(cat "$temp_file" | grep -v "deprecated" | head -5)
            echo -e "  [${node}] ${RED}✗ Failed to create${NC}"
            if [ -n "$error_msg" ]; then
                echo -e "  [${node}] Error: $error_msg"
            fi
        fi
        
        rm -f "$temp_file"
        return $exit_code
    }
    
    # Launch all nodes in parallel
    PIDS=()
    
    for node in "${NODES[@]}"; do
        launch_node "$node" &
        PIDS+=($!)
    done
    
    # Wait for all background jobs to complete
    echo -e "\n  Waiting for all VMs to be created...\n"
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
        echo -e "\n${RED}✗ Failed: The following nodes failed to create:${NC}"
        for node in "${FAILED_NODES[@]}"; do
            echo -e "  - $node"
        done
        echo -e "\n${YELLOW}Cleaning up failed nodes...${NC}"
        for node in "${FAILED_NODES[@]}"; do
            multipass delete "$node" --purge 2>/dev/null || true
        done
        exit 1
    fi
    
    echo -e "\n${GREEN}✓ All ${#NODES[@]} VMs created successfully${NC}\n"
    
    # Show node info
    echo -e "${YELLOW}VM Details:${NC}"
    multipass list | grep -E "NAME|node" || echo "  (none)"
    echo ""
}

delete_nodes() {
    echo -e "${BLUE}=== Deleting Multipass VMs ===${NC}\n"
    
    check_multipass
    
    # Check if nodes exist
    EXISTING_NODES=$(multipass list --format csv 2>/dev/null | grep -E "node1|node2|node3" | cut -d, -f1 || echo "")
    if [ -z "$EXISTING_NODES" ]; then
        echo -e "${GREEN}No nodes found. Already deleted.${NC}"
        exit 0
    fi
    
    echo -e "${YELLOW}This will delete the following VMs:${NC}"
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
    
    # Delete nodes
    echo -e "${YELLOW}Deleting VMs...${NC}"
    for node in "${NODES[@]}"; do
        if multipass list --format csv 2>/dev/null | grep -q "^$node,"; then
            echo -e "  Deleting $node..."
            multipass delete "$node" --purge 2>/dev/null || true
        fi
    done
    
    echo -e "${GREEN}✓ All VMs deleted${NC}\n"
}

show_status() {
    echo -e "${BLUE}=== VM Status ===${NC}\n"
    
    check_multipass
    
    # Check nodes
    EXISTING_NODES=$(multipass list --format csv 2>/dev/null | grep -E "node1|node2|node3" || echo "")
    if [ -z "$EXISTING_NODES" ]; then
        echo -e "${YELLOW}No VMs found.${NC}"
        echo -e "Run '$0 create' to create VMs.${NC}"
        exit 0
    fi
    
    echo -e "${YELLOW}Multipass VMs:${NC}"
    multipass list | grep -E "NAME|node" || echo "  (none)"
    echo ""
    
    # Show detailed info for each node
    for node in "${NODES[@]}"; do
        if multipass list --format csv 2>/dev/null | grep -q "^$node,"; then
            echo -e "${YELLOW}Details for $node:${NC}"
            multipass info "$node" | grep -E "Name|State|IPv4|Image|Release|CPU|Memory|Disk" || true
            echo ""
        fi
    done
}

list_nodes() {
    check_multipass
    
    echo -e "${BLUE}=== All Multipass VMs ===${NC}\n"
    multipass list
    echo ""
    
    # Count nodes
    NODE_COUNT=$(multipass list --format csv 2>/dev/null | tail -n +2 | wc -l | tr -d ' ')
    echo -e "${YELLOW}Total VMs: ${NODE_COUNT}${NC}"
}

# Main
case "${1:-}" in
    create)
        create_nodes
        ;;
    delete)
        delete_nodes
        ;;
    status)
        show_status
        ;;
    list)
        list_nodes
        ;;
    *)
        print_usage
        ;;
esac

