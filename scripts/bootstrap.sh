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

# Check and auto-install Helm if needed
if ! command -v helm >/dev/null 2>&1; then
    echo -e "${YELLOW}Helm not found. Attempting to install...${NC}"
    
    OS="$(uname -s)"
    case "${OS}" in
        Linux*)
            echo -e "${YELLOW}Detected Linux. Installing Helm...${NC}"
            # Use official Helm install script (works for all Linux distros)
            curl -fsSL -o /tmp/get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
            chmod 700 /tmp/get_helm.sh
            if /tmp/get_helm.sh; then
                rm -f /tmp/get_helm.sh
            else
                echo -e "${RED}Error: Helm installation failed.${NC}" >&2
                rm -f /tmp/get_helm.sh
                exit 1
            fi
            ;;
        Darwin*)
            echo -e "${YELLOW}Detected macOS. Installing Helm via Homebrew...${NC}"
            if command -v brew >/dev/null 2>&1; then
                brew install helm
            else
                echo -e "${RED}Error: Homebrew not found. Please install Homebrew first:${NC}" >&2
                echo -e "${YELLOW}/bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\"${NC}" >&2
                echo -e "${YELLOW}Or install Helm manually: https://helm.sh/docs/intro/install/${NC}" >&2
                exit 1
            fi
            ;;
        *)
            echo -e "${RED}Error: Unsupported OS: ${OS}. Please install Helm manually.${NC}" >&2
            echo -e "${YELLOW}Visit: https://helm.sh/docs/intro/install/${NC}" >&2
            exit 1
            ;;
    esac
    
    # Verify installation
    if command -v helm >/dev/null 2>&1; then
        HELM_VERSION=$(helm version --short 2>/dev/null || echo "unknown")
        echo -e "${GREEN}✓ Helm installed successfully (${HELM_VERSION})${NC}\n"
    else
        echo -e "${RED}Error: Helm installation failed. Please install manually.${NC}" >&2
        exit 1
    fi
else
    HELM_VERSION=$(helm version --short 2>/dev/null || echo "unknown")
    echo -e "${GREEN}✓ Helm found (${HELM_VERSION})${NC}"
fi

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

# Step 2: Install ArgoCD (skip if already running)
echo -e "${YELLOW}Step 2: Checking ArgoCD installation...${NC}"
SKIP_ARGOCD_INSTALL=false

