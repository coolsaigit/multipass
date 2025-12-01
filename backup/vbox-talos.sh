#!/bin/bash
set -euo pipefail

# VBoxManage Talos Kubernetes Cluster Management Script
# Uses VirtualBox directly (no Vagrant, no base boxes)
# Usage:
#   ./vbox-talos.sh create    - Create Talos cluster VMs
#   ./vbox-talos.sh delete    - Delete all VMs
#   ./vbox-talos.sh status    - Show VM status
#   ./vbox-talos.sh start     - Start all VMs
#   ./vbox-talos.sh stop      - Stop all VMs

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
CONTROL_PLANE_NODES=("rancher-server-1" "rancher-server-2" "rancher-server-3")
CONTROL_PLANE_IPS=("192.168.1.210" "192.168.1.211" "192.168.1.212")
TALOS_VERSION="${TALOS_VERSION:-v1.11.5}"

# Detect architecture for ISO and VM type
ARCH=$(uname -m)
if [ "$ARCH" = "arm64" ] || [ "$ARCH" = "aarch64" ]; then
    TALOS_ARCH="arm64"
    VM_OSTYPE="Linux_arm64"  # VirtualBox uses lowercase
else
    TALOS_ARCH="amd64"
    VM_OSTYPE="Linux_64"
fi

# Paths
TALOS_ISO_DIR="$HOME/.vagrant/talos-iso"
TALOS_ISO_FILE="$TALOS_ISO_DIR/talos-${TALOS_VERSION}-${TALOS_ARCH}.iso"
TALOS_ISO_URL="https://github.com/siderolabs/talos/releases/download/${TALOS_VERSION}/metal-${TALOS_ARCH}.iso"
VM_BASE_DIR="$HOME/VirtualBox VMs"
DISK_BASE_DIR="$HOME/.vagrant/talos-iso"

# VM specifications
VM_MEMORY=4096      # 4GB RAM
VM_CPUS=2           # 2 CPUs
VM_DISK_SIZE=51200  # 50GB in MB

print_usage() {
    echo "Usage: $0 {create|delete|status|start|stop|ips|ssh}"
    echo ""
    echo "Commands:"
    echo "  create     - Create Talos cluster VMs using VBoxManage"
    echo "  delete     - Delete all Talos VMs"
    echo "  status     - Show VM status with detailed information"
    echo "  start      - Start all VMs"
    echo "  stop       - Stop all VMs"
    echo "  ips        - Show IP addresses (configured and actual)"
    echo "  ssh <node> - SSH into a VM (e.g., rancher-server-1)"
    exit 1
}

check_vboxmanage() {
    if ! command -v VBoxManage >/dev/null 2>&1; then
        echo -e "${RED}Error: VBoxManage is not installed${NC}"
        echo "Install VirtualBox: https://www.virtualbox.org/"
        exit 1
    fi
}

check_iso() {
    if [ ! -f "$TALOS_ISO_FILE" ]; then
        echo -e "${RED}Error: Talos ISO not found: $TALOS_ISO_FILE${NC}"
        echo -e "${YELLOW}Downloading Talos ISO...${NC}"
        mkdir -p "$TALOS_ISO_DIR"
        if curl -L -o "$TALOS_ISO_FILE" "$TALOS_ISO_URL"; then
            echo -e "${GREEN}✓ Talos ISO downloaded${NC}\n"
        else
            echo -e "${RED}✗ Failed to download Talos ISO${NC}"
            exit 1
        fi
    fi
}

vm_exists() {
    local vm_name="$1"
    VBoxManage list vms | grep -q "\"$vm_name\"" || return 1
}

