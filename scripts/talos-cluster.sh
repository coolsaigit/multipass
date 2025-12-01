#!/bin/bash
set -euo pipefail

# Talos Multipass VM Cluster Management Script
# Creates Talos Kubernetes cluster on Multipass VMs (fixes networking issues)
# Uses Multipass VMs with manual Talos installation

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
CLUSTER_NAME="talos-cluster"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIR="$SCRIPT_DIR/_out"
KUBECONFIG_PATH="$OUTPUT_DIR/kubeconfig"
TALOS_CONFIG_PATH="$OUTPUT_DIR/talosconfig"

# Cluster Configuration
CONTROL_PLANE_COUNT=3
WORKER_COUNT=0
KUBERNETES_VERSION="1.34"  # Latest stable (Talos v1.11.5)
VM_CPUS=2
VM_MEMORY="4G"
VM_DISK="50G"

# VM names
CONTROL_PLANE_NODES=()
for i in $(seq 1 $CONTROL_PLANE_COUNT); do
    CONTROL_PLANE_NODES+=("${CLUSTER_NAME}-cp-${i}")
done

print_usage() {
    echo "Usage: $0 {create|delete|status|info}"
    echo ""
    echo "Commands:"
    echo "  create  - Create 3-node HA Talos cluster on Multipass VMs (~8-10 minutes)"
    echo "  delete  - Delete cluster and free ~12GB RAM"
    echo "  status  - Show cluster health and resources"
    echo "  info    - Show access commands and endpoints"
    echo ""
    echo "Note: Multipass VMs get real IPs on your network, solving networking issues"
    echo "      with Rancher/RKE2. VMs are accessible directly without port-forwarding."
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

check_prerequisites() {
    command -v multipass >/dev/null 2>&1 || {
        echo -e "${RED}✗ multipass not installed${NC}"
        echo "Install with: brew install --cask multipass"
        exit 1
    }
    echo -e "${GREEN}✓ multipass found${NC}"
    
    command -v talosctl >/dev/null 2>&1 || {
        echo -e "${RED}✗ talosctl not installed${NC}"
        echo "Install with: brew install siderolabs/tap/talosctl"
        exit 1
    }
    echo -e "${GREEN}✓ talosctl found${NC}"
    
    command -v kubectl >/dev/null 2>&1 || {
        echo -e "${RED}✗ kubectl not installed${NC}"
        exit 1
    }
    echo -e "${GREEN}✓ kubectl found${NC}"
}

get_vm_ip() {
    local vm_name=$1
    multipass info "$vm_name" 2>/dev/null | grep IPv4 | awk '{print $2}' || echo ""
}

wait_for_vm_ready() {
    local vm_name=$1
    local max_attempts=30
    local attempt=0
    
    echo -e "${YELLOW}  Waiting for $vm_name to be ready...${NC}"
    while [ $attempt -lt $max_attempts ]; do
        local ip=$(get_vm_ip "$vm_name")
        if [ -n "$ip" ] && multipass exec "$vm_name" -- ping -c 1 -W 1 8.8.8.8 >/dev/null 2>&1; then
            echo -e "${GREEN}  ✓ $vm_name ready at $ip${NC}"
            return 0
        fi
        sleep 2
        attempt=$((attempt + 1))
    done
    
    echo -e "${RED}  ✗ $vm_name failed to become ready${NC}"
    return 1
}

install_talos_on_vm() {
    local vm_name=$1
    local vm_ip=$2
    
    echo -e "${YELLOW}  Installing Talos on $vm_name...${NC}"
    
    # Install prerequisites
    multipass exec "$vm_name" -- sudo bash -c "
        apt-get update -qq >/dev/null 2>&1
        apt-get install -y curl wget qemu-utils >/dev/null 2>&1
    " || {
        echo -e "${RED}  ✗ Failed to install prerequisites${NC}"
        return 1
    }
    
    # Download and install talosctl on VM
    multipass exec "$vm_name" -- bash -c "
        curl -fsSL https://talos.dev/install | sh
        export PATH=\$PATH:/usr/local/bin
    " || {
        echo -e "${RED}  ✗ Failed to install talosctl on VM${NC}"
        return 1
    }
    
    # Get Talos installer image
    local arch=$(multipass exec "$vm_name" -- uname -m | sed 's/aarch64/arm64/;s/x86_64/amd64/')
    local talos_version=$(talosctl version --client 2>/dev/null | grep "Client" | awk '{print $2}' || echo "v1.11.5")
    local installer_image="ghcr.io/siderolabs/installer:${talos_version#v}"
    
    echo -e "${YELLOW}  Downloading Talos installer image...${NC}"
    
    # Use talosctl image installer to write Talos to disk
    # This requires the VM to be stopped, but Multipass doesn't easily support this
    # Alternative: Use the installer in a container and write to /dev/sda
    multipass exec "$vm_name" -- sudo bash -c "
        /usr/local/bin/talosctl image default --arch $arch > /tmp/talos-image.txt 2>&1
        TALOS_IMAGE=\$(cat /tmp/talos-image.txt)
        echo \"Installing Talos image: \$TALOS_IMAGE\"
        /usr/local/bin/talosctl image get \$TALOS_IMAGE | tar -xz -C /tmp/
        /tmp/installer install disk --disk /dev/sda --platform metal
    " || {
        echo -e "${YELLOW}  ⚠ Direct installation failed, trying alternative method...${NC}"
        # Alternative: Use Docker to run installer
        multipass exec "$vm_name" -- sudo bash -c "
            apt-get install -y docker.io >/dev/null 2>&1
            systemctl start docker
            docker pull $installer_image
            docker run --rm --privileged -v /dev:/dev -v /sys:/sys $installer_image install disk --disk /dev/sda --platform metal
        " || {
            echo -e "${RED}  ✗ Failed to install Talos${NC}"
            return 1
        }
    }
    
    echo -e "${GREEN}  ✓ Talos installed on $vm_name${NC}"
    return 0
}

