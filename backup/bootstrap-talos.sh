#!/bin/bash
set -euo pipefail

# Simple Talos Bootstrap Script (following official docs)
# https://docs.siderolabs.com/talos/v1.11/platform-specific-installations/local-platforms/virtualbox
#
# IMPORTANT: Talos requires bridge networking for proper cluster operation
# - VMs must be on bridged network (not NAT) to communicate with each other
# - Static IPs are configured via Talos machine config (not DHCP)
# - Bridge adapter allows nodes to reach each other on the same subnet

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration - matches vbox-talos.sh
CONTROL_PLANE_NODES=("rancher-server-1" "rancher-server-2" "rancher-server-3")
CONTROL_PLANE_IPS=("192.168.1.210" "192.168.1.211" "192.168.1.212")
FIRST_CONTROL_PLANE_IP="${CONTROL_PLANE_IPS[0]}"

# Network configuration for bridge mode
# NOTE: Update these to match your network if needed
NETWORK_GATEWAY="${NETWORK_GATEWAY:-192.168.1.1}"
NETWORK_PREFIX="${NETWORK_PREFIX:-24}"

CLUSTER_NAME="talos-cluster"
OUTPUT_DIR="_out"
TALOS_VERSION="${TALOS_VERSION:-v1.7.0}"
CLUSTER_ENDPOINT="https://${FIRST_CONTROL_PLANE_IP}:6443"

echo -e "${BLUE}=== Talos Kubernetes Cluster Bootstrap ===${NC}\n"

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

# Check if VMs are running
echo -e "${YELLOW}Checking VMs...${NC}"
RUNNING_VMS=$(VBoxManage list runningvms | grep -E "rancher-server" | wc -l | tr -d ' ')
if [ "$RUNNING_VMS" -lt 3 ]; then
    echo -e "${RED}Error: Need 3 running VMs${NC}"
    echo -e "${YELLOW}Run: ./vbox-talos.sh start${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Found $RUNNING_VMS VMs running${NC}\n"

# Use static IPs from vbox-talos.sh configuration
# Talos will be configured to use these static IPs via machine config
# VMs MUST be on bridge network for proper cluster communication
echo -e "${YELLOW}Using configured static IPs (Bridge Network):${NC}"
for i in "${!CONTROL_PLANE_NODES[@]}"; do
    echo -e "  ${GREEN}${CONTROL_PLANE_NODES[$i]}: ${CONTROL_PLANE_IPS[$i]}/${NETWORK_PREFIX}${NC}"
done
echo -e "\n${GREEN}Gateway: $NETWORK_GATEWAY${NC}"
echo -e "${GREEN}Control plane endpoint: $CLUSTER_ENDPOINT${NC}\n"

# Step 1: Generate machine configurations
echo -e "${BLUE}=== Step 1: Generating Machine Configurations ===${NC}\n"
mkdir -p "$OUTPUT_DIR"

talosctl gen config "$CLUSTER_NAME" "$CLUSTER_ENDPOINT" --output-dir "$OUTPUT_DIR" --force

if [ $? -ne 0 ]; then
    echo -e "${RED}✗ Failed to generate configurations${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Configurations generated in $OUTPUT_DIR${NC}\n"

# Step 2: Apply config to first control plane with static IP
echo -e "${BLUE}=== Step 2: Configuring First Control Plane Node ===${NC}\n"
echo -e "${YELLOW}Applying config to ${CONTROL_PLANE_NODES[0]}...${NC}"
echo -e "${YELLOW}Will configure static IP ${FIRST_CONTROL_PLANE_IP}/${NETWORK_PREFIX} on bridge network${NC}"

# Wait for VM to boot and try to discover IP
echo -e "${YELLOW}Waiting for VM to boot...${NC}"
sleep 15

# Try to get IP from guest properties with retries
INITIAL_IP=""
for attempt in $(seq 1 12); do
    INITIAL_IP=$(VBoxManage guestproperty get "${CONTROL_PLANE_NODES[0]}" "/VirtualBox/GuestInfo/Net/0/V4/IP" 2>/dev/null | grep "Value:" | awk '{print $2}' || echo "")
    if [ -n "$INITIAL_IP" ] && [ "$INITIAL_IP" != "No" ] && [ "$INITIAL_IP" != "value" ] && [ "$INITIAL_IP" != "No value set!" ]; then
        break
    fi
    sleep 2
done

