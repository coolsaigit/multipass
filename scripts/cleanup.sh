#!/bin/bash
set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
NAMESPACES=("minio" "redpanda" "flink" "starrocks" "iceberg" "monitoring" "istio-system")
ARGOCD_NAMESPACE="argocd"
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
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

echo -e "${BLUE}=== Multipass Cleanup Script ===${NC}\n"

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

echo -e "${YELLOW}This script will clean up existing deployments.${NC}"
if [ "$PRESERVE_DATA" = false ]; then
    echo -e "${RED}WARNING: This will delete all data (PVCs will be removed)!${NC}"
else
    echo -e "${GREEN}Data will be preserved (PVCs will be kept).${NC}"
fi
echo ""
read -p "Are you sure you want to continue? (yes/no): " -r
echo ""

if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
    echo -e "${YELLOW}Cleanup cancelled.${NC}"
    exit 0
fi

# Step 1: List what's currently running
echo -e "${BLUE}Step 1: Identifying existing deployments...${NC}\n"
for ns in "${NAMESPACES[@]}"; do
    if kubectl get namespace "$ns" &>/dev/null; then
        echo -e "${YELLOW}Namespace: $ns${NC}"
        kubectl get all,pvc -n "$ns" 2>/dev/null | grep -v "^NAME" | head -10 || echo "  (empty)"
        echo ""
    fi
done

# Step 2: Clean up application namespaces
echo -e "${BLUE}Step 2: Cleaning up application namespaces...${NC}\n"
for ns in "${NAMESPACES[@]}"; do
    if kubectl get namespace "$ns" &>/dev/null; then
        echo -e "${YELLOW}Cleaning up namespace: $ns${NC}"
        
        # Delete StatefulSets first (they manage PVCs and need special handling)
        echo -e "  Deleting StatefulSets in $ns..."
        kubectl delete statefulset --all -n "$ns" --ignore-not-found=true --cascade=orphan
        
        # Delete Deployments and other workloads
        echo -e "  Deleting Deployments and workloads in $ns..."
        kubectl delete deployment,daemonset,replicaset --all -n "$ns" --ignore-not-found=true
        
        # Delete Services
        echo -e "  Deleting Services in $ns..."
        kubectl delete svc --all -n "$ns" --ignore-not-found=true
        
        # Delete Pods (in case any are orphaned)
        kubectl delete pods --all -n "$ns" --ignore-not-found=true --grace-period=0 --force 2>/dev/null || true
        
        # Handle PVCs based on preserve-data flag
        if [ "$PRESERVE_DATA" = false ]; then
            echo -e "  Deleting PVCs in $ns..."
            kubectl delete pvc --all -n "$ns" --ignore-not-found=true
        else
            echo -e "  Preserving PVCs in $ns..."
        fi
        
        # Delete ConfigMaps, Secrets, and other resources
        echo -e "  Deleting ConfigMaps, Secrets, and other resources in $ns..."
        kubectl delete configmap,secret,ingress,networkpolicy --all -n "$ns" --ignore-not-found=true
        
        # Delete Istio resources if in istio-system namespace
        if [ "$ns" = "istio-system" ]; then
            echo -e "  Deleting Istio resources in $ns..."
            kubectl delete gateway,virtualservice,destinationrule,serviceentry --all -n "$ns" --ignore-not-found=true || true
        fi
        
        # Finally delete the namespace (skip for istio-system and argocd - handled separately)
        if [ "$ns" != "istio-system" ] && [ "$ns" != "$ARGOCD_NAMESPACE" ]; then
            echo -e "  Deleting namespace: $ns..."
            kubectl delete namespace "$ns" --ignore-not-found=true
        fi
        
        echo -e "${GREEN}✓ Cleaned up $ns${NC}\n"
    else
        echo -e "${GREEN}✓ Namespace $ns does not exist (already clean)${NC}\n"
    fi
done

# Step 3: Clean up Istio (optional)
echo -e "${BLUE}Step 3: Checking Istio...${NC}\n"
if kubectl get namespace "istio-system" &>/dev/null; then
    echo -e "${YELLOW}Istio namespace found.${NC}"
    read -p "Do you want to remove Istio? (yes/no): " -r
    echo ""
    
    if [[ $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        echo -e "${YELLOW}Removing Istio...${NC}"
        
        # Delete Istio resources
        kubectl delete gateway,virtualservice,destinationrule,serviceentry --all -n "istio-system" --ignore-not-found=true || true
        kubectl delete all --all -n "istio-system" --ignore-not-found=true
        
        # Delete namespace
        kubectl delete namespace "istio-system" --ignore-not-found=true
        echo -e "${GREEN}✓ Istio removed${NC}\n"
    else
        echo -e "${YELLOW}Keeping Istio.${NC}\n"
    fi
else
    echo -e "${GREEN}✓ Istio not installed${NC}\n"
fi

# Step 4: Clean up ArgoCD (optional)
echo -e "${BLUE}Step 4: Checking ArgoCD...${NC}\n"
if kubectl get namespace "$ARGOCD_NAMESPACE" &>/dev/null; then
    echo -e "${YELLOW}ArgoCD namespace found.${NC}"
    read -p "Do you want to remove ArgoCD? (yes/no): " -r
    echo ""
    
    if [[ $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        echo -e "${YELLOW}Removing ArgoCD...${NC}"
        
        # Delete ArgoCD Applications and ApplicationSets first
        kubectl delete application,applicationset --all -n "$ARGOCD_NAMESPACE" --ignore-not-found=true || true
        
        # Check if installed via Helm
        if helm list -n "$ARGOCD_NAMESPACE" 2>/dev/null | grep -q "argocd"; then
            echo -e "  Uninstalling ArgoCD Helm release..."
            helm uninstall argocd -n "$ARGOCD_NAMESPACE" --ignore-not-found=true
        fi
        
        # Delete namespace (this will delete everything)
        kubectl delete namespace "$ARGOCD_NAMESPACE" --ignore-not-found=true
        echo -e "${GREEN}✓ ArgoCD removed${NC}\n"
    else
        echo -e "${YELLOW}Keeping ArgoCD. You can use existing ArgoCD for GitOps.${NC}\n"
    fi
else
    echo -e "${GREEN}✓ ArgoCD not installed${NC}\n"
fi

# Step 5: Clean up any Helm releases
echo -e "${BLUE}Step 5: Checking for Helm releases...${NC}\n"
for ns in "${NAMESPACES[@]}"; do
    if helm list -n "$ns" 2>/dev/null | grep -v "^NAME"; then
        echo -e "${YELLOW}Found Helm releases in $ns:${NC}"
        helm list -n "$ns"
        read -p "Delete Helm releases in $ns? (yes/no): " -r
        echo ""
        if [[ $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
            helm list -n "$ns" -q | xargs -r helm uninstall -n "$ns" || true
            echo -e "${GREEN}✓ Helm releases removed from $ns${NC}\n"
        fi
    fi
done

# Summary
echo -e "${GREEN}=== Cleanup Complete ===${NC}\n"
echo -e "All application namespaces have been cleaned up."
if [ "$PRESERVE_DATA" = false ]; then
    echo -e "${YELLOW}Note: All data (PVCs) has been deleted.${NC}"
else
    echo -e "${GREEN}Note: Data (PVCs) has been preserved.${NC}"
fi
echo ""
echo -e "${BLUE}Next steps:${NC}"
echo -e "1. Update repoURL in gitops/argo/apps/*.yaml files"
echo -e "2. Run: ./scripts/bootstrap.sh"
echo -e "3. Monitor deployment in ArgoCD UI"
echo ""

