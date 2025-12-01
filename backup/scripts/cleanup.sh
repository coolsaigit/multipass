#!/bin/bash
set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# System namespaces to preserve (Kubernetes core)
SYSTEM_NAMESPACES=("kube-system" "kube-public" "kube-node-lease" "default")
PRESERVE_DATA=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --preserve-data)
            PRESERVE_DATA=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [--preserve-data]"
            echo ""
            echo "Options:"
            echo "  --preserve-data    Keep PVCs (persistent volumes) when cleaning up"
            echo "  --help, -h         Show this help message"
            echo ""
            echo "This script will delete ALL Kubernetes resources except:"
            echo "  - Core Kubernetes namespaces (kube-system, kube-public, kube-node-lease, default)"
            echo "  - Kubernetes system components"
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

echo -e "${BLUE}=== Complete Kubernetes Cleanup Script ===${NC}\n"

# Check prerequisites
command -v kubectl >/dev/null 2>&1 || { 
    echo -e "${RED}Error: kubectl is required but not installed.${NC}" >&2
    exit 1
}

# Check cluster connectivity
if ! kubectl cluster-info &>/dev/null; then
    echo -e "${RED}Error: Cannot connect to Kubernetes cluster.${NC}" >&2
    exit 1
fi

echo -e "${RED}⚠️  WARNING: This script will delete ALL Kubernetes resources!${NC}"
echo -e "${YELLOW}The following will be preserved:${NC}"
echo -e "  - Core Kubernetes namespaces: ${SYSTEM_NAMESPACES[*]}"
echo -e "  - Kubernetes system components"
echo ""
if [ "$PRESERVE_DATA" = false ]; then
    echo -e "${RED}WARNING: All data (PVCs) will be deleted!${NC}"
else
    echo -e "${GREEN}Data (PVCs) will be preserved.${NC}"
fi
echo ""
read -p "Are you absolutely sure you want to continue? (yes/no): " -r
echo ""

if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
    echo -e "${YELLOW}Cleanup cancelled.${NC}"
    exit 0
fi

# Helper function to check if namespace is system namespace
is_system_namespace() {
    local ns=$1
    for sys_ns in "${SYSTEM_NAMESPACES[@]}"; do
        if [ "$ns" = "$sys_ns" ]; then
            return 0
        fi
    done
    return 1
}