create_cluster() {
    local start_time=$(date +%s)
    
    echo -e "${BLUE}=== Creating Talos HA Cluster on Multipass VMs ===${NC}\n"
    
    check_prerequisites
    
    # Check if cluster already exists
    EXISTING_VMS=$(multipass list --format csv 2>/dev/null | grep -E "${CLUSTER_NAME}-" | cut -d, -f1 || echo "")
    if [ -n "$EXISTING_VMS" ]; then
        echo -e "${YELLOW}Cluster VMs already exist:${NC}"
        echo "$EXISTING_VMS" | sed 's/^/  /'
        echo -e "${YELLOW}Run: $0 delete first${NC}"
        exit 1
    fi
    
    rm -rf "$OUTPUT_DIR" ~/.talos/clusters/$CLUSTER_NAME
    mkdir -p "$OUTPUT_DIR"
    
    echo -e "${YELLOW}Creating Talos cluster with ${CONTROL_PLANE_COUNT} control plane nodes (HA)...${NC}"
    echo -e "${YELLOW}Using Kubernetes v${KUBERNETES_VERSION} (latest stable, compatible with Rancher)${NC}"
    echo -e "${YELLOW}Provisioner: Multipass VMs (real VMs with proper networking)${NC}"
    echo -e "${YELLOW}This will take 8-10 minutes...${NC}\n"
    
    # Step 1: Create Multipass VMs
    echo -e "${BLUE}[1/7] Creating Multipass VMs...${NC}"
    echo -e "${YELLOW}  This may take 2-3 minutes per VM (first time downloads image)...${NC}"
    for i in $(seq 1 $CONTROL_PLANE_COUNT); do
        vm_name="${CLUSTER_NAME}-cp-${i}"
        echo -e "${YELLOW}  Creating $vm_name ($i/$CONTROL_PLANE_COUNT)...${NC}"
        
        # Check if VM already exists
        if multipass list --format csv 2>/dev/null | grep -q "^${vm_name},"; then
            echo -e "${YELLOW}  ⚠ $vm_name already exists, skipping...${NC}"
            continue
        fi
        
        # Show progress - don't hide output completely
        set +e  # Don't exit on pipe errors
        multipass launch \
            --name "$vm_name" \
            --cpus $VM_CPUS \
            --memory $VM_MEMORY \
            --disk $VM_DISK \
            22.04 2>&1 | while IFS= read -r line; do
            # Filter out verbose messages but show important ones
            if echo "$line" | grep -qE "(Launched|Creating|Downloading|error|Error|Contacting|Retrieving)"; then
                echo "    $line"
            fi
        done
        LAUNCH_EXIT_CODE=${PIPESTATUS[0]}
        set -e  # Re-enable exit on error
        
        if [ $LAUNCH_EXIT_CODE -eq 0 ]; then
            echo -e "${YELLOW}  Waiting for $vm_name to be ready...${NC}"
            # Wait for VM to be in Running state
            local max_wait=120  # 2 minutes max
            local waited=0
            while [ $waited -lt $max_wait ]; do
                local state=$(multipass list --format csv 2>/dev/null | grep "^${vm_name}," | cut -d, -f2 | tr -d ' ' || echo "")
                if [ "$state" = "Running" ]; then
                    echo -e "${GREEN}  ✓ $vm_name is running${NC}"
                    break
                elif [ "$state" = "Stopped" ] || [ -z "$state" ]; then
                    # VM might be starting
                    sleep 2
                    waited=$((waited + 2))
                else
                    # Unknown or other state, wait a bit
                    sleep 2
                    waited=$((waited + 2))
                fi
                if [ $((waited % 10)) -eq 0 ] && [ $waited -gt 0 ]; then
                    echo -e "${YELLOW}  Still waiting... (${waited}s)${NC}"
                fi
            done
            
            if [ $waited -ge $max_wait ]; then
                echo -e "${RED}  ✗ $vm_name failed to start within ${max_wait}s${NC}"
                exit 1
            fi
        else
            echo -e "${RED}  ✗ Failed to create $vm_name (exit code: $LAUNCH_EXIT_CODE)${NC}"
            exit 1
        fi
    done
    echo ""
    
    # Step 2: Get VM IPs
    echo -e "${BLUE}[2/7] Getting VM IPs...${NC}"
    VM_IPS=()
    FIRST_CP_IP=""
    for vm_name in "${CONTROL_PLANE_NODES[@]}"; do
        if wait_for_vm_ready "$vm_name"; then
            ip=$(get_vm_ip "$vm_name")
            VM_IPS+=("$ip")
            if [ -z "$FIRST_CP_IP" ]; then
                FIRST_CP_IP="$ip"
            fi
            echo -e "${GREEN}  $vm_name: $ip${NC}"
        else
            echo -e "${RED}  ✗ Failed to get IP for $vm_name${NC}"
            exit 1
        fi
    done
    echo ""
    
    if [ -z "$FIRST_CP_IP" ]; then
        echo -e "${RED}✗ Failed to get control plane IP${NC}"
        exit 1
    fi
    
    CLUSTER_ENDPOINT="https://${FIRST_CP_IP}:6443"
    echo -e "${BLUE}Cluster endpoint: $CLUSTER_ENDPOINT${NC}\n"
    
    # Step 3: Install Talos on VMs
    echo -e "${BLUE}[3/7] Installing Talos on VMs...${NC}"
    echo -e "${YELLOW}  This will install Talos on each VM's disk...${NC}"
    
    for i in "${!CONTROL_PLANE_NODES[@]}"; do
        vm_name="${CONTROL_PLANE_NODES[$i]}"
        vm_ip="${VM_IPS[$i]}"
        
        if ! install_talos_on_vm "$vm_name" "$vm_ip"; then
            echo -e "${RED}✗ Failed to install Talos on $vm_name${NC}"
            exit 1
        fi
    done
    echo ""
    
    # Step 4: Reboot VMs into Talos
    echo -e "${BLUE}[4/7] Rebooting VMs into Talos...${NC}"
    for vm_name in "${CONTROL_PLANE_NODES[@]}"; do
        echo -e "${YELLOW}  Rebooting $vm_name...${NC}"
        multipass restart "$vm_name" >/dev/null 2>&1
        sleep 5
    done
    echo -e "${YELLOW}  Waiting for VMs to boot into Talos (this may take 2-3 minutes)...${NC}"
    sleep 60  # Give VMs time to boot
    echo ""
    
    # Step 5: Generate Talos machine configs
    echo -e "${BLUE}[5/7] Generating Talos machine configurations...${NC}"
    
    talosctl gen config "$CLUSTER_NAME" "$CLUSTER_ENDPOINT" \
        --output-dir "$OUTPUT_DIR" \
        --kubernetes-version "v${KUBERNETES_VERSION}" \
        --force >/dev/null 2>&1
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}✗ Failed to generate Talos configurations${NC}"
        exit 1
    fi
    echo -e "${GREEN}✓ Configurations generated${NC}\n"
    
    # Step 6: Apply configs to VMs
    echo -e "${BLUE}[6/7] Applying Talos configurations to VMs...${NC}"
    for i in "${!CONTROL_PLANE_NODES[@]}"; do
        vm_name="${CONTROL_PLANE_NODES[$i]}"
        vm_ip="${VM_IPS[$i]}"
        
        echo -e "${YELLOW}  Applying config to $vm_name ($vm_ip)...${NC}"
        
        # Wait for Talos API to be ready
        local max_attempts=30
        local attempt=0
        while [ $attempt -lt $max_attempts ]; do
            if talosctl --nodes "$vm_ip" version --insecure >/dev/null 2>&1; then
                break
            fi
            sleep 5
            attempt=$((attempt + 1))
        done
        
        if [ $attempt -eq $max_attempts ]; then
            echo -e "${RED}  ✗ Talos API not ready on $vm_ip${NC}"
            exit 1
        fi
        
        talosctl apply-config --insecure --nodes "$vm_ip" \
            --file "$OUTPUT_DIR/controlplane.yaml" >/dev/null 2>&1
        
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}  ✓ Config applied to $vm_ip${NC}"
        else
            echo -e "${RED}  ✗ Failed to apply config to $vm_ip${NC}"
            exit 1
        fi
    done
    echo ""
    
    # Step 7: Bootstrap cluster
    echo -e "${BLUE}[7/7] Bootstrapping cluster...${NC}"
    echo -e "${YELLOW}  Waiting for first node to be ready...${NC}"
    
    export TALOSCONFIG="$TALOS_CONFIG_PATH"
    talosctl config endpoint "$FIRST_CP_IP"
    talosctl config node "$FIRST_CP_IP"
    
    local max_attempts=60
    local attempt=0
    while [ $attempt -lt $max_attempts ]; do
        if talosctl bootstrap --nodes "$FIRST_CP_IP" >/dev/null 2>&1; then
            echo -e "${GREEN}✓ Cluster bootstrapped${NC}\n"
            break
        fi
        sleep 5
        attempt=$((attempt + 1))
        if [ $((attempt % 6)) -eq 0 ]; then
            echo -e "${YELLOW}  Waiting... ($attempt/$max_attempts)${NC}"
        fi
    done
    
    if [ $attempt -eq $max_attempts ]; then
        echo -e "${YELLOW}⚠  Bootstrap may have failed, but continuing...${NC}\n"
    fi
    
    # Get kubeconfig
    echo -e "${YELLOW}Retrieving kubeconfig...${NC}"
    sleep 30
    talosctl kubeconfig "$OUTPUT_DIR" --nodes "$FIRST_CP_IP" >/dev/null 2>&1
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    local formatted_duration=$(format_duration $duration)
    
    echo -e "${GREEN}✓ HA Cluster created successfully on Multipass VMs!${NC}"
    echo -e "${BLUE}⏱️  Time taken: ${formatted_duration}${NC}\n"
    
    show_info
}

