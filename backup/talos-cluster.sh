#!/bin/bash
set -euo pipefail

# Talos Docker Cluster Management Script
# Handles Docker socket path for macOS automatically

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Set Docker socket for macOS
export DOCKER_HOST="unix://$HOME/.docker/run/docker.sock"

# Configuration
CLUSTER_NAME="talos-cluster"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KUBECONFIG_PATH="$SCRIPT_DIR/_out/kubeconfig"

print_usage() {
    echo "Usage: $0 {create|delete|status|info}"
    echo ""
    echo "Commands:"
    echo "  create  - Create 3-node HA Talos cluster (~3-4 minutes)"
    echo "  delete  - Delete cluster and free 6GB RAM"
    echo "  status  - Show cluster health and resources"
    echo "  info    - Show access commands and endpoints"
    echo ""
    echo "Note: Docker Talos clusters cannot be stopped/started reliably."
    echo "      Use 'delete' to free memory, 'create' to recreate when needed."
    exit 1
}

format_duration() {
    local seconds=$1
    local hours=$((seconds / 3600))
    local minutes=$(((seconds % 3600) / 60))
    local secs=$((seconds % 60))
    
    if [ $hours -gt 0 ]; then
        echo "${hours}h ${minutes}m ${secs}s"
    elif [ $minutes -gt 0 ]; then
        echo "${minutes}m ${secs}s"
    else
        echo "${secs}s"
    fi
}

create_cluster() {
    local start_time=$(date +%s)
    
    echo -e "${BLUE}=== Creating Talos HA Cluster (3 Control Plane Nodes) ===${NC}\n"
    
    # Clean up old cluster if exists
    if docker ps -a --filter "name=talos-cluster" --format "{{.Names}}" 2>/dev/null | grep -q "talos-cluster"; then
        echo -e "${YELLOW}Cluster already exists${NC}"
        echo -e "${YELLOW}Run: $0 delete first${NC}"
        exit 1
    fi
    
    rm -rf _out/ ~/.talos/clusters/$CLUSTER_NAME
    
    echo -e "${YELLOW}Creating Talos cluster with 3 control plane nodes (HA)...${NC}"
    echo -e "${YELLOW}Using Kubernetes v1.33 (compatible with Rancher)${NC}"
    echo -e "${YELLOW}This will take 3-4 minutes...${NC}\n"
    echo -e "${BLUE}ℹ️  Note: 'waiting' messages are normal progress indicators${NC}\n"
    
    # Create 3-node HA cluster with Kubernetes v1.33
    # Colorize output: waiting/progress = yellow, errors = red, success = green
    set +e  # Don't exit on pipe errors
    talosctl cluster create \
        --name "$CLUSTER_NAME" \
        --controlplanes 3 \
        --workers 0 \
        --kubernetes-version 1.33.0 \
        --wait-timeout 15m \
        --cpus 2 \
        --memory 2048 2>&1 | while IFS= read -r line; do
        # Colorize waiting/progress messages (yellow)
        if echo "$line" | grep -qE "(waiting for|Preparing|Running pre state|errors occurred:.*service.*not in expected state)"; then
            echo -e "${YELLOW}${line}${NC}"
        # Colorize actual errors (red)
        elif echo "$line" | grep -qiE "^error:|failed|fatal"; then
            echo -e "${RED}${line}${NC}"
        # Colorize success messages (green)
        elif echo "$line" | grep -qE "(OK|ready|successfully|completed)"; then
            echo -e "${GREEN}${line}${NC}"
        # Colorize important info (blue)
        elif echo "$line" | grep -qE "(PROVISIONER|NODES:|KUBERNETES ENDPOINT|validating|generating|creating|bootstrapping)"; then
            echo -e "${BLUE}${line}${NC}"
        # Default output
        else
            echo "$line"
        fi
    done
    CREATE_EXIT_CODE=${PIPESTATUS[0]}
    set -e  # Re-enable exit on error
    
    if [ $CREATE_EXIT_CODE -ne 0 ]; then
        echo -e "\n${RED}✗ Cluster creation failed${NC}"
        exit $CREATE_EXIT_CODE
    fi
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    local formatted_duration=$(format_duration $duration)
    
    echo -e "\n${GREEN}✓ HA Cluster created successfully!${NC}"
    echo -e "${BLUE}⏱️  Time taken: ${formatted_duration}${NC}\n"
    show_info
}

