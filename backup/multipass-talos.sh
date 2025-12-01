#!/bin/bash
set -euo pipefail

# Multipass Talos Cluster Setup
# Uses cloud-init to run Talos in Multipass Ubuntu VMs

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
NODE_NAME="talos-node-1"
TALOS_VERSION="v1.11.5"
ARCH="arm64"

print_usage() {
    echo "Usage: $0 {create|delete|status|shell}"
    echo ""
    echo "Commands:"
    echo "  create  - Create Talos VM using Multipass"
    echo "  delete  - Delete Talos VM"
    echo "  status  - Show VM status and IP"
    echo "  shell   - Shell into VM"
    exit 1
}

create_vm() {
    echo -e "${BLUE}=== Creating Talos Node with Multipass ===${NC}\n"
    
    # Check if VM already exists
    if multipass list | grep -q "$NODE_NAME"; then
        echo -e "${RED}Error: VM $NODE_NAME already exists${NC}"
        echo -e "${YELLOW}Run: $0 delete${NC}"
        exit 1
    fi
    
    echo -e "${YELLOW}Creating Ubuntu VM to run Talos via Docker...${NC}"
    
    # Create Ubuntu VM with Docker
    multipass launch -n "$NODE_NAME" \
        --cpus 2 \
        --memory 4G \
        --disk 50G \
        --cloud-init - <<EOF
#cloud-config
package_update: true
packages:
  - docker.io
runcmd:
  - systemctl enable docker
  - systemctl start docker
  - usermod -aG docker ubuntu
  - |
    # Pull and run Talos in Docker (siderolink mode for easy access)
    docker pull ghcr.io/siderolabs/talos:${TALOS_VERSION}
    docker run -d \\
      --name talos \\
      --privileged \\
      --network host \\
      -v /dev:/dev \\
      -v /sys:/sys:ro \\
      ghcr.io/siderolabs/talos:${TALOS_VERSION} \\
      --platform container
EOF
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}✗ Failed to create VM${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✓ VM created${NC}\n"
    echo -e "${YELLOW}Waiting for VM to initialize (60 seconds)...${NC}"
    sleep 60
    
    # Get VM IP
    VM_IP=$(multipass info "$NODE_NAME" | grep IPv4 | awk '{print $2}')
    
    echo -e "${GREEN}✓ Talos node ready${NC}"
    echo -e "${BLUE}VM IP: ${VM_IP}${NC}"
    echo -e "${BLUE}Talos API: ${VM_IP}:50000${NC}\n"
    
    echo -e "${BLUE}Next steps:${NC}"
    echo -e "  1. Use talosctl to connect: talosctl --nodes ${VM_IP} version --insecure"
    echo -e "  2. Configure cluster: talosctl gen config mycluster https://${VM_IP}:6443"
    echo ""
}

delete_vm() {
    echo -e "${BLUE}=== Deleting Talos Node ===${NC}\n"
    
    if ! multipass list | grep -q "$NODE_NAME"; then
        echo -e "${YELLOW}VM $NODE_NAME not found${NC}"
        exit 0
    fi
    
    multipass delete "$NODE_NAME"
    multipass purge
    
    echo -e "${GREEN}✓ VM deleted${NC}\n"
}

show_status() {
    echo -e "${BLUE}=== Talos Node Status ===${NC}\n"
    
    if ! multipass list | grep -q "$NODE_NAME"; then
        echo -e "${YELLOW}VM $NODE_NAME not found${NC}"
        echo -e "${YELLOW}Run: $0 create${NC}"
        exit 0
    fi
    
    multipass info "$NODE_NAME"
    
    VM_IP=$(multipass info "$NODE_NAME" | grep IPv4 | awk '{print $2}')
    
    echo -e "\n${BLUE}Talos Access:${NC}"
    echo -e "  API: ${VM_IP}:50000"
    echo -e "  Test: talosctl --nodes ${VM_IP} version --insecure"
    echo ""
}

shell_vm() {
    if ! multipass list | grep -q "$NODE_NAME"; then
        echo -e "${RED}VM $NODE_NAME not found${NC}"
        exit 1
    fi
    
    multipass shell "$NODE_NAME"
}

# Main
case "${1:-}" in
    create)
        create_vm
        ;;
    delete)
        delete_vm
        ;;
    status)
        show_status
        ;;
    shell)
        shell_vm
        ;;
    *)
        print_usage
        ;;
esac

