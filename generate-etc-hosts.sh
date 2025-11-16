#!/bin/bash

# Script to generate /etc/hosts entries for Multipass services
# Usage: ./generate-etc-hosts.sh [--apply]

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== Generating /etc/hosts entries ===${NC}\n"

ISTIO_NAMESPACE="istio-system"
ISTIO_SVC="istio-ingressgateway"

# Get Gateway IP
EXTERNAL_IP=$(kubectl get svc "${ISTIO_SVC}" -n "${ISTIO_NAMESPACE}" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
NODE_PORT=$(kubectl get svc "${ISTIO_SVC}" -n "${ISTIO_NAMESPACE}" -o jsonpath='{.spec.ports[?(@.name=="http2")].nodePort}' 2>/dev/null || echo "")

if [ -n "${EXTERNAL_IP}" ]; then
    GATEWAY_IP="${EXTERNAL_IP}"
    ACCESS_METHOD="LoadBalancer"
elif [ -n "${NODE_PORT}" ]; then
    NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null || kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="ExternalIP")].address}' 2>/dev/null || echo "YOUR_NODE_IP")
    GATEWAY_IP="${NODE_IP}:${NODE_PORT}"
    ACCESS_METHOD="NodePort"
else
    GATEWAY_IP="127.0.0.1"
    ACCESS_METHOD="Port-Forward (localhost:8080)"
fi

echo -e "${YELLOW}Gateway IP: ${GATEWAY_IP}${NC}"
echo -e "${YELLOW}Access Method: ${ACCESS_METHOD}${NC}\n"

# Generate hosts entries
HOSTS_ENTRIES="${GATEWAY_IP} argocd.local redpanda-console.local grafana.local kiali.local minio.local flink.local starrocks.local trino.local prometheus.local"

echo -e "${GREEN}/etc/hosts entries:${NC}"
echo -e "${BLUE}${HOSTS_ENTRIES}${NC}\n"

if [ "$1" = "--apply" ]; then
    echo -e "${YELLOW}Adding entries to /etc/hosts (requires sudo)...${NC}"
    echo "${HOSTS_ENTRIES}" | sudo tee -a /etc/hosts
    echo -e "${GREEN}✓ Entries added to /etc/hosts${NC}\n"
else
    echo -e "${YELLOW}To apply these entries, run:${NC}"
    echo -e "${BLUE}echo \"${HOSTS_ENTRIES}\" | sudo tee -a /etc/hosts${NC}\n"
    echo -e "${YELLOW}Or run this script with --apply flag:${NC}"
    echo -e "${BLUE}./generate-etc-hosts.sh --apply${NC}\n"
fi

echo -e "${GREEN}All services are now accessible via:${NC}"
echo -e "  http://argocd.local"
echo -e "  http://redpanda-console.local"
echo -e "  http://grafana.local"
echo -e "  http://kiali.local"
echo -e "  http://minio.local"
echo -e "  http://flink.local"
echo -e "  http://starrocks.local"
echo -e "  http://trino.local"
echo -e "  http://prometheus.local"
if [ "${ACCESS_METHOD}" = "Port-Forward (localhost:8080)" ]; then
    echo -e "\n${YELLOW}Note: Using port-forward. Access via: http://<hostname>.local:8080${NC}"
    echo -e "${YELLOW}Start port-forward: kubectl port-forward svc/${ISTIO_SVC} -n ${ISTIO_NAMESPACE} 8080:80${NC}"
fi
echo ""

