#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Set kubeconfig
export KUBECONFIG="$SCRIPT_DIR/_out/kubeconfig"

# Rancher configuration
RANCHER_HOSTNAME="${RANCHER_HOSTNAME:-rancher.localhost}"
RANCHER_PASSWORD="${RANCHER_PASSWORD:-admin}"
CERT_MANAGER_VERSION="v1.16.2"

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

print_section() {
    echo -e "\n${BLUE}===================================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}===================================================${NC}\n"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_info() {
    echo -e "${YELLOW}→ $1${NC}"
}

check_prerequisites() {
    print_section "Checking Prerequisites"
    
    # Check if kubectl is available
    if ! command -v kubectl &> /dev/null; then
        print_error "kubectl not found. Please install kubectl first."
        exit 1
    fi
    print_success "kubectl found"
    
    # Check if helm is available
    if ! command -v helm &> /dev/null; then
        print_error "helm not found. Please install helm first."
        echo "Install with: brew install helm"
        exit 1
    fi
    print_success "helm found"
    
    # Check if cluster is accessible
    if ! kubectl get nodes &> /dev/null; then
        print_error "Cannot connect to Kubernetes cluster"
        echo "Please ensure your Talos cluster is running: ./talos-cluster.sh status"
        exit 1
    fi
    print_success "Kubernetes cluster is accessible"
    
    # Show cluster nodes
    echo ""
    kubectl get nodes
}

install_cert_manager() {
    print_section "Installing cert-manager (Required for Rancher)"
    
    # Check if cert-manager is already installed
    if kubectl get namespace cert-manager &> /dev/null; then
        print_info "cert-manager namespace already exists, skipping installation"
        return 0
    fi
    
    print_info "Applying cert-manager manifests..."
    kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/${CERT_MANAGER_VERSION}/cert-manager.yaml
    
    print_info "Adding control-plane tolerations (required for control-plane-only clusters)..."
    kubectl patch deployment cert-manager -n cert-manager --type='json' -p='[{"op": "add", "path": "/spec/template/spec/tolerations", "value": [{"key": "node-role.kubernetes.io/control-plane", "operator": "Exists", "effect": "NoSchedule"}]}]' 2>/dev/null || true
    kubectl patch deployment cert-manager-cainjector -n cert-manager --type='json' -p='[{"op": "add", "path": "/spec/template/spec/tolerations", "value": [{"key": "node-role.kubernetes.io/control-plane", "operator": "Exists", "effect": "NoSchedule"}]}]' 2>/dev/null || true
    kubectl patch deployment cert-manager-webhook -n cert-manager --type='json' -p='[{"op": "add", "path": "/spec/template/spec/tolerations", "value": [{"key": "node-role.kubernetes.io/control-plane", "operator": "Exists", "effect": "NoSchedule"}]}]' 2>/dev/null || true
    
    print_info "Waiting for cert-manager to be ready (this may take 2-3 minutes)..."
    kubectl wait --for=condition=Available --timeout=300s -n cert-manager deployment/cert-manager
    kubectl wait --for=condition=Available --timeout=300s -n cert-manager deployment/cert-manager-webhook
    kubectl wait --for=condition=Available --timeout=300s -n cert-manager deployment/cert-manager-cainjector
    
    print_success "cert-manager is ready"
    echo ""
    kubectl get pods -n cert-manager
}

install_rancher() {
    print_section "Installing Rancher Manager (3 Replicas)"
    
    # Check if Rancher is already installed
    if helm list -n cattle-system 2>/dev/null | grep -q rancher; then
        print_info "Rancher is already installed"
        kubectl get pods -n cattle-system
        return 0
    fi
    
    print_info "Adding Rancher Helm repository..."
    helm repo add rancher-latest https://releases.rancher.com/server-charts/latest
    helm repo update
    
    print_info "Creating cattle-system namespace..."
    kubectl create namespace cattle-system --dry-run=client -o yaml | kubectl apply -f -
    
    print_info "Installing Rancher with Helm..."
    print_info "Hostname: $RANCHER_HOSTNAME"
    print_info "Bootstrap Password: $RANCHER_PASSWORD"
    print_info "Replicas: 3"
    
    # Create temporary values file with tolerations
    TMP_VALUES=$(mktemp)
    cat > "$TMP_VALUES" <<EOF
hostname: $RANCHER_HOSTNAME
replicas: 3
bootstrapPassword: $RANCHER_PASSWORD
global:
  cattle:
    psp:
      enabled: false
tolerations:
  - key: node-role.kubernetes.io/control-plane
    operator: Exists
    effect: NoSchedule
EOF
    
    helm upgrade --install rancher rancher-latest/rancher \
        --namespace cattle-system \
        -f "$TMP_VALUES" \
        --timeout=10m
    
    rm -f "$TMP_VALUES"
    
    print_info "Adding control-plane tolerations to Rancher deployment..."
    # The Helm chart doesn't apply tolerations correctly, so patch the deployment
    kubectl patch deployment rancher -n cattle-system --type='json' \
        -p='[{"op": "add", "path": "/spec/template/spec/tolerations", "value": [{"key": "node-role.kubernetes.io/control-plane", "operator": "Exists", "effect": "NoSchedule"}]}]' \
        2>/dev/null || print_info "Tolerations already exist"
    
    print_success "Rancher installation completed"
}

wait_for_rancher() {
    print_section "Waiting for Rancher to be Ready"
    
    print_info "Waiting for Rancher pods to be ready (this may take 2-3 minutes)..."
    kubectl wait --for=condition=Ready --timeout=300s -n cattle-system pod -l app=rancher 2>/dev/null || true
    kubectl -n cattle-system rollout status deploy/rancher --timeout=5m
    
    print_success "Rancher is ready"
    echo ""
    kubectl get pods -n cattle-system -l app=rancher
    
    print_info "Patching Fleet and additional Rancher components for control-plane nodes..."
    # Wait a bit for all Rancher components to be created
    sleep 10
    
    # Patch all Fleet and Rancher webhook deployments
    for ns in cattle-fleet-system cattle-fleet-local-system cattle-provisioning-capi-system; do
        for deploy in $(kubectl get deploy -n $ns -o name 2>/dev/null | cut -d/ -f2); do
            kubectl patch deployment $deploy -n $ns --type='json' \
                -p='[{"op": "add", "path": "/spec/template/spec/tolerations", "value": [{"key": "node-role.kubernetes.io/control-plane", "operator": "Exists", "effect": "NoSchedule"}]}]' \
                2>/dev/null && print_info "  ✓ Patched $ns/$deploy" || true
        done
    done
    
    # Patch rancher-webhook in cattle-system
    kubectl patch deployment rancher-webhook -n cattle-system --type='json' \
        -p='[{"op": "add", "path": "/spec/template/spec/tolerations", "value": [{"key": "node-role.kubernetes.io/control-plane", "operator": "Exists", "effect": "NoSchedule"}]}]' \
        2>/dev/null && print_info "  ✓ Patched cattle-system/rancher-webhook" || true
    
    print_info "Cleaning up old replicasets..."
    # Scale down old replicasets to prevent pending pods
    for ns in cattle-fleet-system cattle-fleet-local-system cattle-system; do
        for rs in $(kubectl get rs -n $ns -o name 2>/dev/null); do
            REPLICAS=$(kubectl get $rs -n $ns -o jsonpath='{.status.replicas}' 2>/dev/null || echo "0")
            READY=$(kubectl get $rs -n $ns -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
            if [ "$REPLICAS" != "0" ] && [ "$READY" == "0" ]; then
                kubectl scale $rs -n $ns --replicas=0 2>/dev/null || true
            fi
        done
    done
    
    print_success "All Rancher components patched"
}

start_port_forward() {
    # Check if port-forward is already running
    if ps aux | grep -q "[k]ubectl.*port-forward.*rancher.*8443:443"; then
        print_info "Port-forward is already running"
        return 0
    fi
    
    print_info "Starting port-forward to Rancher (running in background)..."
    
    # Start port-forward in background and detach it
    nohup kubectl -n cattle-system port-forward svc/rancher 8443:443 > /dev/null 2>&1 &
    local pf_pid=$!
    
    # Wait a moment to check if it started successfully
    sleep 2
    
    if ps -p $pf_pid > /dev/null 2>&1; then
        print_success "Port-forward started and running in background"
        return 0
    else
        print_error "Failed to start port-forward"
        return 1
    fi
}

show_access_info() {
    print_section "Rancher Access Information"
    
    echo -e "${GREEN}Rancher Manager has been successfully installed!${NC}\n"
    
    echo -e "${YELLOW}To access Rancher UI:${NC}"
    echo -e "  1. Open in browser:"
    echo -e "     ${BLUE}https://localhost:8443${NC}"
    echo ""
    echo -e "  2. Login credentials:"
    echo -e "     Username: ${BLUE}admin${NC}"
    echo -e "     Password: ${BLUE}$RANCHER_PASSWORD${NC}"
    echo ""
    echo -e "  3. Security warning:"
    echo -e "     Click 'Advanced' → 'Proceed to localhost (unsafe)'"
    echo -e "     (This is normal for self-signed certificates)"
    echo ""
    
    echo -e "${YELLOW}Cluster Status:${NC}"
    kubectl get nodes -o wide
    echo ""
    
    echo -e "${YELLOW}Memory Usage:${NC}"
    docker stats --no-stream $(docker ps -q --filter "name=talos-cluster") --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}"
    echo ""
    
    echo -e "${YELLOW}Rancher Pods:${NC}"
    kubectl get pods -n cattle-system
    echo ""
    
    echo -e "${GREEN}Next Steps:${NC}"
    echo "  • Use Rancher to create and manage additional Kubernetes clusters"
    echo "  • Import existing clusters into Rancher"
    echo "  • Deploy applications through Rancher's catalog"
    echo ""
}

# Main execution
main() {
    local start_time=$(date +%s)
    
    echo -e "${GREEN}"
    echo "╔═══════════════════════════════════════════════════════════╗"
    echo "║       Rancher Manager Installation for Talos Cluster     ║"
    echo "╚═══════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    
    check_prerequisites
    install_cert_manager
    install_rancher
    wait_for_rancher
    show_access_info
    
    # Automatically start port-forward
    start_port_forward
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    local formatted_duration=$(format_duration $duration)
    
    print_success "Installation complete!"
    echo -e "${BLUE}⏱️  Time taken: ${formatted_duration}${NC}"
    echo ""
    echo -e "${GREEN}✓ Rancher is now accessible at: https://localhost:8443${NC}"
    echo ""
}

# Run main function
main

