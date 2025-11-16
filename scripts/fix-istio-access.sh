#!/bin/bash

# Script to fix Istio Gateway access issues
set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== Fixing Istio Gateway Access ===${NC}\n"

# 1. Check if Istio is deployed
echo -e "${YELLOW}1. Checking Istio deployment...${NC}"
if ! kubectl get namespace istio-system >/dev/null 2>&1; then
    echo -e "${RED}Error: Istio namespace not found. Please deploy Istio first.${NC}"
    exit 1
fi

if ! kubectl get pods -n istio-system | grep -q istio-ingressgateway; then
    echo -e "${RED}Error: Istio ingress gateway not found.${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Istio is deployed${NC}\n"

# 2. Configure ArgoCD for insecure mode
echo -e "${YELLOW}2. Configuring ArgoCD for insecure mode...${NC}"
if kubectl get namespace argocd >/dev/null 2>&1; then
    kubectl patch configmap argocd-cmd-params-cm -n argocd --type merge -p '{"data":{"server.insecure":"true"}}' 2>/dev/null || \
    kubectl create configmap argocd-cmd-params-cm -n argocd --from-literal=server.insecure=true --dry-run=client -o yaml | kubectl apply -f -
    
    echo -e "${GREEN}✓ ArgoCD configured for insecure mode${NC}"
    echo -e "${YELLOW}   Restarting ArgoCD server...${NC}"
    kubectl rollout restart deployment argocd-server -n argocd 2>/dev/null || echo -e "${YELLOW}   ArgoCD server deployment not found (may not be deployed yet)${NC}"
else
    echo -e "${YELLOW}   ArgoCD namespace not found (will be configured when deployed)${NC}"
fi
echo ""

# 3. Check Gateway and VirtualService
echo -e "${YELLOW}3. Checking Istio Gateway and VirtualServices...${NC}"
if kubectl get gateway multipass-gateway -n istio-system >/dev/null 2>&1; then
    echo -e "${GREEN}✓ Gateway found${NC}"
else
    echo -e "${RED}   Gateway not found. Apply: kubectl apply -f gitops/istio/gateway.yaml${NC}"
fi

if kubectl get virtualservice argocd -n argocd >/dev/null 2>&1; then
    echo -e "${GREEN}✓ ArgoCD VirtualService found${NC}"
else
    echo -e "${YELLOW}   ArgoCD VirtualService not found (will be created by ArgoCD)${NC}"
fi
echo ""

# 4. Get Istio Gateway info
echo -e "${YELLOW}4. Istio Ingress Gateway Information:${NC}"
ISTIO_SVC=$(kubectl get svc istio-ingressgateway -n istio-system -o jsonpath='{.metadata.name}' 2>/dev/null || echo "")
if [ -n "$ISTIO_SVC" ]; then
    EXTERNAL_IP=$(kubectl get svc istio-ingressgateway -n istio-system -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
    CLUSTER_IP=$(kubectl get svc istio-ingressgateway -n istio-system -o jsonpath='{.spec.clusterIP}' 2>/dev/null || echo "")
    
    if [ -n "$EXTERNAL_IP" ]; then
        echo -e "${GREEN}   External IP: ${EXTERNAL_IP}${NC}"
        echo -e "${YELLOW}   Add to /etc/hosts: ${EXTERNAL_IP} argocd.local redpanda-console.local grafana.local kiali.local${NC}"
    else
        echo -e "${YELLOW}   No external IP (using ClusterIP: ${CLUSTER_IP})${NC}"
        echo -e "${YELLOW}   Use port-forward: kubectl port-forward svc/istio-ingressgateway -n istio-system 8080:80${NC}"
    fi
else
    echo -e "${RED}   Istio ingress gateway service not found${NC}"
fi
echo ""

# 5. Test access
echo -e "${YELLOW}5. Testing access...${NC}"
echo -e "${YELLOW}   To test, run:${NC}"
echo -e "   ${GREEN}kubectl port-forward svc/istio-ingressgateway -n istio-system 8080:80${NC}"
echo -e "   ${GREEN}curl -H \"Host: argocd.local\" http://localhost:8080${NC}"
echo ""

echo -e "${GREEN}=== Setup Complete ===${NC}\n"
echo -e "${YELLOW}Next steps:${NC}"
echo -e "1. Ensure Istio Gateway and VirtualServices are deployed"
echo -e "2. Configure ArgoCD insecure mode (done above)"
echo -e "3. Use port-forward or update /etc/hosts to access services"
echo -e "4. Access ArgoCD at: http://argocd.local (or http://localhost:8080 with port-forward)\n"

