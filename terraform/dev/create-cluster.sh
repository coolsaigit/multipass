#!/bin/bash
set -euo pipefail

# Create RKE2 cluster via Rancher API
# This script creates the cluster, projects, and namespaces

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Load config
if [ ! -f cluster.conf ]; then
    echo "Error: cluster.conf not found"
    exit 1
fi

RANCHER_URL=$(grep -E "^rancher_api_url\s*=" cluster.conf | cut -d'"' -f2 || echo "https://localhost:8443")
RANCHER_TOKEN=$(grep -E "^rancher_token\s*=" cluster.conf | cut -d'"' -f2 || echo "")
CLUSTER_NAME=$(grep -E "^cluster_name\s*=" cluster.conf | cut -d'"' -f2 || echo "dev-rke2")
K8S_VERSION=$(grep -E "^kubernetes_version\s*=" cluster.conf | cut -d'"' -f2 || echo "v1.32.8+rke2r1")
CNI=$(grep -E "^cni\s*=" cluster.conf | cut -d'"' -f2 || echo "calico")
ENABLE_NETWORK_POLICY=$(grep -E "^enable_network_policy\s*=" cluster.conf | awk '{print $3}' || echo "true")

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Check if cluster already exists
EXISTING=$(curl -s -k -H "Authorization: Bearer $RANCHER_TOKEN" \
    "${RANCHER_URL}/v3/clusters?name=${CLUSTER_NAME}" | jq -r '.data[0].id // empty')

if [ -n "$EXISTING" ]; then
    echo -e "${YELLOW}Cluster ${CLUSTER_NAME} already exists (ID: ${EXISTING})${NC}" >&2
    # Get cluster_v1_id
    CLUSTER_V1_ID=$(curl -s -k -H "Authorization: Bearer $RANCHER_TOKEN" \
        "${RANCHER_URL}/v3/clusters/${EXISTING}" | jq -r '.clusterV1Id // .id // empty')
    if [ -z "$CLUSTER_V1_ID" ]; then
        CLUSTER_V1_ID="$EXISTING"
    fi
    echo "$CLUSTER_V1_ID"
    exit 0
fi

# Create cluster via Rancher API
echo -e "${GREEN}Creating RKE2 cluster via Rancher API...${NC}"

CLUSTER_DATA=$(cat <<EOF
{
  "type": "cluster",
  "name": "${CLUSTER_NAME}",
  "kubernetesVersion": "${K8S_VERSION}",
  "enableNetworkPolicy": ${ENABLE_NETWORK_POLICY},
  "rkeConfig": {
    "machineGlobalConfig": "{\"cni\":\"${CNI}\",\"disable-kube-proxy\":false,\"etcd-expose-metrics\":false}",
    "machineSelectorConfig": [{
      "config": "{\"protect-kernel-defaults\":false}"
    }]
  }
}
EOF
)

RESPONSE=$(curl -s -k -X POST \
    -H "Authorization: Bearer $RANCHER_TOKEN" \
    -H "Content-Type: application/json" \
    -d "$CLUSTER_DATA" \
    "${RANCHER_URL}/v3/clusters")

CLUSTER_ID=$(echo "$RESPONSE" | jq -r '.id // empty')

if [ -z "$CLUSTER_ID" ] || [ "$CLUSTER_ID" = "null" ]; then
    echo -e "${RED}Error: Failed to create cluster${NC}"
    echo "$RESPONSE" | jq .
    exit 1
fi

echo -e "${GREEN}✓ Cluster created (ID: ${CLUSTER_ID})${NC}" >&2

# Get cluster_v1_id (needed for projects/namespaces)
sleep 2
CLUSTER_V1_ID=$(curl -s -k -H "Authorization: Bearer $RANCHER_TOKEN" \
    "${RANCHER_URL}/v3/clusters/${CLUSTER_ID}" | jq -r '.clusterV1Id // .id // empty')

if [ -z "$CLUSTER_V1_ID" ]; then
    CLUSTER_V1_ID="$CLUSTER_ID"
fi

# Output only the cluster_v1_id (no messages to stdout)
echo "$CLUSTER_V1_ID"

# Create default project and namespace via API
sleep 3
echo -e "${GREEN}Creating default project and namespace...${NC}" >&2

# Create default project
PROJECT_DATA="{\"type\":\"project\",\"name\":\"Default\",\"description\":\"Default project for ${CLUSTER_NAME}\"}"
PROJECT_RESPONSE=$(curl -s -k -X POST \
    -H "Authorization: Bearer $RANCHER_TOKEN" \
    -H "Content-Type: application/json" \
    -d "$PROJECT_DATA" \
    "${RANCHER_URL}/v3/projects?clusterId=${CLUSTER_V1_ID}")

PROJECT_ID=$(echo "$PROJECT_RESPONSE" | jq -r '.id // empty')
if [ -n "$PROJECT_ID" ]; then
    echo -e "${GREEN}✓ Project created${NC}" >&2
    
    # Create applications namespace
    sleep 2
    NS_DATA="{\"type\":\"namespace\",\"name\":\"applications\",\"projectId\":\"${PROJECT_ID}\",\"description\":\"Namespace for application deployments\"}"
    NS_RESPONSE=$(curl -s -k -X POST \
        -H "Authorization: Bearer $RANCHER_TOKEN" \
        -H "Content-Type: application/json" \
        -d "$NS_DATA" \
        "${RANCHER_URL}/v3/namespaces")
    
    echo -e "${GREEN}✓ Namespace created${NC}" >&2
fi