delete_cluster() {
    echo -e "${BLUE}=== Deleting Talos Cluster ===${NC}\n"
    
    talosctl cluster destroy --name "$CLUSTER_NAME" 2>/dev/null || true
    rm -rf _out/ ~/.talos/clusters/$CLUSTER_NAME
    
    echo -e "${GREEN}✓ Cluster deleted (freed ~6GB RAM)${NC}\n"
}

show_status() {
    echo -e "${BLUE}=== Talos Cluster Status ===${NC}\n"
    
    # Check if cluster container is running
    if ! docker ps --filter "name=talos-cluster-controlplane" --format "{{.Names}}" 2>/dev/null | grep -q "talos-cluster"; then
        echo -e "${YELLOW}Cluster not running${NC}"
        echo -e "${YELLOW}Run: $0 create${NC}"
        exit 0
    fi
    
    echo -e "${BLUE}Docker Containers:${NC}"
    docker ps --filter "name=talos-cluster" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
    echo ""
    
    export KUBECONFIG="$KUBECONFIG_PATH"
    echo -e "${BLUE}Kubernetes Nodes:${NC}"
    kubectl get nodes -o wide
    echo ""
    
    echo -e "${BLUE}System Pods:${NC}"
    kubectl get pods -n kube-system -l 'component in (kube-apiserver,etcd,coredns)' 2>/dev/null || kubectl get pods -n kube-system | head -10
    echo ""
    
    echo -e "${BLUE}Resource Usage:${NC}"
    docker stats --no-stream $(docker ps -q --filter "name=talos-cluster") --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}"
    echo ""
}

show_info() {
    echo -e "${BLUE}=== Cluster Access Information ===${NC}\n"
    
    # Check if cluster exists
    if ! docker ps --filter "name=talos-cluster-controlplane" --format "{{.Names}}" 2>/dev/null | grep -q "talos-cluster"; then
        echo -e "${YELLOW}No cluster found${NC}"
        echo -e "${YELLOW}Run: $0 create${NC}"
        exit 0
    fi
    
    export KUBECONFIG="$KUBECONFIG_PATH"
    
    echo -e "${GREEN}Kubernetes Access:${NC}"
    echo -e "  export KUBECONFIG=$KUBECONFIG_PATH"
    echo -e "  kubectl get nodes"
    echo -e "  kubectl get pods -A"
    echo ""
    
    echo -e "${GREEN}Talos API Access:${NC}"
    echo -e "  export DOCKER_HOST=\"unix://\$HOME/.docker/run/docker.sock\""
    echo -e "  talosctl --nodes 10.5.0.2 version"
    echo -e "  talosctl --nodes 10.5.0.2 dashboard"
    echo -e "  talosctl --nodes 10.5.0.2 logs kubelet"
    echo -e "  talosctl --nodes 10.5.0.2 dmesg"
    echo -e "  talosctl --nodes 10.5.0.2 get members  # etcd members"
    echo ""
    
    echo -e "${GREEN}Cluster Endpoints:${NC}"
    KUBE_PORT=$(docker port talos-cluster-controlplane-1 6443 2>/dev/null | cut -d: -f2)
    TALOS_PORT=$(docker port talos-cluster-controlplane-1 50000 2>/dev/null | cut -d: -f2)
    echo -e "  Kubernetes API: https://127.0.0.1:${KUBE_PORT}"
    echo -e "  Talos API: 127.0.0.1:${TALOS_PORT}"
    echo ""
    
    echo -e "${GREEN}Node IPs (internal Docker network):${NC}"
    kubectl get nodes -o custom-columns=NAME:.metadata.name,INTERNAL-IP:.status.addresses[0].address --no-headers 2>/dev/null
    echo ""
    
    echo -e "${YELLOW}Memory Usage: ~6GB (3 nodes × 2GB each)${NC}"
    echo -e "${YELLOW}To free memory: $0 delete${NC}"
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
    info)
        show_info
        ;;
    *)
        print_usage
        ;;
esac
