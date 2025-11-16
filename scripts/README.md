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

**Main script to fix and test all endpoints.** Use this when endpoints are not working.

```bash
./scripts/fix-endpoints.sh
```

**What it does:**
- Applies Istio Gateway if missing
- Applies all VirtualServices
- Configures ArgoCD for insecure mode
- Starts port-forward to Istio Gateway
- Tests all 9 endpoints

### access-all-services.sh

**Access all services via Istio Gateway.** Use this when everything is working and you just need to access services.

```bash
./scripts/access-all-services.sh
```

**What it does:**
- Starts port-forward to Istio Gateway
- Shows all service URLs and access information
- Displays ArgoCD credentials

### show-endpoints.sh

**Show endpoint information without starting port-forward.** Use this to see how to access services.

```bash
./scripts/show-endpoints.sh
```

**What it does:**
- Shows Istio Gateway IP/address
- Displays all service URLs
- Provides /etc/hosts setup commands
- Shows ArgoCD credentials

## Quick Reference

| Script | Purpose | When to Use |
|--------|---------|-------------|
| `migrate-to-gitops.sh` | Full migration | Setting up from scratch |
| `bootstrap.sh` | Deploy via GitOps | After migration or fresh install |
| `fix-endpoints.sh` | Fix broken endpoints | Endpoints not working |
| `access-all-services.sh` | Access services | Everything working, need access |
| `show-endpoints.sh` | Show endpoint info | Need to see access URLs |
| `cleanup.sh` | Clean up deployments | Before migration or reset |

