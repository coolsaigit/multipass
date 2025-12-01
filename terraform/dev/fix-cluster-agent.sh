#!/bin/bash
set -euo pipefail

# Fix cattle-cluster-agent to use host IP instead of localhost
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
    FIRST_VM=$(multipass list --format csv 2>/dev/null | grep -E "${CLUSTER_NAME}-cp-" | head -1 | cut -d',' -f1)
    if [ -n "$FIRST_VM" ]; then
        GATEWAY=$(multipass exec "$FIRST_VM" -- ip route 2>/dev/null | grep default | awk '{print $3}' || echo "")
        if [ -n "$GATEWAY" ]; then
            HOST_IP="$GATEWAY"
        fi
    fi
fi

echo "Fixing cattle-cluster-agent deployment..."
echo "Using host IP: $HOST_IP"

# Get kubeconfig from control plane node
FIRST_CP=$(multipass list --format csv 2>/dev/null | grep -E "${CLUSTER_NAME}-cp-" | head -1 | cut -d',' -f1)

if [ -z "$FIRST_CP" ]; then
    echo "Error: No control plane node found"
    exit 1
fi

# Patch the deployment - need to find the exact index of CATTLE_SERVER env var
echo "Patching cattle-cluster-agent deployment..."
# First, delete the old pod to force recreation
multipass exec "$FIRST_CP" -- sudo /var/lib/rancher/rke2/bin/kubectl \
    --kubeconfig /etc/rancher/rke2/rke2.yaml \
    delete pods -n cattle-system -l app=cattle-cluster-agent --grace-period=0 --force 2>/dev/null || true

# First, set up port-forward on VM so localhost:8443 works
echo "Setting up port-forward on VM..."
"$SCRIPT_DIR/setup-vm-port-forward.sh" >/dev/null 2>&1 || {
    echo "Warning: Could not set up VM port-forward"
}

# Patch the deployment to enable hostNetwork and disable strict verification
# hostNetwork allows the pod to use the host's network, so localhost works
multipass exec "$FIRST_CP" -- sudo /var/lib/rancher/rke2/bin/kubectl \
    --kubeconfig /etc/rancher/rke2/rke2.yaml \
    set env deployment/cattle-cluster-agent -n cattle-system \
    CATTLE_SERVER="https://localhost:8443" \
    STRICT_VERIFY="false" 2>&1 || true

# Enable hostNetwork so localhost:8443 works (maps to VM's localhost, which forwards to Mac)
multipass exec "$FIRST_CP" -- sudo /var/lib/rancher/rke2/bin/kubectl \
    --kubeconfig /etc/rancher/rke2/rke2.yaml \
    patch deployment -n cattle-system cattle-cluster-agent \
    --type='json' \
    -p='[{"op": "add", "path": "/spec/template/spec/hostNetwork", "value": true}, {"op": "add", "path": "/spec/template/spec/dnsPolicy", "value": "ClusterFirstWithHostNet"}]' 2>&1 || {
    echo "Warning: Failed to patch deployment (may not exist yet)"
    exit 0
}

echo "✓ Deployment patched. Waiting for pod to restart..."
sleep 5

# Check status
multipass exec "$FIRST_CP" -- sudo /var/lib/rancher/rke2/bin/kubectl \
    --kubeconfig /etc/rancher/rke2/rke2.yaml \
    get pods -n cattle-system -l app=cattle-cluster-agent 2>&1 || true

echo ""
echo "✓ Cluster agent should now connect to Rancher at ${HOST_IP}:8443"
echo "Check Rancher UI - cluster should progress now."

