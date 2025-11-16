# Bootstrap Scripts

## migrate-to-gitops.sh (Recommended)

**Complete migration script** that handles the entire process:
1. Checks/updates Git repository URL
2. Cleans up existing deployments (optional)
3. Runs bootstrap to deploy via GitOps

```bash
./scripts/migrate-to-gitops.sh
```

## cleanup.sh

Cleans up existing deployments before migrating to GitOps.

```bash
# Clean up everything (including data)
./scripts/cleanup.sh

# Clean up but preserve data (PVCs)
./scripts/cleanup.sh --preserve-data
```

## bootstrap.sh

Zero-touch deployment script that automates the entire GitOps setup.

### Usage

```bash
./scripts/bootstrap.sh
```

### What it does

1. **Checks prerequisites**: Verifies kubectl and helm are installed
2. **Adds ArgoCD Helm repo**: Adds the official ArgoCD Helm repository
3. **Installs ArgoCD**: Installs ArgoCD using Helm
4. **Waits for readiness**: Ensures ArgoCD is fully operational
5. **Retrieves admin password**: Gets the initial admin password
6. **Creates ArgoCD project**: Applies the multipass project configuration
7. **Creates bootstrap Application**: Sets up ArgoCD self-management
8. **Creates App of Apps**: Triggers deployment of all applications

### Requirements

- `kubectl` configured to access your cluster
- `helm` v3.x installed
- Cluster with sufficient resources

### Output

The script will:
- Display progress for each step
- Show the ArgoCD admin password
- Provide next steps for accessing ArgoCD UI

### Troubleshooting

If the script fails:
1. Check cluster connectivity: `kubectl cluster-info`
2. Verify Helm is installed: `helm version`
3. Check ArgoCD installation: `kubectl get pods -n argocd`
4. View logs: `kubectl logs -n argocd -l app.kubernetes.io/name=argocd-server`

