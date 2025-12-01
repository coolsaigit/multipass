#!/bin/bash
set -euo pipefail

# Fix rancher-system-agent configuration to use host IP instead of localhost
# This is needed when using port-forward

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Load config
if [ ! -f cluster.conf ]; then
    echo "Error: cluster.conf not found"
    exit 1
fi

CLUSTER_NAME=$(grep -E "^cluster_name\s*=" cluster.conf | cut -d'"' -f2 || echo "dev-rke2")

# Get host IP that VMs can reach
HOST_IP="192.168.64.1"
if command -v multipass >/dev/null 2>&1; then
    FIRST_VM=$(multipass list --format csv 2>/dev/null | grep -v "^Name," | head -1 | cut -d',' -f1)
    if [ -n "$FIRST_VM" ]; then
        GATEWAY=$(multipass exec "$FIRST_VM" -- ip route 2>/dev/null | grep default | awk '{print $3}' || echo "")
        if [ -n "$GATEWAY" ]; then
            HOST_IP="$GATEWAY"
        fi
    fi
fi

echo "Fixing rancher-system-agent configuration on all nodes..."
echo "Using host IP: $HOST_IP"

# Fix all nodes
NODES=$(multipass list --format csv 2>/dev/null | grep -E "${CLUSTER_NAME}-" | cut -d, -f1 || echo "")

if [ -z "$NODES" ]; then
    echo "No nodes found for cluster ${CLUSTER_NAME}"
    exit 1
fi

for NODE in $NODES; do
    echo "Fixing $NODE..."
    
    # Fix connection info JSON
    if multipass exec "$NODE" -- sudo test -f /var/lib/rancher/agent/rancher2_connection_info.json 2>/dev/null; then
        multipass exec "$NODE" -- sudo sed -i "s|localhost:8443|${HOST_IP}:8443|g" /var/lib/rancher/agent/rancher2_connection_info.json 2>/dev/null || true
        multipass exec "$NODE" -- sudo sed -i "s|127.0.0.1:8443|${HOST_IP}:8443|g" /var/lib/rancher/agent/rancher2_connection_info.json 2>/dev/null || true
    fi
    
    # Fix agent config YAML
    if multipass exec "$NODE" -- sudo test -f /etc/rancher/agent/config.yaml 2>/dev/null; then
        multipass exec "$NODE" -- sudo sed -i "s|localhost:8443|${HOST_IP}:8443|g" /etc/rancher/agent/config.yaml 2>/dev/null || true
        multipass exec "$NODE" -- sudo sed -i "s|127.0.0.1:8443|${HOST_IP}:8443|g" /etc/rancher/agent/config.yaml 2>/dev/null || true
    fi
    
    # Restart agent
    multipass exec "$NODE" -- sudo systemctl restart rancher-system-agent 2>/dev/null || true
    echo "  ✓ Fixed and restarted agent on $NODE"
done

echo ""
echo "✓ All nodes fixed. The cluster should start progressing now."
echo "Check Rancher UI to see cluster status."