if kubectl get namespace "${ARGOCD_NAMESPACE}" &>/dev/null; then
    if helm list -n "${ARGOCD_NAMESPACE}" | grep -q "${ARGOCD_RELEASE_NAME}"; then
        # Check if ArgoCD server deployment exists and is ready
        if kubectl get deployment argocd-server -n "${ARGOCD_NAMESPACE}" &>/dev/null; then
            READY_REPLICAS=$(kubectl get deployment argocd-server -n "${ARGOCD_NAMESPACE}" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
            if [ "${READY_REPLICAS}" -ge "1" ]; then
                echo -e "${GREEN}✓ ArgoCD already installed and running. Skipping installation/upgrade.${NC}\n"
                SKIP_ARGOCD_INSTALL=true
            else
                echo -e "${YELLOW}ArgoCD installed but not ready. Waiting for it to be ready...${NC}"
                kubectl wait --for=condition=available \
                    --timeout=60s \
                    deployment/argocd-server \
                    -n "${ARGOCD_NAMESPACE}" 2>/dev/null && {
                    echo -e "${GREEN}✓ ArgoCD is ready${NC}\n"
                    SKIP_ARGOCD_INSTALL=true
                } || {
                    echo -e "${YELLOW}ArgoCD not ready yet. Will upgrade to ensure it's working...${NC}"
                    SKIP_ARGOCD_INSTALL=false
                }
            fi
        else
            echo -e "${YELLOW}ArgoCD Helm release found but deployment missing. Installing...${NC}"
            SKIP_ARGOCD_INSTALL=false
        fi
    else
        echo -e "${YELLOW}Namespace exists but ArgoCD not found. Installing...${NC}"
        SKIP_ARGOCD_INSTALL=false
    fi
else
    echo -e "${YELLOW}Installing ArgoCD for the first time...${NC}"
    SKIP_ARGOCD_INSTALL=false
fi

if [ "${SKIP_ARGOCD_INSTALL}" = "false" ]; then
    if helm list -n "${ARGOCD_NAMESPACE}" 2>/dev/null | grep -q "${ARGOCD_RELEASE_NAME}"; then
        echo -e "${YELLOW}Upgrading ArgoCD...${NC}"
        helm upgrade "${ARGOCD_RELEASE_NAME}" argo/argo-cd \
            --namespace "${ARGOCD_NAMESPACE}" \
            --create-namespace \
            --wait \
            --timeout 10m
    else
        echo -e "${YELLOW}Installing ArgoCD...${NC}"
        helm install "${ARGOCD_RELEASE_NAME}" argo/argo-cd \
            --namespace "${ARGOCD_NAMESPACE}" \
            --create-namespace \
            --wait \
            --timeout 10m
    fi
    echo -e "${GREEN}✓ ArgoCD installed${NC}\n"
    
    # Wait for ArgoCD to be ready
    echo -e "${YELLOW}Waiting for ArgoCD to be ready...${NC}"
    kubectl wait --for=condition=available \
        --timeout=300s \
        deployment/argocd-server \
        -n "${ARGOCD_NAMESPACE}" || {
        echo -e "${RED}Error: ArgoCD server did not become ready in time${NC}" >&2
        exit 1
    }
    echo -e "${GREEN}✓ ArgoCD is ready${NC}\n"
fi

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
echo -e "${YELLOW}Current repoURL placeholder: https://github.com/coolsaigit/multipass.git${NC}\n"

# Step 7: Create bootstrap Application
echo -e "${YELLOW}Step 7: Creating bootstrap Application...${NC}"
if [ -f "${REPO_ROOT}/gitops/argo/apps/argocd-bootstrap.yaml" ]; then
    kubectl apply -f "${REPO_ROOT}/gitops/argo/apps/argocd-bootstrap.yaml"
    echo -e "${GREEN}✓ Bootstrap Application created${NC}"
    echo -e "${YELLOW}   (Will sync automatically in background - no need to wait)${NC}\n"
else
    echo -e "${YELLOW}Bootstrap Application file not found, skipping...${NC}\n"
fi

# Step 8: Create Istio ApplicationSet (Wave 1 - before App of Apps)
echo -e "${YELLOW}Step 8: Creating Istio ApplicationSet (infrastructure)...${NC}"
if [ -f "${REPO_ROOT}/gitops/argo/apps/istio-appset.yaml" ]; then
    kubectl apply -f "${REPO_ROOT}/gitops/argo/apps/istio-appset.yaml"
    echo -e "${GREEN}✓ Istio ApplicationSet created${NC}\n"
    echo -e "${YELLOW}Istio will deploy in sync-wave 1 (before other applications)${NC}\n"
else
    echo -e "${YELLOW}Istio ApplicationSet file not found, skipping...${NC}\n"
fi

# Step 9: Create App of Apps
echo -e "${YELLOW}Step 9: Creating App of Apps...${NC}"
if [ -f "${REPO_ROOT}/gitops/argo/apps/app-of-apps.yaml" ]; then
    kubectl apply -f "${REPO_ROOT}/gitops/argo/apps/app-of-apps.yaml"
    echo -e "${GREEN}✓ App of Apps created${NC}"
    echo -e "${YELLOW}   (Will sync automatically in background - no need to wait)${NC}\n"
else
    echo -e "${YELLOW}App of Apps file not found, skipping...${NC}\n"
fi

# Summary
echo -e "${GREEN}=== Bootstrap Complete ===${NC}\n"
echo -e "ArgoCD is installed and configured."
echo -e "Applications will be deployed automatically via GitOps.\n"
echo -e "${YELLOW}Next steps:${NC}"
echo -e "1. Wait for Istio to deploy (check: kubectl get pods -n istio-system)"
echo -e "2. Show all service endpoints: ${GREEN}./scripts/show-endpoints.sh${NC}"
echo -e "3. Access services via Istio Gateway (no port-forward needed!)"
if [ -n "${ARGOCD_PASSWORD}" ]; then
    echo -e "4. ArgoCD credentials: admin / ${ARGOCD_PASSWORD}"
fi
echo -e "\n${GREEN}All done! 🚀${NC}"
echo -e "${YELLOW}Run './scripts/show-endpoints.sh' to see all service URLs${NC}"

