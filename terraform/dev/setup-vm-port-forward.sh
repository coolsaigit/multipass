#!/bin/bash
set -euo pipefail

# Set up port-forward on VM to forward localhost:8443 to Mac host
# This allows cattle-cluster-agent to connect via localhost

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

echo "Setting up port-forward on control plane node..."
echo "Forwarding localhost:8443 -> ${HOST_IP}:8443"

FIRST_CP=$(multipass list --format csv 2>/dev/null | grep -E "${CLUSTER_NAME}-cp-" | head -1 | cut -d',' -f1)

if [ -z "$FIRST_CP" ]; then
    echo "Error: No control plane node found"
    exit 1
fi

# Install socat if not present
multipass exec "$FIRST_CP" -- sudo apt-get update -qq >/dev/null 2>&1
multipass exec "$FIRST_CP" -- sudo apt-get install -y -qq socat >/dev/null 2>&1

# Kill any existing socat process on port 8443
multipass exec "$FIRST_CP" -- sudo pkill -f "socat.*8443" 2>/dev/null || true
sleep 1

# Set up port-forward
multipass exec "$FIRST_CP" -- sudo bash -c "nohup socat TCP-LISTEN:8443,fork,reuseaddr TCP:${HOST_IP}:8443 >/tmp/socat-8443.log 2>&1 &" 2>/dev/null

sleep 2

# Verify it works
if multipass exec "$FIRST_CP" -- curl -s -k "https://localhost:8443/ping" 2>/dev/null | grep -q "pong"; then
    echo "✓ Port-forward is working"
else
    echo "⚠ Port-forward may not be working correctly"
fi

echo ""
echo "Port-forward is running in background on $FIRST_CP"
echo "This allows cattle-cluster-agent to connect via localhost:8443"

