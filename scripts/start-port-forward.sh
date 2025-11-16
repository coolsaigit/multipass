#!/bin/bash

# Quick script to start port-forward to Istio Gateway

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${YELLOW}Starting port-forward to Istio Gateway...${NC}"

# Kill existing port-forwards
pkill -f "kubectl port-forward.*istio-ingressgateway" 2>/dev/null
sleep 2

# Start new port-forward
kubectl port-forward svc/istio-ingressgateway -n istio-system 8080:80 > /dev/null 2>&1 &
PF_PID=$!

# Wait for it to be ready
sleep 3

# Test
if curl -s -o /dev/null -H "Host: argocd.local" http://localhost:8080 2>/dev/null; then
    echo -e "${GREEN}✓ Port-forward is running (PID: ${PF_PID})${NC}"
    echo -e "${GREEN}✓ All endpoints should now be accessible${NC}\n"
    echo -e "${YELLOW}Access URLs:${NC}"
    echo -e "  http://argocd.local:8080"
    echo -e "  http://redpanda-console.local:8080"
    echo -e "  http://grafana.local:8080"
    echo -e "  ... and 6 more services\n"
    echo -e "${YELLOW}To stop: pkill -f 'kubectl port-forward.*istio-ingressgateway'${NC}"
else
    echo -e "${RED}✗ Port-forward failed to start${NC}"
    exit 1
fi

