#!/bin/bash

# Unified script to access all services via Istio Gateway
# This avoids port conflicts by using a single port-forward to the Gateway

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}=== Multipass Service Access (via Istio Gateway) ===${NC}\n"

ISTIO_NAMESPACE="istio-system"
ISTIO_SVC="istio-ingressgateway"
LOCAL_PORT="8080"
REMOTE_PORT="80"

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}Error: kubectl is not installed${NC}"
    exit 1
fi

# Check if Istio Gateway exists
if ! kubectl get svc "${ISTIO_SVC}" -n "${ISTIO_NAMESPACE}" &>/dev/null; then
    echo -e "${RED}Error: Istio Gateway not found. Please deploy Istio first.${NC}"
    exit 1
fi

# Kill existing port-forwards to avoid conflicts
echo -e "${YELLOW}Checking for existing port-forwards...${NC}"
pkill -f "kubectl port-forward.*istio-ingressgateway" 2>/dev/null && echo -e "${GREEN}✓ Stopped existing port-forward${NC}" || echo -e "${GREEN}✓ No existing port-forward${NC}"
sleep 2

# Start port-forward to Istio Gateway
echo -e "\n${YELLOW}Starting port-forward to Istio Gateway (${LOCAL_PORT}:${REMOTE_PORT})...${NC}"
kubectl port-forward svc/"${ISTIO_SVC}" -n "${ISTIO_NAMESPACE}" "${LOCAL_PORT}":"${REMOTE_PORT}" > /dev/null 2>&1 &
PF_PID=$!

# Wait for port-forward to be ready
echo -e "${YELLOW}Waiting for port-forward to be ready...${NC}"
for i in {1..10}; do
    if curl -s -o /dev/null -w "%{http_code}" "http://localhost:${LOCAL_PORT}" &>/dev/null; then
        echo -e "${GREEN}✓ Port-forward is ready!${NC}\n"
        break
    fi
    sleep 1
    if [ $i -eq 10 ]; then
        echo -e "${RED}Error: Port-forward did not become ready${NC}"
        kill $PF_PID 2>/dev/null
        exit 1
    fi
done

# Get ArgoCD password
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d || echo "")

echo -e "${GREEN}=== All Services Accessible via Istio Gateway ===${NC}\n"
echo -e "${YELLOW}Access Method: Port-forward to Istio Gateway${NC}"
echo -e "  Local port: ${BLUE}${LOCAL_PORT}${NC}"
echo -e "  Remote port: ${BLUE}${REMOTE_PORT}${NC}\n"

echo -e "${GREEN}Service URLs (use Host headers or /etc/hosts):${NC}\n"

echo -e "1. ${GREEN}ArgoCD${NC}"
echo -e "   URL: ${BLUE}http://argocd.local:${LOCAL_PORT}${NC}"
echo -e "   Command: ${BLUE}curl -H \"Host: argocd.local\" http://localhost:${LOCAL_PORT}${NC}"
if [ -n "${ARGOCD_PASSWORD}" ]; then
    echo -e "   Credentials: ${BLUE}admin / ${ARGOCD_PASSWORD}${NC}"
fi
echo ""

echo -e "2. ${GREEN}Redpanda Console${NC}"
echo -e "   URL: ${BLUE}http://redpanda-console.local:${LOCAL_PORT}${NC}"
echo -e "   Command: ${BLUE}curl -H \"Host: redpanda-console.local\" http://localhost:${LOCAL_PORT}${NC}"
echo ""

echo -e "3. ${GREEN}Grafana${NC}"
echo -e "   URL: ${BLUE}http://grafana.local:${LOCAL_PORT}${NC}"
echo -e "   Command: ${BLUE}curl -H \"Host: grafana.local\" http://localhost:${LOCAL_PORT}${NC}"
echo ""

echo -e "4. ${GREEN}Kiali${NC}"
echo -e "   URL: ${BLUE}http://kiali.local:${LOCAL_PORT}${NC}"
echo -e "   Command: ${BLUE}curl -H \"Host: kiali.local\" http://localhost:${LOCAL_PORT}${NC}"
echo ""

echo -e "5. ${GREEN}MinIO Console${NC}"
echo -e "   URL: ${BLUE}http://minio.local:${LOCAL_PORT}${NC}"
echo -e "   Command: ${BLUE}curl -H \"Host: minio.local\" http://localhost:${LOCAL_PORT}${NC}"
echo ""

echo -e "6. ${GREEN}Flink${NC}"
echo -e "   URL: ${BLUE}http://flink.local:${LOCAL_PORT}${NC}"
echo -e "   Command: ${BLUE}curl -H \"Host: flink.local\" http://localhost:${LOCAL_PORT}${NC}"
echo ""

echo -e "7. ${GREEN}StarRocks${NC}"
echo -e "   URL: ${BLUE}http://starrocks.local:${LOCAL_PORT}${NC}"
echo -e "   Command: ${BLUE}curl -H \"Host: starrocks.local\" http://localhost:${LOCAL_PORT}${NC}"
echo ""

echo -e "8. ${GREEN}Trino${NC}"
echo -e "   URL: ${BLUE}http://trino.local:${LOCAL_PORT}${NC}"
echo -e "   Command: ${BLUE}curl -H \"Host: trino.local\" http://localhost:${LOCAL_PORT}${NC}"
echo ""

echo -e "9. ${GREEN}Prometheus${NC}"
echo -e "   URL: ${BLUE}http://prometheus.local:${LOCAL_PORT}${NC}"
echo -e "   Command: ${BLUE}curl -H \"Host: prometheus.local\" http://localhost:${LOCAL_PORT}${NC}"
echo ""

echo -e "${YELLOW}=== Quick Setup ===${NC}\n"
echo -e "Add to /etc/hosts for easy access:"
echo -e "  ${BLUE}echo \"127.0.0.1 argocd.local redpanda-console.local grafana.local kiali.local minio.local flink.local starrocks.local trino.local prometheus.local\" | sudo tee -a /etc/hosts${NC}\n"

echo -e "${YELLOW}Port-forward is running (PID: ${PF_PID})${NC}"
echo -e "${YELLOW}Press Ctrl+C to stop...${NC}\n"

# Trap to cleanup on exit
trap "echo -e '\n${YELLOW}Stopping port-forward...${NC}'; pkill -f 'kubectl port-forward.*istio-ingressgateway'; exit" INT TERM

# Keep script running
wait $PF_PID