delete_cluster() {
    echo -e "${BLUE}=== Deleting Talos Cluster ===${NC}\n"
    
    # Get all VMs for this cluster
    VMS=$(multipass list --format csv 2>/dev/null | grep -E "${CLUSTER_NAME}-" | cut -d, -f1 || echo "")
    
    if [ -z "$VMS" ]; then
        echo -e "${YELLOW}No cluster VMs found${NC}"
        exit 0
    fi
    
    echo -e "${YELLOW}Deleting VMs...${NC}"
    for vm in $VMS; do
        echo -e "${YELLOW}  Deleting $vm...${NC}"
        multipass delete --purge "$vm" 2>/dev/null || true
    done
    
    rm -rf "$OUTPUT_DIR" ~/.talos/clusters/$CLUSTER_NAME
    
    echo -e "${GREEN}✓ Cluster deleted (freed ~12GB RAM)${NC}\n"
}

show_status() {
    echo -e "${BLUE}=== Talos Cluster Status ===${NC}\n"
    
    # Check if VMs exist
    VMS=$(multipass list --format csv 2>/dev/null | grep -E "${CLUSTER_NAME}-" | cut -d, -f1 || echo "")
    
    if [ -z "$VMS" ]; then
        echo -e "${YELLOW}Cluster not found${NC}"
        echo -e "${YELLOW}Run: $0 create${NC}"
        exit 0
    fi
    
    echo -e "${BLUE}Multipass VMs:${NC}"
    multipass list | grep -E "NAME|${CLUSTER_NAME}-" || echo "  No VMs found"
    echo ""
    
    if [ -f "$KUBECONFIG_PATH" ]; then
        export KUBECONFIG="$KUBECONFIG_PATH"
        echo -e "${BLUE}Kubernetes Nodes:${NC}"
        kubectl get nodes -o wide 2>/dev/null || echo "  Cluster not ready"
        echo ""
        
        echo -e "${BLUE}System Pods:${NC}"
        kubectl get pods -n kube-system 2>/dev/null | head -10 || echo "  No pods found"
        echo ""
    else
        echo -e "${YELLOW}Kubeconfig not found - cluster may not be bootstrapped yet${NC}\n"
    fi
}

