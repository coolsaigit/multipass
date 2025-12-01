#!/bin/bash
set -euo pipefail

# Enterprise-grade RKE2 Cluster Deployment
# One-touch deployment script that orchestrates Multipass VMs and Rancher API
# Usage: 
#   ./deploy.sh create   - Create cluster
#   ./deploy.sh destroy  - Delete cluster
#   ./deploy.sh          - Create cluster (default)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Load configuration
if [ ! -f cluster.conf ]; then
    echo "Error: cluster.conf not found"
    echo "Copy cluster.conf.example to cluster.conf and configure it"
    exit 1
fi

# Parse cluster.conf
CLUSTER_NAME=$(grep -E "^cluster_name\s*=" cluster.conf | cut -d'"' -f2 || echo "dev-rke2")
K8S_VERSION=$(grep -E "^kubernetes_version\s*=" cluster.conf | cut -d'"' -f2 || echo "v1.32.8+rke2r1")
CONTROL_PLANE_COUNT=$(grep -E "^control_plane_count\s*=" cluster.conf | awk '{print $3}' || echo "3")
WORKER_COUNT=$(grep -E "^worker_count\s*=" cluster.conf | awk '{print $3}' || echo "3")
MULTIPASS_CPU=$(grep -E "^multipass_cpu\s*=" cluster.conf | awk '{print $3}' || echo "2")
MULTIPASS_MEMORY=$(grep -E "^multipass_memory\s*=" cluster.conf | cut -d'"' -f2 || echo "4G")
MULTIPASS_DISK=$(grep -E "^multipass_disk\s*=" cluster.conf | cut -d'"' -f2 || echo "50G")
MULTIPASS_IMAGE=$(grep -E "^multipass_image\s*=" cluster.conf | cut -d'"' -f2 || echo "22.04")

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

destroy() {
    echo -e "${YELLOW}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║           Destroying RKE2 Cluster                     ║${NC}"
    echo -e "${YELLOW}╚════════════════════════════════════════════════════════╝${NC}\n"
    
    # Load Rancher config
    RANCHER_URL=$(grep -E "^rancher_api_url\s*=" cluster.conf | cut -d'"' -f2 || echo "https://localhost:8443")
    RANCHER_TOKEN=$(grep -E "^rancher_token\s*=" cluster.conf | cut -d'"' -f2 || echo "")
    
    if [ -z "$RANCHER_TOKEN" ] || [[ "$RANCHER_TOKEN" == *"xxxxx"* ]]; then
        echo -e "${RED}✗ rancher_token not configured${NC}"
        echo "Edit cluster.conf and set your Rancher API token"
        exit 1
    fi
    
    # Step 1: Delete cluster from Rancher
    echo -e "${YELLOW}[1/3] Deleting cluster from Rancher...${NC}"
    CLUSTER_ID=$(curl -s -k -H "Authorization: Bearer $RANCHER_TOKEN" \
        "${RANCHER_URL}/v3/clusters?name=${CLUSTER_NAME}" | jq -r '.data[0].id // empty')
    
    if [ -n "$CLUSTER_ID" ]; then
        echo -e "${YELLOW}  Found cluster: ${CLUSTER_NAME} (ID: ${CLUSTER_ID})${NC}"
        
        # Get cluster state
        CLUSTER_STATE=$(curl -s -k -H "Authorization: Bearer $RANCHER_TOKEN" \
            "${RANCHER_URL}/v3/clusters/${CLUSTER_ID}" | jq -r '.state // empty')
        
        if [ "$CLUSTER_STATE" != "removing" ] && [ "$CLUSTER_STATE" != "removed" ]; then
            # Delete the cluster
            DELETE_RESPONSE=$(curl -s -k -X DELETE -H "Authorization: Bearer $RANCHER_TOKEN" \
                "${RANCHER_URL}/v3/clusters/${CLUSTER_ID}")
            
            if echo "$DELETE_RESPONSE" | jq -e '.id' >/dev/null 2>&1; then
                echo -e "${GREEN}✓ Cluster deletion initiated${NC}"
                
                # Wait for cluster to be removed (with timeout)
                echo -e "${YELLOW}  Waiting for cluster to be removed from Rancher...${NC}"
                for i in {1..30}; do
                    sleep 2
                    CLUSTER_STATE=$(curl -s -k -H "Authorization: Bearer $RANCHER_TOKEN" \
                        "${RANCHER_URL}/v3/clusters/${CLUSTER_ID}" 2>/dev/null | jq -r '.state // "removed"' || echo "removed")
                    if [ "$CLUSTER_STATE" = "removed" ] || [ "$CLUSTER_STATE" = "removing" ]; then
                        echo -e "${GREEN}✓ Cluster removed from Rancher${NC}\n"
                        break
                    fi
                    if [ $i -eq 30 ]; then
                        echo -e "${YELLOW}⚠ Cluster deletion still in progress (may take longer)${NC}\n"
                    fi
                done
            else
                echo -e "${RED}✗ Failed to delete cluster${NC}"
                echo "$DELETE_RESPONSE" | jq . 2>/dev/null || echo "$DELETE_RESPONSE"
            fi
        else
            echo -e "${GREEN}✓ Cluster already being removed${NC}\n"
        fi
    else
        echo -e "${YELLOW}  Cluster ${CLUSTER_NAME} not found in Rancher${NC}\n"
    fi
    
    # Step 2: Delete Multipass VMs
    echo -e "${YELLOW}[2/3] Deleting Multipass VMs...${NC}"
    NODES=$(multipass list --format csv 2>/dev/null | grep -E "${CLUSTER_NAME}-" | cut -d, -f1 || echo "")
    if [ -n "$NODES" ]; then
        for NODE in $NODES; do
            echo -e "${YELLOW}  Deleting ${NODE}...${NC}"
            multipass delete --purge "$NODE" 2>&1 | grep -v "deprecated" || true
        done
        echo -e "${GREEN}✓ VMs deleted${NC}\n"
    else
        echo -e "${GREEN}✓ No VMs to delete${NC}\n"
    fi
    
    # Step 3: Cleanup any remaining resources
    echo -e "${YELLOW}[3/3] Cleaning up...${NC}"
    # Remove any temporary files
    rm -f /tmp/multipass-cloud-init.yaml 2>/dev/null || true
    echo -e "${GREEN}✓ Cleanup complete${NC}\n"
    
    echo -e "${GREEN}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║           Cluster Destroyed Successfully              ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════╝${NC}\n"
    exit 0
}

