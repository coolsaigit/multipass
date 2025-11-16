#!/bin/bash
set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo -e "${BLUE}=== Migrate to GitOps ===${NC}\n"

# Step 1: Check repoURL
echo -e "${YELLOW}Step 1: Checking Git repository configuration...${NC}"
REPO_URL=$(grep -h "repoURL:" "${REPO_ROOT}"/gitops/argo/apps/*.yaml | head -1 | awk '{print $2}' | tr -d '"')

if [[ "$REPO_URL" == *"your-org"* ]] || [[ "$REPO_URL" == *"placeholder"* ]]; then
    echo -e "${RED}⚠️  WARNING: Repository URL is still a placeholder!${NC}"
    echo -e "${YELLOW}Current repoURL: $REPO_URL${NC}"
    echo ""
    read -p "Enter your Git repository URL (or press Enter to skip): " -r NEW_REPO_URL
    echo ""
    
    if [ -n "$NEW_REPO_URL" ]; then
        echo -e "${YELLOW}Updating repository URLs...${NC}"
        find "${REPO_ROOT}"/gitops/argo/apps -name "*.yaml" -exec sed -i '' "s|repoURL:.*|repoURL: $NEW_REPO_URL|g" {} \;
        echo -e "${GREEN}✓ Repository URLs updated${NC}\n"
    else
        echo -e "${YELLOW}Skipping repository URL update. Please update manually before running bootstrap.${NC}\n"
    fi
else
    echo -e "${GREEN}✓ Repository URL configured: $REPO_URL${NC}\n"
fi

# Step 2: Ask about cleanup
echo -e "${YELLOW}Step 2: Cleanup existing deployments${NC}"
echo -e "Do you want to clean up existing deployments before migrating to GitOps?${NC}"
echo -e "${YELLOW}Options:${NC}"
echo -e "  1. Clean up everything (recommended for fresh start)"
echo -e "  2. Clean up but preserve data (PVCs)"
echo -e "  3. Skip cleanup (keep existing deployments)"
echo ""
read -p "Enter choice (1/2/3): " -r CLEANUP_CHOICE
echo ""

case $CLEANUP_CHOICE in
    1)
        echo -e "${YELLOW}Running cleanup (all data will be deleted)...${NC}"
        "${REPO_ROOT}"/scripts/cleanup.sh
        ;;
    2)
        echo -e "${YELLOW}Running cleanup (preserving data)...${NC}"
        "${REPO_ROOT}"/scripts/cleanup.sh --preserve-data
        ;;
    3)
        echo -e "${YELLOW}Skipping cleanup.${NC}\n"
        ;;
    *)
        echo -e "${RED}Invalid choice. Skipping cleanup.${NC}\n"
        ;;
esac

# Step 3: Run bootstrap
echo -e "${YELLOW}Step 3: Deploying via GitOps${NC}"
echo -e "Ready to run bootstrap script? This will install ArgoCD and deploy all applications.${NC}"
read -p "Continue? (yes/no): " -r
echo ""

if [[ $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
    echo -e "${GREEN}Running bootstrap script...${NC}\n"
    "${REPO_ROOT}"/scripts/bootstrap.sh
else
    echo -e "${YELLOW}Bootstrap cancelled. Run manually with: ./scripts/bootstrap.sh${NC}\n"
fi

echo -e "${GREEN}=== Migration Complete ===${NC}\n"