# If still no IP, try to scan for Talos nodes on the network
if [ -z "$INITIAL_IP" ] || [ "$INITIAL_IP" = "No" ] || [ "$INITIAL_IP" = "value" ] || [ "$INITIAL_IP" = "No value set!" ]; then
    echo -e "${YELLOW}Could not detect IP from VM, trying network scan...${NC}"
    
    # Get MAC address of the VM
    VM_MAC=$(VBoxManage showvminfo "${CONTROL_PLANE_NODES[0]}" --machinereadable | grep "macaddress1=" | cut -d'"' -f2 | sed 's/../&:/g;s/:$//' | tr 'A-Z' 'a-z')
    echo -e "${YELLOW}VM MAC: $VM_MAC${NC}"
    
    # Do a quick ping sweep to populate ARP table
    echo -e "${YELLOW}Scanning network 192.168.1.0/24...${NC}"
    for ip in $(seq 50 250); do
        (ping -c 1 -W 1 192.168.1.$ip > /dev/null 2>&1 &)
    done
    sleep 5
    
    # Try to find the IP by MAC address
    INITIAL_IP=$(arp -an | grep -i "$VM_MAC" | grep -oE "192\.168\.1\.[0-9]+" | head -1)
    
    if [ -n "$INITIAL_IP" ]; then
        echo -e "${GREEN}✓ Found VM at IP: $INITIAL_IP (via ARP)${NC}"
    else
        echo -e "${YELLOW}Could not auto-detect IP. Trying talosctl discover...${NC}"
        # Try talosctl discover
        DISCOVER_OUTPUT=$(timeout 15 talosctl discover 2>/dev/null | grep -oE "192\.168\.1\.[0-9]+" | head -1 || echo "")
        if [ -n "$DISCOVER_OUTPUT" ]; then
            INITIAL_IP="$DISCOVER_OUTPUT"
            echo -e "${GREEN}✓ Discovered VM at: $INITIAL_IP${NC}"
        else
            echo -e "${YELLOW}⚠  Auto-detection failed${NC}"
            echo -e "${YELLOW}Please check VirtualBox console to see the VM's IP${NC}"
            echo -e "${YELLOW}Then run: VBoxManage showvminfo rancher-server-1${NC}"
            echo -e "${RED}Or manually enter the IP when prompted${NC}\n"
            
            # Prompt for manual IP
            read -p "Enter the IP address of rancher-server-1 (or press Enter to try static IP): " MANUAL_IP
            if [ -n "$MANUAL_IP" ]; then
                INITIAL_IP="$MANUAL_IP"
            fi
        fi
    fi
fi

# If still no IP, try the static IP directly
if [ -z "$INITIAL_IP" ] || [ "$INITIAL_IP" = "No" ] || [ "$INITIAL_IP" = "value" ] || [ "$INITIAL_IP" = "No value set!" ]; then
    echo -e "${YELLOW}Trying static IP ${FIRST_CONTROL_PLANE_IP}...${NC}"
    if ping -c 1 -W 2 "$FIRST_CONTROL_PLANE_IP" >/dev/null 2>&1; then
        INITIAL_IP="$FIRST_CONTROL_PLANE_IP"
        echo -e "${GREEN}✓ Static IP ${FIRST_CONTROL_PLANE_IP} is reachable${NC}"
    else
        echo -e "${RED}✗ Cannot connect to VM. Please ensure:${NC}"
        echo -e "${RED}  - VMs are running (./vbox-talos.sh start)${NC}"
        echo -e "${RED}  - VMs are using bridge network (not NAT)${NC}"
        echo -e "${RED}  - Bridge adapter is properly configured${NC}"
        echo -e "${RED}  - Your network has a DHCP server${NC}"
        echo -e "${YELLOW}  - Check VirtualBox console for actual IP${NC}"
        exit 1
    fi
else
    echo -e "${GREEN}Detected VM IP: $INITIAL_IP${NC}"
fi

echo -e "${GREEN}Connecting to VM, will configure static IP ${FIRST_CONTROL_PLANE_IP}/${NETWORK_PREFIX}${NC}"

# Apply config with static IP configuration on bridge network
# Include gateway for proper routing
talosctl apply-config --insecure --nodes "$INITIAL_IP" \
    --file "$OUTPUT_DIR/controlplane.yaml" \
    --config-patch @- <<EOF
machine:
  network:
    interfaces:
      - interface: eth0
        addresses:
          - ${FIRST_CONTROL_PLANE_IP}/${NETWORK_PREFIX}
        routes:
          - network: 0.0.0.0/0
            gateway: ${NETWORK_GATEWAY}
EOF

if [ $? -ne 0 ]; then
    echo -e "${RED}✗ Failed to apply configuration${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Configuration applied${NC}"
echo -e "${YELLOW}VM will reboot and install Talos. This may take 2-3 minutes...${NC}\n"

# Step 3: Wait for first node and bootstrap etcd
echo -e "${BLUE}=== Step 3: Bootstrapping etcd ===${NC}\n"
echo -e "${YELLOW}Waiting for first node to be ready...${NC}"

max_attempts=60
attempt=0
while [ $attempt -lt $max_attempts ]; do
    if talosctl --talosconfig "$OUTPUT_DIR/talosconfig" config endpoint "$FIRST_CONTROL_PLANE_IP" 2>/dev/null && \
       talosctl --talosconfig "$OUTPUT_DIR/talosconfig" config node "$FIRST_CONTROL_PLANE_IP" 2>/dev/null && \
       talosctl --talosconfig "$OUTPUT_DIR/talosconfig" bootstrap 2>/dev/null; then
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

