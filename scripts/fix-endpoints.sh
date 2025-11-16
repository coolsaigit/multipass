#!/bin/bash

# Script to fix and test all endpoints

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}=== Fixing and Testing Endpoints ===${NC}\n"

# Step 1: Apply Gateway if missing
echo -e "${YELLOW}Step 1: Checking Istio Gateway...${NC}"
if ! kubectl get gateway multipass-gateway -n istio-system &>/dev/null; then
    echo -e "${YELLOW}Gateway missing. Applying...${NC}"
    kubectl apply -f gitops/istio/gateway.yaml
    echo -e "${GREEN}✓ Gateway applied${NC}\n"
else
    echo -e "${GREEN}✓ Gateway exists${NC}\n"
fi

# Step 2: Apply all VirtualServices
echo -e "${YELLOW}Step 2: Applying VirtualServices...${NC}"
kubectl apply -f gitops/istio/virtualservices/
echo -e "${GREEN}✓ VirtualServices applied${NC}\n"

# Step 3: Apply ArgoCD ConfigMap
echo -e "${YELLOW}Step 3: Configuring ArgoCD for insecure mode...${NC}"
kubectl apply -f gitops/istio/argocd-config/configmap.yaml
kubectl rollout restart deployment argocd-server -n argocd 2>/dev/null || echo -e "${YELLOW}  ArgoCD server not ready yet${NC}"
echo -e "${GREEN}✓ ArgoCD configured${NC}\n"

# Step 4: Stop existing port-forwards and start new one
echo -e "${YELLOW}Step 4: Setting up port-forward to Istio Gateway...${NC}"
pkill -f "kubectl port-forward.*istio-ingressgateway" 2>/dev/null
sleep 2
kubectl port-forward svc/istio-ingressgateway -n istio-system 8080:80 > /dev/null 2>&1 &
PF_PID=$!
echo -e "${GREEN}✓ Port-forward started (PID: ${PF_PID})${NC}\n"

# Wait for port-forward to be ready
echo -e "${YELLOW}Waiting for port-forward to be ready...${NC}"
for i in {1..10}; do
    if curl -s -o /dev/null http://localhost:8080 &>/dev/null; then
        echo -e "${GREEN}✓ Port-forward is ready!${NC}\n"
        break
    fi
    sleep 1
    if [ $i -eq 10 ]; then
        echo -e "${RED}✗ Port-forward did not become ready${NC}\n"
        exit 1
    fi
done

# Step 5: Test all endpoints
echo -e "${YELLOW}Step 5: Testing all endpoints...${NC}\n"

HOSTS=(
    "argocd.local"
    "redpanda-console.local"
    "grafana.local"
    "kiali.local"
    "minio.local"
    "flink.local"
    "starrocks.local"
    "trino.local"
    "prometheus.local"
)

SUCCESS=0
FAILED=0

for host in "${HOSTS[@]}"; do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -H "Host: $host" http://localhost:8080 2>/dev/null || echo "000")
    if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ] || [ "$HTTP_CODE" = "301" ]; then
        echo -e "${GREEN}✓ ${host}${NC} (HTTP ${HTTP_CODE})"
        ((SUCCESS++))
    else
        echo -e "${RED}✗ ${host}${NC} (HTTP ${HTTP_CODE})"
        ((FAILED++))
    fi
done

echo ""
echo -e "${GREEN}=== Summary ===${NC}"
echo -e "  Success: ${GREEN}${SUCCESS}${NC}"
echo -e "  Failed: ${RED}${FAILED}${NC}"
echo ""

if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}✓ All endpoints are working!${NC}\n"
    echo -e "${YELLOW}Access URLs (with /etc/hosts entries pointing to 127.0.0.1):${NC}"
    for host in "${HOSTS[@]}"; do
        echo -e "  ${BLUE}http://${host}:8080${NC}"
    done
    echo ""
else
    echo -e "${YELLOW}Some endpoints failed. Check:${NC}"
    echo -e "  1. VirtualServices: kubectl get virtualservice -A"
    echo -e "  2. Gateway: kubectl get gateway -n istio-system"
    echo -e "  3. Port-forward: ps aux | grep 'kubectl port-forward.*istio-ingressgateway'"
    echo ""
fi

echo -e "${YELLOW}Port-forward is running (PID: ${PF_PID})${NC}"
echo -e "${YELLOW}To stop: pkill -f 'kubectl port-forward.*istio-ingressgateway'${NC}\n"
echo -e "${RED}⚠️  IMPORTANT: Keep this port-forward running!${NC}"
echo -e "${YELLOW}If it stops, endpoints will refuse connections.${NC}"
echo -e "${YELLOW}To restart: ./scripts/fix-endpoints.sh${NC}\n"

