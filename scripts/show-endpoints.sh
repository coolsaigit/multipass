#!/bin/bash

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Multipass Service Endpoints ===${NC}\n"

# Get Istio Gateway information
echo -e "${YELLOW}Istio Ingress Gateway:${NC}"
ISTIO_NAMESPACE="istio-system"
ISTIO_SVC="istio-ingressgateway"

# Check if Istio namespace exists
if ! kubectl get namespace "${ISTIO_NAMESPACE}" &>/dev/null; then
    echo -e "${YELLOW}⚠ Istio namespace not found. Istio is still deploying...${NC}"
    echo -e "${YELLOW}   Wait a few minutes and run this script again, or check:${NC}"
    echo -e "${BLUE}   kubectl get pods -n istio-system${NC}\n"
    exit 0
fi

# Check if Istio Gateway service exists, wait a bit if not
if ! kubectl get svc "${ISTIO_SVC}" -n "${ISTIO_NAMESPACE}" &>/dev/null; then
    echo -e "${YELLOW}⚠ Istio Gateway service not found. Waiting for Istio to deploy...${NC}"
    echo -e "${YELLOW}   Checking if Istio pods are starting...${NC}"
    
    # Wait up to 30 seconds for Istio to start
    for i in {1..6}; do
        sleep 5
        if kubectl get svc "${ISTIO_SVC}" -n "${ISTIO_NAMESPACE}" &>/dev/null; then
            echo -e "${GREEN}✓ Istio Gateway found!${NC}\n"
            break
        fi
        if [ $i -eq 6 ]; then
            echo -e "${YELLOW}⚠ Istio Gateway still not ready after 30 seconds.${NC}"
            echo -e "${YELLOW}   Istio is deploying in the background. Run this script again in a few minutes.${NC}"
            echo -e "${BLUE}   Check status: kubectl get pods -n istio-system${NC}\n"
            exit 0
        fi
    done
fi

if kubectl get svc "${ISTIO_SVC}" -n "${ISTIO_NAMESPACE}" &>/dev/null; then
    EXTERNAL_IP=$(kubectl get svc "${ISTIO_SVC}" -n "${ISTIO_NAMESPACE}" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
    CLUSTER_IP=$(kubectl get svc "${ISTIO_SVC}" -n "${ISTIO_NAMESPACE}" -o jsonpath='{.spec.clusterIP}' 2>/dev/null || echo "")
    NODE_PORT=$(kubectl get svc "${ISTIO_SVC}" -n "${ISTIO_NAMESPACE}" -o jsonpath='{.spec.ports[?(@.name=="http2")].nodePort}' 2>/dev/null || echo "")
    
    if [ -n "${EXTERNAL_IP}" ]; then
        GATEWAY_IP="${EXTERNAL_IP}"
        ACCESS_METHOD="LoadBalancer"
    elif [ -n "${NODE_PORT}" ]; then
        NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null || kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="ExternalIP")].address}' 2>/dev/null || echo "localhost")
        GATEWAY_IP="${NODE_IP}:${NODE_PORT}"
        ACCESS_METHOD="NodePort"
    else
        GATEWAY_IP="${CLUSTER_IP}"
        ACCESS_METHOD="ClusterIP (use port-forward)"
    fi
    
    echo -e "  IP/Address: ${GREEN}${GATEWAY_IP}${NC}"
    echo -e "  Access Method: ${ACCESS_METHOD}\n"
    
    if [ "${ACCESS_METHOD}" = "ClusterIP (use port-forward)" ]; then
        echo -e "${YELLOW}Port-forward command:${NC}"
        echo -e "  ${GREEN}kubectl port-forward svc/${ISTIO_SVC} -n ${ISTIO_NAMESPACE} 8080:80${NC}\n"
        GATEWAY_URL="http://localhost:8080"
    else
        GATEWAY_URL="http://${GATEWAY_IP}"
    fi
else
    echo -e "${YELLOW}⚠ Istio Gateway not found. Please deploy Istio first.${NC}\n"
    exit 1
fi

# Service endpoints
echo -e "${YELLOW}Service Endpoints (via Istio Gateway):${NC}\n"

echo -e "${GREEN}ArgoCD:${NC}"
echo -e "  URL: ${GATEWAY_URL} (Host: argocd.local)"
echo -e "  Command: ${BLUE}curl -H \"Host: argocd.local\" ${GATEWAY_URL}${NC}"
echo -e "  Or add to /etc/hosts: ${GATEWAY_IP} argocd.local\n"

echo -e "${GREEN}Redpanda Console:${NC}"
echo -e "  URL: ${GATEWAY_URL} (Host: redpanda-console.local)"
echo -e "  Command: ${BLUE}curl -H \"Host: redpanda-console.local\" ${GATEWAY_URL}${NC}"
echo -e "  Or add to /etc/hosts: ${GATEWAY_IP} redpanda-console.local\n"

echo -e "${GREEN}Grafana:${NC}"
echo -e "  URL: ${GATEWAY_URL} (Host: grafana.local)"
echo -e "  Command: ${BLUE}curl -H \"Host: grafana.local\" ${GATEWAY_URL}${NC}"
echo -e "  Or add to /etc/hosts: ${GATEWAY_IP} grafana.local\n"

echo -e "${GREEN}Kiali:${NC}"
echo -e "  URL: ${GATEWAY_URL} (Host: kiali.local)"
echo -e "  Command: ${BLUE}curl -H \"Host: kiali.local\" ${GATEWAY_URL}${NC}"
echo -e "  Or add to /etc/hosts: ${GATEWAY_IP} kiali.local\n"

# Quick setup for /etc/hosts
echo -e "${YELLOW}Quick Setup (/etc/hosts):${NC}"
if [ "${ACCESS_METHOD}" != "ClusterIP (use port-forward)" ]; then
    echo -e "  Run this command to add all endpoints to /etc/hosts:"
    echo -e "  ${BLUE}echo \"${GATEWAY_IP} argocd.local redpanda-console.local grafana.local kiali.local\" | sudo tee -a /etc/hosts${NC}\n"
else
    echo -e "  ${YELLOW}Note: Using port-forward. Access via localhost:8080 with Host headers.${NC}\n"
fi

# ArgoCD password
echo -e "${YELLOW}ArgoCD Credentials:${NC}"
ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d || echo "")
if [ -n "${ARGOCD_PASSWORD}" ]; then
    echo -e "  Username: ${GREEN}admin${NC}"
    echo -e "  Password: ${GREEN}${ARGOCD_PASSWORD}${NC}\n"
else
    echo -e "  ${YELLOW}Password not found (may have been changed)${NC}\n"
fi

echo -e "${GREEN}All endpoints are accessible via Istio Gateway! 🚀${NC}"