# Step 4: Apply config to additional control plane nodes
if [ ${#CONTROL_PLANE_IPS[@]} -gt 1 ]; then
    echo -e "${BLUE}=== Step 4: Adding Additional Control Plane Nodes ===${NC}\n"
    
    for i in $(seq 1 $((${#CONTROL_PLANE_IPS[@]} - 1))); do
        node_name="${CONTROL_PLANE_NODES[$i]}"
        node_ip="${CONTROL_PLANE_IPS[$i]}"
        echo -e "${YELLOW}Applying config to $node_name...${NC}"
        
        # Try to get IP from guest properties with retries
        INITIAL_NODE_IP=""
        for attempt in $(seq 1 12); do
            INITIAL_NODE_IP=$(VBoxManage guestproperty get "$node_name" "/VirtualBox/GuestInfo/Net/0/V4/IP" 2>/dev/null | grep "Value:" | awk '{print $2}' || echo "")
            if [ -n "$INITIAL_NODE_IP" ] && [ "$INITIAL_NODE_IP" != "No" ] && [ "$INITIAL_NODE_IP" != "value" ] && [ "$INITIAL_NODE_IP" != "No value set!" ]; then
                break
            fi
            sleep 2
        done
        
        # If still no IP, try the static IP
        if [ -z "$INITIAL_NODE_IP" ] || [ "$INITIAL_NODE_IP" = "No" ] || [ "$INITIAL_NODE_IP" = "value" ] || [ "$INITIAL_NODE_IP" = "No value set!" ]; then
            echo -e "${YELLOW}Could not detect DHCP IP, trying static IP $node_ip...${NC}"
            if ping -c 1 -W 2 "$node_ip" >/dev/null 2>&1; then
                INITIAL_NODE_IP="$node_ip"
                echo -e "${GREEN}✓ Static IP $node_ip is reachable${NC}"
            else
                echo -e "${YELLOW}⚠  Cannot connect to $node_name, skipping...${NC}"
                continue
            fi
        else
            echo -e "${GREEN}Detected VM IP: $INITIAL_NODE_IP${NC}"
        fi
        
        echo -e "${GREEN}Connecting to $node_name, will configure static IP $node_ip/${NETWORK_PREFIX}${NC}"
        
        # Apply config with static IP configuration on bridge network
        # Include gateway for proper routing
        talosctl apply-config --insecure --nodes "$INITIAL_NODE_IP" \
            --file "$OUTPUT_DIR/controlplane.yaml" \
            --config-patch @- <<EOF
machine:
  network:
    interfaces:
      - interface: eth0
        addresses:
          - ${node_ip}/${NETWORK_PREFIX}
        routes:
          - network: 0.0.0.0/0
            gateway: ${NETWORK_GATEWAY}
EOF
        
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}✓ Configuration applied to $node_ip${NC}\n"
        else
            echo -e "${YELLOW}⚠  Failed to apply to $node_ip, continuing...${NC}\n"
        fi
    done
fi

# Step 5: Get kubeconfig
echo -e "${BLUE}=== Step 5: Retrieving Kubeconfig ===${NC}\n"
sleep 30

talosctl --talosconfig "$OUTPUT_DIR/talosconfig" config endpoint "$FIRST_CONTROL_PLANE_IP"
talosctl --talosconfig "$OUTPUT_DIR/talosconfig" config node "$FIRST_CONTROL_PLANE_IP"
talosctl --talosconfig "$OUTPUT_DIR/talosconfig" kubeconfig .

if [ $? -eq 0 ]; then
    export KUBECONFIG="$(pwd)/kubeconfig"
    echo -e "${GREEN}✓ Kubeconfig retrieved${NC}\n"
    
    # Step 6: Verify cluster
    echo -e "${BLUE}=== Step 6: Verifying Cluster ===${NC}\n"
    echo -e "${YELLOW}Waiting for nodes to be ready...${NC}"
    
    max_attempts=40
    attempt=0
    while [ $attempt -lt $max_attempts ]; do
        READY_NODES=$(kubectl get nodes --no-headers 2>/dev/null | grep -c " Ready " || echo "0")
        if [ "$READY_NODES" -ge ${#CONTROL_PLANE_IPS[@]} ]; then
            break
        fi
        sleep 5
        attempt=$((attempt + 1))
        if [ $((attempt % 4)) -eq 0 ]; then
            echo -e "  Ready nodes: $READY_NODES/${#CONTROL_PLANE_IPS[@]} ($attempt/$max_attempts)"
        fi
    done
    
    echo ""
    kubectl get nodes
    echo ""
    
    echo -e "${BLUE}=== Setup Complete! ===${NC}\n"
    echo -e "${GREEN}Kubeconfig:${NC} $(pwd)/kubeconfig"
    echo -e "${GREEN}To use:${NC} export KUBECONFIG=$(pwd)/kubeconfig"
    echo ""
else
    echo -e "${RED}✗ Failed to retrieve kubeconfig${NC}"
    exit 1
fi