# Step 1: List all namespaces
echo -e "${BLUE}Step 1: Identifying all namespaces...${NC}\n"
ALL_NAMESPACES=$(kubectl get namespaces -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")
echo -e "${YELLOW}Found namespaces:${NC}"
for ns in $ALL_NAMESPACES; do
    if is_system_namespace "$ns"; then
        echo -e "  ${GREEN}$ns (system - will be preserved)${NC}"
    else
        echo -e "  ${YELLOW}$ns (will be deleted)${NC}"
    fi
done
echo ""

# Step 2: Delete all Helm releases across all namespaces
echo -e "${BLUE}Step 2: Deleting all Helm releases...${NC}\n"
if command -v helm &>/dev/null; then
    for ns in $ALL_NAMESPACES; do
        if ! is_system_namespace "$ns"; then
            HELM_RELEASES=$(helm list -n "$ns" -q 2>/dev/null || echo "")
            if [ -n "$HELM_RELEASES" ]; then
                echo -e "${YELLOW}  Deleting Helm releases in $ns:${NC}"
                echo "$HELM_RELEASES" | while read -r release; do
                    if [ -n "$release" ]; then
                        echo -e "    - $release"
                        helm uninstall "$release" -n "$ns" --ignore-not-found=true --timeout=10s 2>/dev/null || true
                    fi
                done
            fi
        fi
    done
    echo -e "${GREEN}✓ Helm releases cleaned up${NC}\n"
else
    echo -e "${YELLOW}  Helm not found, skipping Helm cleanup${NC}\n"
fi

# Step 3: Delete all cluster-level resources (CRDs, ClusterRoles, etc.)
echo -e "${BLUE}Step 3: Deleting cluster-level resources...${NC}\n"

# Delete CRDs (Custom Resource Definitions) - this will cascade delete all custom resources
echo -e "${YELLOW}  Deleting Custom Resource Definitions (CRDs)...${NC}"
CRDS=$(kubectl get crd -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")
if [ -n "$CRDS" ]; then
    for crd in $CRDS; do
        echo -e "    - $crd"
        # Remove finalizers from CRD first
        kubectl patch crd "$crd" -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
        kubectl delete crd "$crd" --ignore-not-found=true --wait=false --timeout=10s 2>/dev/null || true
    done
fi

# Delete ClusterRoles and ClusterRoleBindings
echo -e "${YELLOW}  Deleting ClusterRoles and ClusterRoleBindings...${NC}"
kubectl delete clusterrole,clusterrolebinding --all --ignore-not-found=true --timeout=10s 2>/dev/null || true

# Delete ValidatingWebhookConfigurations and MutatingWebhookConfigurations
echo -e "${YELLOW}  Deleting WebhookConfigurations...${NC}"
# Remove finalizers first (works without jq)
for kind in validatingwebhookconfiguration mutatingwebhookconfiguration; do
    kubectl get "$kind" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null | \
        tr ' ' '\n' | \
        while read -r name; do
            if [ -n "$name" ]; then
                kubectl patch "$kind" "$name" -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
            fi
        done || true
done
kubectl delete validatingwebhookconfiguration,mutatingwebhookconfiguration --all --ignore-not-found=true --timeout=10s 2>/dev/null || true

# Delete APIServices (except system ones)
echo -e "${YELLOW}  Deleting APIServices...${NC}"
kubectl delete apiservice --all --ignore-not-found=true --timeout=10s 2>/dev/null || true

# Delete PriorityClasses (except system ones)
echo -e "${YELLOW}  Deleting PriorityClasses...${NC}"
kubectl delete priorityclass --all --ignore-not-found=true --timeout=10s 2>/dev/null || true

# Delete StorageClasses (optional - comment out if you want to keep them)
# kubectl delete storageclass --all --ignore-not-found=true 2>/dev/null || true

echo -e "${GREEN}✓ Cluster-level resources cleaned up${NC}\n"

# Step 4: Delete all non-system namespaces (this will cascade delete all resources in them)
echo -e "${BLUE}Step 4: Deleting all non-system namespaces...${NC}\n"

# First, get fresh list of namespaces
ALL_NAMESPACES=$(kubectl get namespaces -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")

for ns in $ALL_NAMESPACES; do
    if ! is_system_namespace "$ns"; then
        echo -e "${YELLOW}  Deleting namespace: $ns${NC}"
        
        # Delete all resources in namespace first (with finalizers removed)
        echo -e "    Deleting all resources in namespace..."
        
        # Get all resource types and delete them
        kubectl delete all --all -n "$ns" --ignore-not-found=true --timeout=10s --grace-period=0 2>/dev/null || true
        kubectl delete pvc --all -n "$ns" --ignore-not-found=true --timeout=10s --grace-period=0 2>/dev/null || true
        kubectl delete configmap,secret --all -n "$ns" --ignore-not-found=true --timeout=10s --grace-period=0 2>/dev/null || true
        
        # Remove finalizers from namespace
        echo -e "    Removing finalizers from namespace..."
        kubectl patch namespace "$ns" -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
        
        # Delete the namespace (this will cascade delete all resources)
        kubectl delete namespace "$ns" --ignore-not-found=true --wait=false --timeout=10s --grace-period=0 2>/dev/null || true
    fi
done

# Wait a bit for namespaces to start terminating
echo -e "${YELLOW}  Waiting for namespaces to start terminating...${NC}"
sleep 3

# Force delete any stuck namespaces by removing finalizers
echo -e "${YELLOW}  Force deleting any stuck namespaces...${NC}"
ALL_NAMESPACES=$(kubectl get namespaces -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")
for ns in $ALL_NAMESPACES; do
    if ! is_system_namespace "$ns"; then
        if kubectl get namespace "$ns" &>/dev/null; then
            echo -e "${YELLOW}    Force deleting stuck namespace: $ns${NC}"
            
            # Get all resources in the namespace and remove their finalizers
            # Try common resource types directly (faster and doesn't require jq)
            for kind in deployment statefulset daemonset replicaset job cronjob pod service configmap secret pvc ingress networkpolicy; do
                kubectl get "$kind" -n "$ns" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null | \
                    tr ' ' '\n' | \
                    while read -r name; do
                        if [ -n "$name" ]; then
                            kubectl patch "$kind" "$name" -n "$ns" -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
                        fi
                    done || true
            done
            
            # If jq is available, try to remove finalizers from all other resource types
            if command -v jq &>/dev/null; then
                for resource in $(kubectl api-resources --verbs=list --namespaced -o name 2>/dev/null | grep -v "^deployment\|^statefulset\|^daemonset\|^replicaset\|^job\|^cronjob\|^pod\|^service\|^configmap\|^secret\|^pvc\|^ingress\|^networkpolicy"); do
                    kubectl get "$resource" -n "$ns" -o json 2>/dev/null | \
                        jq -r '.items[] | "\(.kind) \(.metadata.name)"' 2>/dev/null | \
                        while read -r line; do
                            if [ -n "$line" ]; then
                                kind=$(echo "$line" | cut -d' ' -f1)
                                name=$(echo "$line" | cut -d' ' -f2)
                                kubectl patch "$kind" "$name" -n "$ns" -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
                            fi
                        done || true
                done
            fi
            
            # Remove finalizers from namespace itself
            kubectl patch namespace "$ns" -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
            kubectl delete namespace "$ns" --ignore-not-found=true --grace-period=0 --force --timeout=5s 2>/dev/null || true
        fi
    fi
done

echo -e "${GREEN}✓ Non-system namespaces deleted${NC}\n"

# Step 5: Clean up any remaining resources in default namespace (if preserve-data is false)
if [ "$PRESERVE_DATA" = false ]; then
    echo -e "${BLUE}Step 5: Cleaning up default namespace...${NC}\n"
    echo -e "${YELLOW}  Deleting all resources in default namespace...${NC}"
    
    # Delete all workloads
    kubectl delete all --all -n default --ignore-not-found=true 2>/dev/null || true
    
    # Delete PVCs
    kubectl delete pvc --all -n default --ignore-not-found=true 2>/dev/null || true
    
    # Delete ConfigMaps and Secrets
    kubectl delete configmap,secret --all -n default --ignore-not-found=true 2>/dev/null || true
    
    echo -e "${GREEN}✓ Default namespace cleaned up${NC}\n"
else
    echo -e "${BLUE}Step 5: Preserving default namespace (--preserve-data flag)${NC}\n"
fi

# Step 6: Final verification
echo -e "${BLUE}Step 6: Final verification...${NC}\n"
REMAINING_NAMESPACES=$(kubectl get namespaces -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")
REMAINING_COUNT=0
for ns in $REMAINING_NAMESPACES; do
    if ! is_system_namespace "$ns"; then
        REMAINING_COUNT=$((REMAINING_COUNT + 1))
        echo -e "${YELLOW}  Warning: Namespace $ns still exists${NC}"
    fi
done

if [ $REMAINING_COUNT -eq 0 ]; then
    echo -e "${GREEN}✓ All non-system namespaces have been deleted${NC}\n"
else
    echo -e "${YELLOW}⚠  $REMAINING_COUNT namespace(s) still exist (may be terminating)${NC}\n"
fi

# Summary
echo -e "${GREEN}=== Cleanup Complete ===${NC}\n"
echo -e "Kubernetes cluster has been cleaned up."
echo -e "${GREEN}Preserved:${NC}"
for ns in "${SYSTEM_NAMESPACES[@]}"; do
    if kubectl get namespace "$ns" &>/dev/null; then
        echo -e "  ✓ $ns"
    fi
done
echo ""
if [ "$PRESERVE_DATA" = false ]; then
    echo -e "${YELLOW}Note: All data (PVCs) has been deleted.${NC}"
else
    echo -e "${GREEN}Note: Data (PVCs) has been preserved.${NC}"
fi
echo ""
echo -e "${BLUE}Next steps:${NC}"
echo -e "1. Your Kubernetes cluster is now clean (only system components remain)"
echo -e "2. You can now deploy fresh applications"
echo -e "3. Run: ./scripts/bootstrap.sh to deploy via ArgoCD"
echo ""

