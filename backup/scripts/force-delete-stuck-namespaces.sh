#!/bin/bash
# Force delete stuck namespaces in Terminating state
# Usage: ./scripts/force-delete-stuck-namespaces.sh

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}Force deleting stuck namespaces...${NC}\n"

# Get stuck namespaces
STUCK_NAMESPACES=$(kubectl get namespaces -o json 2>/dev/null | \
    grep -A 5 '"phase":' | \
    grep -B 5 '"Terminating"' | \
    grep '"name":' | \
    sed 's/.*"name": "\([^"]*\)".*/\1/' | \
    tr '\n' ' ' || echo "")

if [ -z "$STUCK_NAMESPACES" ]; then
    # Try alternative method
    STUCK_NAMESPACES=$(kubectl get namespaces --field-selector status.phase=Terminating -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")
fi

if [ -z "$STUCK_NAMESPACES" ]; then
    echo -e "${GREEN}No stuck namespaces found.${NC}"
    exit 0
fi

echo -e "${YELLOW}Found stuck namespaces:${NC}"
for ns in $STUCK_NAMESPACES; do
    echo -e "  - $ns"
done
echo ""

for ns in $STUCK_NAMESPACES; do
    echo -e "${YELLOW}Force deleting namespace: $ns${NC}"
    
    # Method 1: Remove finalizers from namespace directly
    echo -e "  Removing finalizers from namespace..."
    kubectl get namespace "$ns" -o json 2>/dev/null | \
        sed 's/"finalizers": \[[^]]*\]/"finalizers": []/' | \
        kubectl replace --raw "/api/v1/namespaces/$ns/finalize" -f - 2>/dev/null || true
    
    # Method 2: Patch namespace to remove finalizers
    kubectl patch namespace "$ns" -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
    
    # Method 3: Try to delete resources in namespace and remove their finalizers
    echo -e "  Removing finalizers from resources in namespace..."
    for kind in deployment statefulset daemonset replicaset job cronjob pod service configmap secret pvc ingress networkpolicy; do
        kubectl get "$kind" -n "$ns" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null | \
            tr ' ' '\n' | \
            while read -r name; do
                if [ -n "$name" ]; then
                    kubectl patch "$kind" "$name" -n "$ns" -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
                fi
            done || true
    done
    
    # Method 4: Final attempt - direct API call
    echo -e "  Final attempt via API..."
    kubectl get namespace "$ns" -o json 2>/dev/null | \
        jq 'del(.spec.finalizers)' 2>/dev/null | \
        kubectl replace --raw "/api/v1/namespaces/$ns/finalize" -f - 2>/dev/null || \
    kubectl get namespace "$ns" -o json 2>/dev/null | \
        sed 's/"finalizers": \[[^]]*\]/"finalizers": []/' | \
        kubectl replace --raw "/api/v1/namespaces/$ns/finalize" -f - 2>/dev/null || true
    
    sleep 1
done

echo ""
echo -e "${GREEN}Done! Checking remaining namespaces...${NC}"
kubectl get namespaces | grep -E "NAME|Terminating" || echo -e "${GREEN}All namespaces cleaned up!${NC}"