# Main deployment function (everything below is the create logic)

# Handle command line arguments
case "${1:-create}" in
    create|deploy|"")
        # Continue with deployment (default behavior)
        ;;
    destroy|delete|remove)
        destroy
        ;;
    *)
        echo "Usage: $0 [create|destroy]"
        echo "  create  - Create/deploy cluster (default)"
        echo "  destroy - Delete/destroy cluster"
        exit 1
        ;;
esac

# Check prerequisites
echo -e "${BLUE}Checking prerequisites...${NC}"

command -v multipass &> /dev/null || {
    echo -e "${RED}✗ multipass not installed${NC}"
    echo "Install with: brew install --cask multipass"
    exit 1
}
echo -e "${GREEN}✓ multipass found${NC}"

# Check Rancher token
RANCHER_TOKEN=$(grep -E "^rancher_token\s*=" cluster.conf | cut -d'"' -f2 || echo "")
if [ -z "$RANCHER_TOKEN" ] || [[ "$RANCHER_TOKEN" == *"xxxxx"* ]]; then
    echo -e "${RED}✗ rancher_token not configured${NC}"
    echo "Edit cluster.conf and set your Rancher API token"
    exit 1
fi
echo -e "${GREEN}✓ Rancher token configured${NC}\n"

echo -e "${BLUE}╔════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║     Deploying RKE2 Cluster on Multipass              ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════╝${NC}\n"

# Step 1: Create Multipass VMs
echo -e "${GREEN}[1/3] Creating Multipass VMs...${NC}"

create_cloud_init() {
    cat > /tmp/multipass-cloud-init.yaml <<EOF
#cloud-config
package_update: true
package_upgrade: true
packages:
  - curl
  - wget
runcmd:
  - swapoff -a
  - sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab
  - |
    cat > /etc/sysctl.d/99-kubernetes.conf <<SYSCTL_EOF
    net.bridge.bridge-nf-call-iptables  = 1
    net.ipv4.ip_forward                 = 1
    net.bridge.bridge-nf-call-ip6tables = 1
    SYSCTL_EOF
  - sysctl --system
  - modprobe overlay
  - modprobe br_netfilter
  - |
    cat > /etc/modules-load.d/k8s.conf <<MODULES_EOF
    overlay
    br_netfilter
    MODULES_EOF
  - systemctl enable systemd-modules-load
EOF
}

create_cloud_init

# Create control plane nodes
for i in $(seq 1 $CONTROL_PLANE_COUNT); do
    NODE="${CLUSTER_NAME}-cp-${i}"
    if multipass list --format csv 2>/dev/null | grep -q "^${NODE},"; then
        echo -e "${YELLOW}  ${NODE} already exists, skipping${NC}"
    else
        echo -e "${GREEN}  Creating ${NODE}...${NC}"
        multipass launch "$MULTIPASS_IMAGE" \
            --name "$NODE" \
            --cpus "$MULTIPASS_CPU" \
            --memory "$MULTIPASS_MEMORY" \
            --disk "$MULTIPASS_DISK" \
            --cloud-init /tmp/multipass-cloud-init.yaml 2>&1 | grep -v "deprecated" || true
    fi
done

