# Multipass Scripts

## Deployment Scripts

### migrate-to-gitops.sh (Recommended)

**Complete migration script** that handles the entire process:
1. Checks/updates Git repository URL
2. Cleans up existing deployments (optional)
3. Runs bootstrap to deploy via GitOps

```bash
./scripts/migrate-to-gitops.sh
```

### cleanup.sh

Cleans up existing deployments before migrating to GitOps.

```bash
# Clean up everything (including data)
./scripts/cleanup.sh

# Clean up but preserve data (PVCs)
./scripts/cleanup.sh --preserve-data
```

### bootstrap.sh

Zero-touch deployment script that automates the entire GitOps setup.

```bash
./scripts/bootstrap.sh
```

**What it does:**
1. Checks prerequisites (kubectl, auto-installs Helm if needed)
2. Adds ArgoCD Helm repo
3. Installs ArgoCD
4. Creates ArgoCD project
5. Creates bootstrap Application
6. Creates App of Apps

## Access Scripts

### fix-endpoints.sh

**Single script to fix and access all endpoints.**

```bash
./scripts/fix-endpoints.sh
```

**What it does:**
- Applies Istio Gateway if missing
- Applies all VirtualServices
- Configures ArgoCD for insecure mode
- Starts port-forward to Istio Gateway
- Tests all 9 endpoints
- Shows all service URLs and access information
- Displays ArgoCD credentials
- Provides /etc/hosts setup commands

## Quick Reference

| Script | Purpose | When to Use |
|--------|---------|-------------|
| `migrate-to-gitops.sh` | Full migration | Setting up from scratch |
| `bootstrap.sh` | Deploy via GitOps | After migration or fresh install |
| `fix-endpoints.sh` | Fix and access endpoints | Endpoints not working or need access |
| `cleanup.sh` | Clean up deployments | Before migration or reset |

