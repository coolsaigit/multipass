#!/bin/bash
set -euo pipefail

# Get registration token from Rancher API

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

# Get cluster ID
CLUSTER_ID=$(curl -s -k -H "Authorization: Bearer $RANCHER_TOKEN" \
    "${RANCHER_URL}/v3/clusters?name=${CLUSTER_NAME}" | jq -r '.data[0].id // empty')

if [ -z "$CLUSTER_ID" ]; then
    echo "Error: Cluster not found"
    exit 1
fi

# Get or create registration token
TOKEN_RESPONSE=$(curl -s -k -X POST \
    -H "Authorization: Bearer $RANCHER_TOKEN" \
    -H "Content-Type: application/json" \
    -d '{"type":"clusterRegistrationToken"}' \
    "${RANCHER_URL}/v3/clusters/${CLUSTER_ID}/clusterregistrationtokens" 2>/dev/null || echo "")

# If creation failed, try to get existing token
if [ -z "$TOKEN_RESPONSE" ] || echo "$TOKEN_RESPONSE" | jq -e '.id == null' >/dev/null 2>&1; then
    sleep 2
    TOKENS=$(curl -s -k -H "Authorization: Bearer $RANCHER_TOKEN" \
        "${RANCHER_URL}/v3/clusters/${CLUSTER_ID}/clusterregistrationtokens")
    TOKEN=$(echo "$TOKENS" | jq -r '.data[0].token // empty')
else
    TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.token // empty')
fi

if [ -z "$TOKEN" ]; then
    echo "Error: Failed to get registration token" >&2
    exit 1
fi

# Get the insecure node command directly from the token
TOKENS_RESPONSE=$(curl -s -k -H "Authorization: Bearer $RANCHER_TOKEN" \
    "${RANCHER_URL}/v3/clusters/${CLUSTER_ID}/clusterregistrationtokens")
NODE_COMMAND=$(echo "$TOKENS_RESPONSE" | jq -r '.data[0].insecureNodeCommand // .data[0].nodeCommand // empty')

# Get host IP that VMs can reach (gateway IP)
HOST_IP="localhost"
if command -v multipass >/dev/null 2>&1; then
    FIRST_VM=$(multipass list --format csv 2>/dev/null | grep -v "^Name," | head -1 | cut -d',' -f1)
    if [ -n "$FIRST_VM" ]; then
        GATEWAY=$(multipass exec "$FIRST_VM" -- ip route 2>/dev/null | grep default | awk '{print $3}' || echo "")
        if [ -n "$GATEWAY" ]; then
            HOST_IP="$GATEWAY"
        fi
    fi
fi

if [ -n "$NODE_COMMAND" ] && [ "$NODE_COMMAND" != "null" ]; then
    # Replace ALL occurrences of localhost with host IP that VMs can reach
    # Need to replace both in URLs and in the --server flag
    NODE_COMMAND=$(echo "$NODE_COMMAND" | sed "s|localhost|${HOST_IP}|g")
    NODE_COMMAND=$(echo "$NODE_COMMAND" | sed "s|127\.0\.0\.1|${HOST_IP}|g")
    
    # Remove CA checksum verification (port-forward certificate mismatch issue)
    # This is less secure but necessary when using port-forward
    NODE_COMMAND=$(echo "$NODE_COMMAND" | sed "s|--ca-checksum [a-f0-9]*||")
    
    # The system-agent-install.sh script has hardcoded localhost URLs
    # We need to modify the script as it's downloaded to replace localhost
    # Insert sed between curl and sh to replace localhost in the downloaded script
    # Replace "| sudo  sh" with "| sed 's/localhost:8443/${HOST_IP}:8443/g' | sed 's/127.0.0.1:8443/${HOST_IP}:8443/g' | sudo sh"
    NODE_COMMAND="${NODE_COMMAND%| sudo  sh*} | sed 's/localhost:8443/${HOST_IP}:8443/g' | sed 's/127.0.0.1:8443/${HOST_IP}:8443/g' | sudo sh ${NODE_COMMAND#*| sudo  sh }"
    
    echo "$NODE_COMMAND"
else
    # Fallback: construct command manually
    RANCHER_PORT=$(echo "$RANCHER_URL" | sed 's|.*:||' | cut -d/ -f1)
    if [ -z "$RANCHER_PORT" ] || [ "$RANCHER_PORT" = "localhost" ]; then
        RANCHER_PORT="8443"
    fi
    REG_CMD="curl -fL --insecure https://${HOST_IP}:${RANCHER_PORT}/v3/import/${TOKEN}.yaml | sudo kubectl apply -f -"
    echo "$REG_CMD"
fi