create_vm() {
    local vm_name="$1"
    local vm_ip="$2"
    
    echo -e "  [${vm_name}] Creating VM..."
    echo -e "  [${vm_name}] Architecture: ${TALOS_ARCH}, OS Type: ${VM_OSTYPE}"
    
    # Create VM
    echo -e "  [${vm_name}] Registering VM..."
    VBoxManage createvm \
        --name "$vm_name" \
        --ostype "$VM_OSTYPE" \
        --register \
        --basefolder "$VM_BASE_DIR" 2>&1 | sed "s/^/  [${vm_name}] /" || {
        echo -e "  [${vm_name}] ${RED}✗ Failed to create VM${NC}"
        return 1
    }
    
    # Configure memory and CPUs
    echo -e "  [${vm_name}] Configuring VM settings..."
    if [ "$TALOS_ARCH" = "arm64" ]; then
        # ARM64 specific configuration (some options not available)
        VBoxManage modifyvm "$vm_name" \
            --memory "$VM_MEMORY" \
            --cpus "$VM_CPUS" \
            --boot1 dvd \
            --boot2 disk \
            --boot3 none \
            --rtcuseutc on \
            --graphicscontroller vmsvga \
            --audio-driver none \
            --usb off \
            --clipboard disabled \
            --draganddrop disabled 2>&1 | grep -v "not available" || true
        echo -e "  [${vm_name}] ${GREEN}✓ VM configured${NC}"
    else
        # x86_64 configuration
        VBoxManage modifyvm "$vm_name" \
            --memory "$VM_MEMORY" \
            --cpus "$VM_CPUS" \
            --boot1 dvd \
            --boot2 disk \
            --boot3 none \
            --acpi on \
            --ioapic on \
            --pae on \
            --longmode on \
            --rtcuseutc on \
            --graphicscontroller vboxsvga \
            --audio-driver none \
            --usb off \
            --clipboard disabled \
            --draganddrop disabled 2>&1 | grep -v "not available" || true
    fi
    
    # Configure network - NAT with port forwarding for Talos API access
    # NAT provides automatic DHCP, we access via localhost port forwarding
    echo -e "  [${vm_name}] Configuring network (NAT with port forwarding)..."
    
    # NIC 1: NAT with port forwarding for Talos API
    VBoxManage modifyvm "$vm_name" \
        --nic1 nat \
        --cableconnected1 on 2>&1 | sed "s/^/  [${vm_name}] /" || {
        echo -e "  [${vm_name}] ${RED}✗ Failed to configure NAT adapter${NC}"
        return 1
    }
    
    # Setup port forwarding for Talos API
    # Extract node number from IP (e.g., 192.168.1.210 -> 210)
    local node_num="${vm_ip##*.}"
    local talos_port=$((50000 + node_num - 200))  # 50010, 50011, 50012
    
    echo -e "  [${vm_name}] Setting up port forwarding for Talos API..."
    # Talos API (50000 -> host:500XX)
    VBoxManage modifyvm "$vm_name" \
        --natpf1 "talos-api,tcp,,${talos_port},,50000" 2>&1 | sed "s/^/  [${vm_name}] /" || true
    
    echo -e "  [${vm_name}] ${GREEN}✓ Network configured (NAT + Port Forward)${NC}"
    echo -e "  [${vm_name}] ${GREEN}✓ Talos API accessible on localhost:${talos_port}${NC}"
    
    # Create disk
    local disk_path="$DISK_BASE_DIR/${vm_name}.vdi"
    mkdir -p "$DISK_BASE_DIR"
    echo -e "  [${vm_name}] Creating ${VM_DISK_SIZE}MB disk (this may take a few minutes)..."
    # Create disk and show progress
    VBoxManage createhd \
        --filename "$disk_path" \
        --size "$VM_DISK_SIZE" \
        --format VDI 2>&1 | sed "s/^/  [${vm_name}] /"
    
    if [ -f "$disk_path" ]; then
        echo -e "  [${vm_name}] ${GREEN}✓ Disk created${NC}"
    else
        echo -e "  [${vm_name}] ${RED}✗ Disk creation failed${NC}"
        return 1
    fi
    
    # Attach disk
    if [ "$TALOS_ARCH" = "arm64" ]; then
        # ARM64 may need different controller
        VBoxManage storagectl "$vm_name" \
            --name "SATA Controller" \
            --add sata >/dev/null 2>&1 || \
        VBoxManage storagectl "$vm_name" \
            --name "SATA Controller" \
            --add sata \
            --controller IntelAHCI >/dev/null 2>&1
    else
        VBoxManage storagectl "$vm_name" \
            --name "SATA Controller" \
            --add sata \
            --controller IntelAHCI >/dev/null 2>&1
    fi
    
    VBoxManage storageattach "$vm_name" \
        --storagectl "SATA Controller" \
        --port 0 \
        --device 0 \
        --type hdd \
        --medium "$disk_path" >/dev/null 2>&1
    
    # Attach Talos ISO
    # On ARM64, use SATA for ISO instead of IDE (IDE controller not fully supported)
    if [ "$TALOS_ARCH" = "arm64" ]; then
        # Use SATA port 1 for ISO
        VBoxManage storageattach "$vm_name" \
            --storagectl "SATA Controller" \
            --port 1 \
            --device 0 \
            --type dvddrive \
            --medium "$TALOS_ISO_FILE" >/dev/null 2>&1
    else
        # x86_64 can use IDE
        VBoxManage storagectl "$vm_name" \
            --name "IDE Controller" \
            --add ide >/dev/null 2>&1
        
        VBoxManage storageattach "$vm_name" \
            --storagectl "IDE Controller" \
            --port 1 \
            --device 0 \
            --type dvddrive \
            --medium "$TALOS_ISO_FILE" >/dev/null 2>&1
    fi
    
    echo -e "  [${vm_name}] ${GREEN}✓ Created${NC}"
}

