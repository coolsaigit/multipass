#!/bin/bash

# Script to fix and access all endpoints
# This is the single script for endpoint management

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}=== Fixing and Accessing Endpoints ===${NC}\n"

ISTIO_NAMESPACE="istio-system"
ISTIO_SVC="istio-ingressgateway"
LOCAL_PORT="8080"
REMOTE_PORT="80"

# Step 1: Apply Gateway if missing
echo -e "${YELLOW}Step 1: Checking Istio Gateway...${NC}"
if ! kubectl get gateway multipass-gateway -n "${ISTIO_NAMESPACE}" &>/dev/null; then
    echo -e "${YELLOW}Gateway missing. Applying...${NC}"
    kubectl apply -f gitops/istio/gateway.yaml
    echo -e "${GREEN}✓ Gateway applied${NC}\n"
else
    echo -e "${GREEN}✓ Gateway exists${NC}\n"
fi

# Step 2: Apply all VirtualServices
echo -e "${YELLOW}Step 2: Applying VirtualServices...${NC}"
kubectl apply -f gitops/istio/virtualservices/ &>/dev/null
echo -e "${GREEN}✓ VirtualServices applied${NC}\n"

# Step 3: Apply ArgoCD ConfigMap
echo -e "${YELLOW}Step 3: Configuring ArgoCD for insecure mode...${NC}"
kubectl apply -f gitops/istio/argocd-config/configmap.yaml &>/dev/null
kubectl rollout restart deployment argocd-server -n argocd &>/dev/null || true
echo -e "${GREEN}✓ ArgoCD configured${NC}\n"

# Step 4: Stop existing port-forwards and start new one
echo -e "${YELLOW}Step 4: Setting up port-forward to Istio Gateway...${NC}"
pkill -f "kubectl port-forward.*istio-ingressgateway" 2>/dev/null
sleep 2
kubectl port-forward svc/"${ISTIO_SVC}" -n "${ISTIO_NAMESPACE}" "${LOCAL_PORT}":"${REMOTE_PORT}" > /dev/null 2>&1 &
PF_PID=$!
echo -e "${GREEN}✓ Port-forward started (PID: ${PF_PID})${NC}\n"

# Wait for port-forward to be ready
echo -e "${YELLOW}Waiting for port-forward to be ready...${NC}"
for i in {1..10}; do
    if curl -s -o /dev/null http://localhost:"${LOCAL_PORT}" &>/dev/null; then
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
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -H "Host: $host" http://localhost:"${LOCAL_PORT}" 2>/dev/null || echo "000")
    if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ] || [ "$HTTP_CODE" = "301" ] || [ "$HTTP_CODE" = "303" ]; then
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

if [ $FAILED -gt 0 ]; then
    echo -e "${YELLOW}Some endpoints failed. Check:${NC}"
    echo -e "  1. VirtualServices: kubectl get virtualservice -A"
    echo -e "  2. Gateway: kubectl get gateway -n istio-system"
    echo -e "  3. Port-forward: ps aux | grep 'kubectl port-forward.*istio-ingressgateway'"
    echo ""
fi

# Get ArgoCD password
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d || echo "")

# Show access information (simplified - always show port-forward URLs since we're using port-forward)
echo -e "${GREEN}=== Access Information ===${NC}\n"
echo -e "${YELLOW}Access Method:${NC} Port-forward to Istio Gateway (localhost:${LOCAL_PORT})\n"

echo -e "${GREEN}Service URLs:${NC}\n"
for host in "${HOSTS[@]}"; do
    echo -e "  ${BLUE}http://${host}:${LOCAL_PORT}${NC}"
done

echo ""
echo -e "${YELLOW}Quick Setup (/etc/hosts):${NC}"
HOSTS_ENTRIES="127.0.0.1 ${HOSTS[*]}"
echo -e "  ${BLUE}echo \"${HOSTS_ENTRIES}\" | sudo tee -a /etc/hosts${NC}\n"
echo -e "${YELLOW}After adding to /etc/hosts, access via: http://<hostname>.local:${LOCAL_PORT}${NC}\n"

if [ -n "${ARGOCD_PASSWORD}" ]; then
    echo -e "${YELLOW}ArgoCD Credentials:${NC}"
    echo -e "  Username: ${GREEN}admin${NC}"
    echo -e "  Password: ${GREEN}${ARGOCD_PASSWORD}${NC}\n"
fi

echo -e "${YELLOW}Port-forward is running (PID: ${PF_PID})${NC}"
echo -e "${YELLOW}To stop: pkill -f 'kubectl port-forward.*istio-ingressgateway'${NC}\n"
echo -e "${RED}⚠️  IMPORTANT: Keep this port-forward running!${NC}"
echo -e "${YELLOW}If it stops, endpoints will refuse connections.${NC}"
echo -e "${YELLOW}To restart: ./scripts/fix-endpoints.sh${NC}\n"
