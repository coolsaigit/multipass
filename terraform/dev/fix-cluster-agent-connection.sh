#!/bin/bash
set -euo pipefail

# Comprehensive fix for cattle-cluster-agent connection issue
# This addresses the localhost:8443 hardcoded WebSocket connection problem

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Load config
if [ ! -f cluster.conf ]; then
    echo "Error: cluster.conf not found"
    exit 1
fi

CLUSTER_NAME=$(grep -E "^cluster_name\s*=" cluster.conf | cut -d'"' -f2 || echo "dev-rke2")
RANCHER_URL=$(grep -E "^rancher_api_url\s*=" cluster.conf | cut -d'"' -f2 || echo "https://localhost:8443")
RANCHER_TOKEN=$(grep -E "^rancher_token\s*=" cluster.conf | cut -d'"' -f2 || echo "")

# Get host IP that VMs can reach
HOST_IP="192.168.64.1"
FIRST_CP=$(multipass list --format csv 2>/dev/null | grep -E "${CLUSTER_NAME}-cp-" | head -1 | cut -d',' -f1)

if [ -z "$FIRST_CP" ]; then
    echo "Error: No control plane node found"
    exit 1
fi

GATEWAY=$(multipass exec "$FIRST_CP" -- ip route 2>/dev/null | grep default | awk '{print $3}' || echo "")
if [ -n "$GATEWAY" ]; then
    HOST_IP="$GATEWAY"
fi

echo "Fixing cattle-cluster-agent connection..."
echo "Host IP: $HOST_IP"
echo ""

# Step 1: Install socat and set up port-forward on VM
echo "[1/4] Setting up port-forward on VM (localhost:8443 -> ${HOST_IP}:8443)..."
multipass exec "$FIRST_CP" -- sudo apt-get update -qq >/dev/null 2>&1
multipass exec "$FIRST_CP" -- sudo apt-get install -y -qq socat >/dev/null 2>&1

# Kill any existing socat
multipass exec "$FIRST_CP" -- sudo pkill -f "socat.*8443" 2>/dev/null || true
sleep 1

# Set up port-forward
multipass exec "$FIRST_CP" -- sudo bash -c "nohup socat TCP-LISTEN:8443,fork,reuseaddr TCP:${HOST_IP}:8443 >/tmp/socat-8443.log 2>&1 &" 2>/dev/null
sleep 2

# Verify port-forward works
if multipass exec "$FIRST_CP" -- curl -s -k "https://localhost:8443/ping" 2>/dev/null | grep -q "pong"; then
    echo "✓ Port-forward is working"
else
    echo "⚠ Port-forward may not be working correctly"
fi

# Step 2: Get Rancher CA and create ConfigMap
echo ""
echo "[2/4] Getting Rancher CA certificate..."
RANCHER_CA=$(curl -s -k "${RANCHER_URL}/v3/settings/cacerts" | jq -r '.value // empty' || echo "")
if [ -n "$RANCHER_CA" ]; then
    # Create ConfigMap with CA
    echo "$RANCHER_CA" | multipass exec "$FIRST_CP" -- sudo /var/lib/rancher/rke2/bin/kubectl \
        --kubeconfig /etc/rancher/rke2/rke2.yaml \
        create configmap -n cattle-system rancher-ca \
        --from-file=cacerts.pem=/dev/stdin \
        --dry-run=client -o yaml 2>/dev/null | \
    multipass exec "$FIRST_CP" -- sudo /var/lib/rancher/rke2/bin/kubectl \
        --kubeconfig /etc/rancher/rke2/rke2.yaml \
        apply -f - 2>&1 | grep -v "deprecated" || true
    echo "✓ CA certificate saved"
else
    echo "⚠ Could not retrieve CA certificate"
fi

# Step 3: Patch deployment
echo ""
echo "[3/4] Patching cattle-cluster-agent deployment..."
multipass exec "$FIRST_CP" -- sudo /var/lib/rancher/rke2/bin/kubectl \
    --kubeconfig /etc/rancher/rke2/rke2.yaml \
    set env deployment/cattle-cluster-agent -n cattle-system \
    CATTLE_SERVER="https://localhost:8443" \
    STRICT_VERIFY="false" 2>&1 | grep -v "deprecated" || true

# Enable hostNetwork
multipass exec "$FIRST_CP" -- sudo /var/lib/rancher/rke2/bin/kubectl \
    --kubeconfig /etc/rancher/rke2/rke2.yaml \
    patch deployment -n cattle-system cattle-cluster-agent \
    --type='json' \
    -p='[{"op": "add", "path": "/spec/template/spec/hostNetwork", "value": true}, {"op": "add", "path": "/spec/template/spec/dnsPolicy", "value": "ClusterFirstWithHostNet"}]' 2>&1 | grep -v "deprecated" || true

echo "✓ Deployment patched"

# Step 4: Restart pods
echo ""
echo "[4/4] Restarting agent pods..."
multipass exec "$FIRST_CP" -- sudo /var/lib/rancher/rke2/bin/kubectl \
    --kubeconfig /etc/rancher/rke2/rke2.yaml \
    delete pods -n cattle-system -l app=cattle-cluster-agent \
    --grace-period=0 --force 2>&1 | grep -v "deprecated" || true

echo "✓ Pods restarted"
echo ""
echo "Waiting for agent to connect..."
sleep 15

# Check status
multipass exec "$FIRST_CP" -- sudo /var/lib/rancher/rke2/bin/kubectl \
    --kubeconfig /etc/rancher/rke2/rke2.yaml \
    get pods -n cattle-system -l app=cattle-cluster-agent 2>&1

echo ""
echo "Check Rancher UI - the cluster should progress now."
echo "If still stuck, the cluster is functional - you can use kubectl directly:"
echo "  export KUBECONFIG=~/.kube/dev-rke2-config"
echo "  kubectl get nodes"