create_cluster() {
    echo -e "${BLUE}=== Creating Talos Cluster VMs ===${NC}\n"
    
    check_vboxmanage
    check_iso
    
    # Check if VMs already exist
    EXISTING_VMS=()
    for node in "${CONTROL_PLANE_NODES[@]}"; do
        if vm_exists "$node"; then
            EXISTING_VMS+=("$node")
        fi
    done
    
    if [ ${#EXISTING_VMS[@]} -gt 0 ]; then
        echo -e "${RED}Error: VMs already exist:${NC}"
        printf '  %s\n' "${EXISTING_VMS[@]}"
        echo -e "${YELLOW}Run '$0 delete' first to remove existing VMs${NC}"
        exit 1
    fi
    
    echo -e "${YELLOW}Creating ${#CONTROL_PLANE_NODES[@]} control plane nodes...${NC}"
    echo -e "  Configuration: ${VM_CPUS} CPUs, ${VM_MEMORY}MB RAM, ${VM_DISK_SIZE}MB disk per VM"
    echo -e "  Talos ISO: $TALOS_ISO_FILE\n"
    
    # Create all VMs
    for i in "${!CONTROL_PLANE_NODES[@]}"; do
        create_vm "${CONTROL_PLANE_NODES[$i]}" "${CONTROL_PLANE_IPS[$i]}"
    done
    
    echo -e "\n${GREEN}✓ All VMs created successfully!${NC}\n"
    
    # Show IP address configuration
    echo -e "${BLUE}VM Configuration:${NC}"
    for i in "${!CONTROL_PLANE_NODES[@]}"; do
        echo -e "  ${GREEN}${CONTROL_PLANE_NODES[$i]}${NC}: ${BLUE}${CONTROL_PLANE_IPS[$i]}${NC}"
    done
    echo ""
    
    echo -e "${BLUE}Cluster Information:${NC}"
    echo -e "  Control Plane Endpoint: https://${CONTROL_PLANE_IPS[0]}:6443"
    echo -e "  Network: ${CONTROL_PLANE_IPS[0]%.*}.0/24"
    echo ""
    
    echo -e "${BLUE}Next steps:${NC}"
    echo -e "  1. Run '$0 start' to start all VMs"
    echo -e "  2. Run './bootstrap-talos.sh' to configure the Talos Kubernetes cluster"
    echo -e "  3. Use '$0 status' to check VM status and IP addresses"
    echo ""
}

delete_cluster() {
    echo -e "${BLUE}=== Deleting Talos Cluster ===${NC}\n"
    
    check_vboxmanage
    
    for node in "${CONTROL_PLANE_NODES[@]}"; do
        if vm_exists "$node"; then
            echo -e "${YELLOW}Deleting $node...${NC}"
            
            # Power off if running
            if VBoxManage showvminfo "$node" --machinereadable | grep -q 'VMState="running"'; then
                VBoxManage controlvm "$node" poweroff >/dev/null 2>&1 || true
                sleep 2
            fi
            
            # Delete VM
            VBoxManage unregistervm "$node" --delete >/dev/null 2>&1 || true
            
            # Delete disk
            local disk_path="$DISK_BASE_DIR/${node}.vdi"
            if [ -f "$disk_path" ]; then
                rm -f "$disk_path"
            fi
            
            echo -e "${GREEN}✓ $node deleted${NC}"
        else
            echo -e "${YELLOW}$node not found, skipping${NC}"
        fi
    done
    
    echo -e "\n${GREEN}✓ Cluster deleted${NC}\n"
}

show_status() {
    echo -e "${BLUE}=== Talos Cluster Status ===${NC}\n"
    
    check_vboxmanage
    
    for i in "${!CONTROL_PLANE_NODES[@]}"; do
        local node="${CONTROL_PLANE_NODES[$i]}"
        local configured_ip="${CONTROL_PLANE_IPS[$i]}"
        
        if vm_exists "$node"; then
            local state=$(VBoxManage showvminfo "$node" --machinereadable 2>/dev/null | grep 'VMState=' | cut -d'"' -f2)
            local memory=$(VBoxManage showvminfo "$node" --machinereadable 2>/dev/null | grep 'memory=' | cut -d'=' -f2)
            local cpus=$(VBoxManage showvminfo "$node" --machinereadable 2>/dev/null | grep 'cpus=' | cut -d'=' -f2)
            local nic_type=$(VBoxManage showvminfo "$node" --machinereadable 2>/dev/null | grep '^nic1=' | cut -d'"' -f2)
            
            echo -e "${GREEN}$node${NC}"
            echo -e "  State: $state"
            echo -e "  CPUs: $cpus, Memory: ${memory}MB"
            echo -e "  Network: $nic_type"
            
            # Show configured static IP
            echo -e "  Configured IP: ${BLUE}${configured_ip}${NC}"
            
            # Try to get actual IP if running
            if [ "$state" = "running" ]; then
                local actual_ip=$(VBoxManage guestproperty get "$node" "/VirtualBox/GuestInfo/Net/0/V4/IP" 2>/dev/null | grep "Value:" | awk '{print $2}' || echo "")
                
                if [ -n "$actual_ip" ] && [ "$actual_ip" != "No" ] && [ "$actual_ip" != "value" ] && [ "$actual_ip" != "No value set!" ]; then
                    # Check if it matches configured IP
                    if [ "$actual_ip" = "$configured_ip" ]; then
                        echo -e "  Actual IP: ${GREEN}${actual_ip}${NC} ✓"
                    else
                        echo -e "  Actual IP: ${YELLOW}${actual_ip}${NC} (will be set to ${configured_ip} by bootstrap)"
                    fi
                    
                    # Test connectivity
                    if ping -c 1 -W 1 "$actual_ip" >/dev/null 2>&1; then
                        echo -e "  Connectivity: ${GREEN}✓ reachable${NC}"
                    else
                        echo -e "  Connectivity: ${YELLOW}⚠ not reachable${NC}"
                    fi
                else
                    echo -e "  Actual IP: ${YELLOW}detecting...${NC} (try after VM boots)"
                fi
            fi
            echo ""
        else
            echo -e "${YELLOW}$node${NC} - not created"
            echo -e "  Configured IP: ${BLUE}${configured_ip}${NC}"
            echo ""
        fi
    done
    
    # Show cluster endpoint info
    echo -e "${BLUE}Cluster Information:${NC}"
    echo -e "  Control Plane Endpoint: https://${CONTROL_PLANE_IPS[0]}:6443"
    echo -e "  Network: ${CONTROL_PLANE_IPS[0]%.*}.0/24"
    echo ""
}

start_cluster() {
    echo -e "${BLUE}=== Starting Talos Cluster ===${NC}\n"
    
    check_vboxmanage
    
    for i in "${!CONTROL_PLANE_NODES[@]}"; do
        local node="${CONTROL_PLANE_NODES[$i]}"
        local configured_ip="${CONTROL_PLANE_IPS[$i]}"
        
        if vm_exists "$node"; then
            local state=$(VBoxManage showvminfo "$node" --machinereadable 2>/dev/null | grep 'VMState=' | cut -d'"' -f2)
            if [ "$state" = "running" ]; then
                echo -e "${YELLOW}$node is already running${NC}"
                echo -e "  Configured IP: ${BLUE}${configured_ip}${NC}"
            else
                echo -e "${YELLOW}Starting $node...${NC}"
                VBoxManage startvm "$node" --type headless >/dev/null 2>&1
                echo -e "${GREEN}✓ $node started${NC}"
                echo -e "  Configured IP: ${BLUE}${configured_ip}${NC}"
            fi
        else
            echo -e "${RED}$node does not exist${NC}"
        fi
    done
    
    echo -e "\n${BLUE}Tip:${NC} Use '$0 status' to check actual IP addresses after VMs boot (wait ~30 seconds)"
    echo ""
}

stop_cluster() {
    echo -e "${BLUE}=== Stopping Talos Cluster ===${NC}\n"
    
    check_vboxmanage
    
    for node in "${CONTROL_PLANE_NODES[@]}"; do
        if vm_exists "$node"; then
            local state=$(VBoxManage showvminfo "$node" --machinereadable 2>/dev/null | grep 'VMState=' | cut -d'"' -f2)
            if [ "$state" = "running" ]; then
                echo -e "${YELLOW}Stopping $node...${NC}"
                VBoxManage controlvm "$node" poweroff >/dev/null 2>&1
                echo -e "${GREEN}✓ $node stopped${NC}"
            else
                echo -e "${YELLOW}$node is not running${NC}"
            fi
        else
            echo -e "${YELLOW}$node does not exist${NC}"
        fi
    done
    
    echo ""
}

show_ips() {
    echo -e "${BLUE}=== Talos Cluster IP Addresses ===${NC}\n"
    
    check_vboxmanage
    
    echo -e "${YELLOW}Configured IPs (Static):${NC}"
    for i in "${!CONTROL_PLANE_NODES[@]}"; do
        local node="${CONTROL_PLANE_NODES[$i]}"
        local configured_ip="${CONTROL_PLANE_IPS[$i]}"
        echo -e "  ${GREEN}${node}${NC}: ${BLUE}${configured_ip}${NC}"
    done
    echo ""
    
    echo -e "${YELLOW}Actual IPs (Current):${NC}"
    for i in "${!CONTROL_PLANE_NODES[@]}"; do
        local node="${CONTROL_PLANE_NODES[$i]}"
        local configured_ip="${CONTROL_PLANE_IPS[$i]}"
        
        if vm_exists "$node"; then
            local state=$(VBoxManage showvminfo "$node" --machinereadable 2>/dev/null | grep 'VMState=' | cut -d'"' -f2)
            
            if [ "$state" = "running" ]; then
                local actual_ip=$(VBoxManage guestproperty get "$node" "/VirtualBox/GuestInfo/Net/0/V4/IP" 2>/dev/null | grep "Value:" | awk '{print $2}' || echo "")
                
                if [ -n "$actual_ip" ] && [ "$actual_ip" != "No" ] && [ "$actual_ip" != "value" ] && [ "$actual_ip" != "No value set!" ]; then
                    if [ "$actual_ip" = "$configured_ip" ]; then
                        echo -e "  ${GREEN}${node}${NC}: ${GREEN}${actual_ip}${NC} ✓"
                    else
                        echo -e "  ${GREEN}${node}${NC}: ${YELLOW}${actual_ip}${NC} (will change to ${configured_ip})"
                    fi
                else
                    echo -e "  ${GREEN}${node}${NC}: ${YELLOW}detecting...${NC}"
                fi
            else
                echo -e "  ${GREEN}${node}${NC}: ${YELLOW}not running${NC}"
            fi
        else
            echo -e "  ${GREEN}${node}${NC}: ${RED}not created${NC}"
        fi
    done
    echo ""
    
    echo -e "${BLUE}Cluster Endpoints:${NC}"
    echo -e "  Control Plane: https://${CONTROL_PLANE_IPS[0]}:6443"
    echo -e "  Talos API: ${CONTROL_PLANE_IPS[0]}:50000"
    echo -e "  Network: ${CONTROL_PLANE_IPS[0]%.*}.0/24"
    echo ""
    
    echo -e "${BLUE}Add to /etc/hosts:${NC}"
    for i in "${!CONTROL_PLANE_NODES[@]}"; do
        echo -e "  ${CONTROL_PLANE_IPS[$i]} ${CONTROL_PLANE_NODES[$i]}"
    done
    echo ""
}

ssh_to_vm() {
    local vm_name="${2:-}"
    
    if [ -z "$vm_name" ]; then
        echo -e "${RED}Error: VM name required${NC}"
        echo "Usage: $0 ssh <vm-name>"
        echo "Available VMs: ${CONTROL_PLANE_NODES[*]}"
        exit 1
    fi
    
    if ! vm_exists "$vm_name"; then
        echo -e "${RED}Error: VM '$vm_name' does not exist${NC}"
        exit 1
    fi
    
    local state=$(VBoxManage showvminfo "$vm_name" --machinereadable 2>/dev/null | grep 'VMState=' | cut -d'"' -f2)
    if [ "$state" != "running" ]; then
        echo -e "${RED}Error: VM '$vm_name' is not running${NC}"
        exit 1
    fi
    
    echo -e "${YELLOW}Note: Talos is immutable and doesn't support SSH by default${NC}"
    echo -e "${YELLOW}Use 'talosctl' to interact with Talos nodes${NC}"
    echo ""
    
    # Try to get console access (if configured)
    VBoxManage controlvm "$vm_name" keyboardputscancode 1c 9c 2>/dev/null || true
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
    start)
        start_cluster
        ;;
    stop)
        stop_cluster
        ;;
    ips)
        show_ips
        ;;
    ssh)
        ssh_to_vm "$@"
        ;;
    *)
        print_usage
        ;;
esac