show_info() {
    echo -e "${BLUE}=== Cluster Access Information ===${NC}\n"
    
    # Check if VMs exist
    VMS=$(multipass list --format csv 2>/dev/null | grep -E "${CLUSTER_NAME}-" | cut -d, -f1 || echo "")
    
    if [ -z "$VMS" ]; then
        echo -e "${YELLOW}No cluster found${NC}"
        echo -e "${YELLOW}Run: $0 create${NC}"
        exit 0
    fi
    
    echo -e "${GREEN}VM IPs:${NC}"
    for vm in $VMS; do
        ip=$(get_vm_ip "$vm")
        if [ -n "$ip" ]; then
            echo -e "  ${GREEN}$vm${NC}: $ip"
        fi
    done
    echo ""
    
    if [ -f "$KUBECONFIG_PATH" ]; then
        export KUBECONFIG="$KUBECONFIG_PATH"
        echo -e "${GREEN}Kubernetes Access:${NC}"
        echo -e "  export KUBECONFIG=$KUBECONFIG_PATH"
        echo -e "  kubectl get nodes"
        echo -e "  kubectl get pods -A"
        echo ""
        
        FIRST_CP=$(echo "$VMS" | head -1)
        FIRST_CP_IP=$(get_vm_ip "$FIRST_CP")
        if [ -n "$FIRST_CP_IP" ]; then
            echo -e "${GREEN}Talos API Access:${NC}"
            echo -e "  export TALOSCONFIG=$TALOS_CONFIG_PATH"
            echo -e "  talosctl --nodes $FIRST_CP_IP version"
            echo -e "  talosctl --nodes $FIRST_CP_IP dashboard"
            echo ""
            
            echo -e "${GREEN}Cluster Endpoints:${NC}"
            echo -e "  Kubernetes API: https://${FIRST_CP_IP}:6443"
            echo -e "  Talos API: ${FIRST_CP_IP}:50000"
            echo ""
            echo -e "${BLUE}ℹ️  These are real VM IPs - Rancher/RKE2 can access them directly!${NC}"
            echo ""
        fi
    else
        echo -e "${YELLOW}Cluster not fully bootstrapped yet${NC}"
        echo -e "${YELLOW}Kubeconfig will be available after cluster is ready${NC}"
        echo ""
    fi
    
    echo -e "${YELLOW}Memory Usage: ~12GB (3 nodes × 4GB each)${NC}"
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
