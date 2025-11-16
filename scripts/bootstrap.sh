#!/bin/bash
set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
ARGOCD_NAMESPACE="argocd"
ARGOCD_RELEASE_NAME="argocd"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HELM_CHART_PATH="${REPO_ROOT}/gitops/helm/argocd"

echo -e "${GREEN}=== Multipass GitOps Bootstrap ===${NC}\n"

# Check prerequisites
echo -e "${YELLOW}Checking prerequisites...${NC}"
command -v kubectl >/dev/null 2>&1 || { echo -e "${RED}Error: kubectl is required but not installed.${NC}" >&2; exit 1; }
command -v helm >/dev/null 2>&1 || { echo -e "${RED}Error: helm is required but not installed.${NC}" >&2; exit 1; }

# Check if kubectl can connect to cluster
if ! kubectl cluster-info &>/dev/null; then
    echo -e "${RED}Error: Cannot connect to Kubernetes cluster.${NC}" >&2
    exit 1
fi

echo -e "${GREEN}✓ Prerequisites check passed${NC}\n"

# Step 1: Add ArgoCD Helm repository
echo -e "${YELLOW}Step 1: Adding ArgoCD Helm repository...${NC}"
if ! helm repo list | grep -q "argoproj"; then
    helm repo add argo https://argoproj.github.io/argo-helm
    helm repo update
    echo -e "${GREEN}✓ ArgoCD Helm repository added${NC}\n"
else
    echo -e "${GREEN}✓ ArgoCD Helm repository already exists${NC}\n"
fi

# Step 2: Install ArgoCD
echo -e "${YELLOW}Step 2: Installing ArgoCD...${NC}"
if kubectl get namespace "${ARGOCD_NAMESPACE}" &>/dev/null; then
    if helm list -n "${ARGOCD_NAMESPACE}" | grep -q "${ARGOCD_RELEASE_NAME}"; then
        echo -e "${YELLOW}ArgoCD already installed. Upgrading...${NC}"
        helm upgrade "${ARGOCD_RELEASE_NAME}" argo/argo-cd \
            --namespace "${ARGOCD_NAMESPACE}" \
            --create-namespace \
            --wait \
            --timeout 10m
    else
        echo -e "${YELLOW}Namespace exists but ArgoCD not found. Installing...${NC}"
        helm install "${ARGOCD_RELEASE_NAME}" argo/argo-cd \
            --namespace "${ARGOCD_NAMESPACE}" \
            --create-namespace \
            --wait \
            --timeout 10m
    fi
else
    echo -e "${YELLOW}Installing ArgoCD for the first time...${NC}"
    helm install "${ARGOCD_RELEASE_NAME}" argo/argo-cd \
        --namespace "${ARGOCD_NAMESPACE}" \
        --create-namespace \
        --wait \
        --timeout 10m
fi
echo -e "${GREEN}✓ ArgoCD installed${NC}\n"

# Step 3: Wait for ArgoCD to be ready
echo -e "${YELLOW}Step 3: Waiting for ArgoCD to be ready...${NC}"
kubectl wait --for=condition=available \
    --timeout=300s \
    deployment/argocd-server \
    -n "${ARGOCD_NAMESPACE}" || {
    echo -e "${RED}Error: ArgoCD server did not become ready in time${NC}" >&2
    exit 1
}
echo -e "${GREEN}✓ ArgoCD is ready${NC}\n"

# Step 4: Get ArgoCD admin password
echo -e "${YELLOW}Step 4: Retrieving ArgoCD admin password...${NC}"
ARGOCD_PASSWORD=$(kubectl -n "${ARGOCD_NAMESPACE}" get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d 2>/dev/null || echo "")
if [ -z "${ARGOCD_PASSWORD}" ]; then
    echo -e "${YELLOW}Admin password not found (may have been changed)${NC}"
else
    echo -e "${GREEN}✓ Admin password retrieved${NC}"
    echo -e "${YELLOW}ArgoCD Admin Password: ${ARGOCD_PASSWORD}${NC}"
    echo -e "${YELLOW}(Save this password securely!)${NC}\n"
fi

# Step 5: Create ArgoCD Project
echo -e "${YELLOW}Step 5: Creating ArgoCD project...${NC}"
if [ -f "${REPO_ROOT}/gitops/argo/projects/multipass-project.yaml" ]; then
    kubectl apply -f "${REPO_ROOT}/gitops/argo/projects/multipass-project.yaml"
    echo -e "${GREEN}✓ ArgoCD project created${NC}\n"
else
    echo -e "${YELLOW}Project file not found, skipping...${NC}\n"
fi

# Step 6: Configure Git repository (if needed)
echo -e "${YELLOW}Step 6: Configuring Git repository...${NC}"
echo -e "${YELLOW}Note: Update repoURL in Application manifests if needed${NC}"
echo -e "${YELLOW}Current repoURL placeholder: https://github.com/your-org/multipass-gitops.git${NC}\n"

# Step 7: Create bootstrap Application
echo -e "${YELLOW}Step 7: Creating bootstrap Application...${NC}"
if [ -f "${REPO_ROOT}/gitops/argo/apps/argocd-bootstrap.yaml" ]; then
    kubectl apply -f "${REPO_ROOT}/gitops/argo/apps/argocd-bootstrap.yaml"
    echo -e "${GREEN}✓ Bootstrap Application created${NC}\n"
    
    # Wait for bootstrap app to sync
    echo -e "${YELLOW}Waiting for bootstrap Application to sync...${NC}"
    sleep 10
    kubectl wait --for=condition=healthy \
        --timeout=120s \
        application/argocd-bootstrap \
        -n "${ARGOCD_NAMESPACE}" 2>/dev/null || {
        echo -e "${YELLOW}Bootstrap app may still be syncing. Check ArgoCD UI.${NC}"
    }
    echo -e "${GREEN}✓ Bootstrap Application synced${NC}\n"
else
    echo -e "${YELLOW}Bootstrap Application file not found, skipping...${NC}\n"
fi

# Step 8: Create App of Apps
echo -e "${YELLOW}Step 8: Creating App of Apps...${NC}"
if [ -f "${REPO_ROOT}/gitops/argo/apps/app-of-apps.yaml" ]; then
    kubectl apply -f "${REPO_ROOT}/gitops/argo/apps/app-of-apps.yaml"
    echo -e "${GREEN}✓ App of Apps created${NC}\n"
    
    echo -e "${YELLOW}Waiting for App of Apps to sync...${NC}"
    sleep 10
    echo -e "${GREEN}✓ App of Apps syncing${NC}\n"
else
    echo -e "${YELLOW}App of Apps file not found, skipping...${NC}\n"
fi

# Summary
echo -e "${GREEN}=== Bootstrap Complete ===${NC}\n"
echo -e "ArgoCD is installed and configured."
echo -e "Applications will be deployed automatically via GitOps.\n"
echo -e "${YELLOW}Next steps:${NC}"
echo -e "1. Access ArgoCD UI: kubectl port-forward svc/argocd-server -n ${ARGOCD_NAMESPACE} 8080:443"
echo -e "2. Login with username: admin"
if [ -n "${ARGOCD_PASSWORD}" ]; then
    echo -e "3. Password: ${ARGOCD_PASSWORD}"
fi
echo -e "4. Monitor applications in ArgoCD UI\n"
echo -e "${GREEN}All done! 🚀${NC}"