# Create worker nodes
for i in $(seq 1 $WORKER_COUNT); do
    NODE="${CLUSTER_NAME}-worker-${i}"
    if multipass list --format csv 2>/dev/null | grep -q "^${NODE},"; then
        echo -e "${YELLOW}  ${NODE} already exists, skipping${NC}"
    else
        echo -e "${GREEN}  Creating ${NODE}...${NC}"
        multipass launch "$MULTIPASS_IMAGE" \
            --name "$NODE" \
            --cpus "$MULTIPASS_CPU" \
            --memory "$MULTIPASS_MEMORY" \
            --disk "$MULTIPASS_DISK" \
            --cloud-init /tmp/multipass-cloud-init.yaml 2>&1 | grep -v "deprecated" || true
    fi
done

rm -f /tmp/multipass-cloud-init.yaml
echo -e "${GREEN}✓ VMs created${NC}\n"

# Step 2: Create cluster in Rancher (via API)
echo -e "${GREEN}[2/3] Creating cluster in Rancher...${NC}"
CLUSTER_V1_ID=$(./create-cluster.sh)
if [ -z "$CLUSTER_V1_ID" ]; then
    echo -e "${RED}Failed to create cluster${NC}"
    exit 1
fi

# Projects and namespaces are created by create-cluster.sh
echo -e "${GREEN}✓ Cluster and resources created in Rancher${NC}\n"

# Step 3: Register nodes
echo -e "${GREEN}[3/3] Registering nodes with Rancher...${NC}"

# Wait for registration token to be available
sleep 5
REG_CMD=$(./get-registration-token.sh 2>/dev/null || echo "")

if [ -z "$REG_CMD" ]; then
    echo -e "${RED}Error: Registration command not available${NC}"
    echo "Waiting a bit longer..."
    sleep 10
    REG_CMD=$(./get-registration-token.sh 2>/dev/null || echo "")
    if [ -z "$REG_CMD" ]; then
        echo -e "${RED}Failed to get registration command${NC}"
        exit 1
    fi
fi

# Register control plane nodes (add --etcd --controlplane roles)
for i in $(seq 1 $CONTROL_PLANE_COUNT); do
    NODE="${CLUSTER_NAME}-cp-${i}"
    echo -e "${YELLOW}  Registering ${NODE} (control plane)...${NC}"
    CP_CMD=$(echo "$REG_CMD" | sed 's|--label|--etcd --controlplane --label|')
    multipass exec "$NODE" -- bash -c "$CP_CMD" || {
        echo -e "${RED}  Failed to register ${NODE}${NC}"
        exit 1
    }
done

# Register worker nodes (add --worker role)
for i in $(seq 1 $WORKER_COUNT); do
    NODE="${CLUSTER_NAME}-worker-${i}"
    echo -e "${YELLOW}  Registering ${NODE} (worker)...${NC}"
    WORKER_CMD=$(echo "$REG_CMD" | sed 's|--label|--worker --label|')
    multipass exec "$NODE" -- bash -c "$WORKER_CMD" || {
        echo -e "${RED}  Failed to register ${NODE}${NC}"
        exit 1
    }
done

echo -e "${GREEN}✓ All nodes registered${NC}\n"

# Step 4: Fix agent configuration (replace localhost with host IP)
echo -e "${GREEN}[4/4] Fixing agent configuration...${NC}"
./fix-agent-config.sh >/dev/null 2>&1 || {
    echo -e "${YELLOW}⚠ Could not auto-fix agent config. Run ./fix-agent-config.sh manually if needed${NC}"
}

# Wait for cluster to be ready before fixing cluster agent
echo -e "${YELLOW}  Waiting for cluster to be ready...${NC}"
for i in {1..60}; do
    sleep 5
    if multipass exec "${CLUSTER_NAME}-cp-1" -- sudo /var/lib/rancher/rke2/bin/kubectl \
        --kubeconfig /etc/rancher/rke2/rke2.yaml get nodes 2>/dev/null | grep -q Ready; then
        echo -e "${GREEN}✓ Cluster is ready${NC}"
        break
    fi
    if [ $i -eq 60 ]; then
        echo -e "${YELLOW}⚠ Cluster taking longer than expected${NC}"
    fi
done

# Fix cluster agent deployment
echo -e "${YELLOW}  Fixing cluster agent...${NC}"
./fix-cluster-agent.sh >/dev/null 2>&1 || {
    echo -e "${YELLOW}⚠ Could not auto-fix cluster agent. Run ./fix-cluster-agent.sh manually if needed${NC}"
}
echo -e "${GREEN}✓ Agent configuration updated${NC}\n"

# Show success message
echo -e "${BLUE}╔════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║           Deployment Complete!                        ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════╝${NC}\n"

echo -e "${GREEN}Cluster: ${CLUSTER_NAME}${NC}"
echo -e "${GREEN}Kubernetes Version: ${K8S_VERSION}${NC}"
echo -e "${GREEN}Access Rancher UI: https://localhost:8443${NC}"

echo -e "\n${GREEN}Next steps:${NC}"
echo "  - Wait 5-10 minutes for cluster to be fully ready"
echo "  - Check status: kubectl get nodes"
echo "  - Access Rancher UI: https://localhost:8443"
echo ""

