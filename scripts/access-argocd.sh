#!/bin/bash

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== ArgoCD Access Script ===${NC}\n"

# Check if port-forward is already running
if pgrep -f "kubectl port-forward.*istio-ingressgateway" > /dev/null; then
    echo -e "${YELLOW}Port-forward already running. Killing existing process...${NC}"
    pkill -f "kubectl port-forward.*istio-ingressgateway"
    sleep 2
fi

# Start port-forward
echo -e "${YELLOW}Starting port-forward for Istio Gateway...${NC}"
kubectl port-forward svc/istio-ingressgateway -n istio-system 8080:80 > /dev/null 2>&1 &
PORT_FORWARD_PID=$!

# Wait for port-forward to be ready
sleep 3

# Check if port-forward is working
if ! kill -0 $PORT_FORWARD_PID 2>/dev/null; then
    echo -e "${RED}Error: Port-forward failed to start${NC}"
    exit 1
fi

# Test access
echo -e "${YELLOW}Testing ArgoCD access...${NC}"
if curl -s -H "Host: argocd.local" http://localhost:8080 | grep -q "Argo CD"; then
    echo -e "${GREEN}✓ ArgoCD is accessible!${NC}\n"
else
    echo -e "${YELLOW}⚠ ArgoCD might still be starting...${NC}\n"
fi

# Get credentials
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d || echo "")

echo -e "${GREEN}=== ArgoCD Access Information ===${NC}\n"
echo -e "URL: ${BLUE}http://argocd.local${NC}"
echo -e "   (Access via: ${BLUE}http://localhost:8080${NC} with Host header)\n"
echo -e "Or use this command:"
echo -e "  ${BLUE}curl -H 'Host: argocd.local' http://localhost:8080${NC}\n"

if [ -n "${ARGOCD_PASSWORD}" ]; then
    echo -e "${GREEN}Credentials:${NC}"
    echo -e "  Username: ${BLUE}admin${NC}"
    echo -e "  Password: ${BLUE}${ARGOCD_PASSWORD}${NC}\n"
fi

echo -e "${YELLOW}Port-forward is running in the background (PID: ${PORT_FORWARD_PID})${NC}"
echo -e "${YELLOW}To stop: pkill -f 'kubectl port-forward.*istio-ingressgateway'${NC}\n"

echo -e "${GREEN}=== Browser Access ===${NC}"
echo -e "Option 1: Use browser extension to set Host header"
echo -e "Option 2: Add to /etc/hosts: ${BLUE}127.0.0.1 argocd.local${NC}"
echo -e "         Then access: ${BLUE}http://argocd.local:8080${NC}\n"

# Keep script running
echo -e "${YELLOW}Press Ctrl+C to stop port-forward and exit...${NC}\n"

# Trap to cleanup on exit
trap "echo -e '\n${YELLOW}Stopping port-forward...${NC}'; pkill -f 'kubectl port-forward.*istio-ingressgateway'; exit" INT TERM

# Wait
wait $PORT_FORWARD_PID

