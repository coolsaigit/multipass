# Migration to GitOps - Step by Step Guide

## Current State

Based on cluster inspection, you currently have:
- ✅ **minio** - Running (1 pod)
- ✅ **redpanda** - Running (2 pods: redpanda + console)
- ✅ **flink** - Running (2 pods: jobmanager + taskmanager)
- ✅ **starrocks** - Running (2 pods: fe + be)
- ⚠️ **iceberg** - Running but Trino is in CrashLoopBackOff
- ❌ **argocd** - Not installed

## Migration Options

### Option 1: Automated Migration (Recommended)

Run the complete migration script that handles everything:

```bash
./scripts/migrate-to-gitops.sh
```

This script will:
1. ✅ Check/update Git repository URL
2. ✅ Clean up existing deployments (with options)
3. ✅ Deploy everything via GitOps

### Option 2: Manual Step-by-Step

#### Step 1: Update Git Repository URL

**IMPORTANT**: Before proceeding, update the repository URL in all Application files:

```bash
# Find all files that need updating
grep -r "coolsaigit/multipass" gitops/argo/apps/

# Replace with your actual repository URL
# Example: https://github.com/yourusername/multipass.git
find gitops/argo/apps -name "*.yaml" -exec sed -i '' 's|https://github.com/coolsaigit/multipass.git|YOUR_ACTUAL_REPO_URL|g' {} \;
```

Files to update:
- `gitops/argo/apps/argocd-bootstrap.yaml`
- `gitops/argo/apps/app-of-apps.yaml`
- `gitops/argo/apps/minio-appset.yaml`
- `gitops/argo/apps/redpanda-appset.yaml`
- `gitops/argo/apps/flink-appset.yaml`
- `gitops/argo/apps/starrocks-appset.yaml`
- `gitops/argo/apps/iceberg-appset.yaml`

#### Step 2: Clean Up Existing Deployments

Choose one:

**Option A: Clean everything (fresh start)**
```bash
./scripts/cleanup.sh
```

**Option B: Clean but preserve data**
```bash
./scripts/cleanup.sh --preserve-data
```

**Option C: Manual cleanup**
```bash
# Delete all namespaces
kubectl delete namespace minio redpanda flink starrocks iceberg

# Or delete resources but keep namespaces
kubectl delete all --all -n minio
kubectl delete all --all -n redpanda
kubectl delete all --all -n flink
kubectl delete all --all -n starrocks
kubectl delete all --all -n iceberg
```

#### Step 3: Deploy via GitOps

```bash
./scripts/bootstrap.sh
```

This will:
1. Install ArgoCD
2. Create ArgoCD project
3. Deploy all applications automatically

## What Happens After Migration

Once bootstrap completes:

1. **ArgoCD** will be installed and running
2. **ApplicationSets** will generate Applications for each environment:
   - `minio-dev`, `minio-staging`, `minio-prod`
   - `redpanda-dev`, `redpanda-staging`, `redpanda-prod`
   - `flink-dev`, `flink-staging`, `flink-prod`
   - `starrocks-dev`, `starrocks-staging`, `starrocks-prod`
   - `iceberg-dev`, `iceberg-staging`, `iceberg-prod`

3. **Applications** will deploy automatically based on:
   - Base Helm values: `helm/{app}/values.yaml`
   - Environment overrides: `kustomize/overlays/{env}/{app}/values-{env}.yaml`

## Verification

After migration, verify everything:

```bash
# Check ArgoCD
kubectl get pods -n argocd

# Check Applications
kubectl get applications -n argocd

# Check ApplicationSets
kubectl get applicationsets -n argocd

# Check deployed apps
kubectl get pods -n minio
kubectl get pods -n redpanda
kubectl get pods -n flink
kubectl get pods -n starrocks
kubectl get pods -n iceberg
```

## Access ArgoCD UI

```bash
# Port forward
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Get admin password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

Access: https://localhost:8080 (username: `admin`)

## Troubleshooting

### Applications not syncing
```bash
# Check application status
kubectl get applications -n argocd
kubectl describe application <app-name> -n argocd

# Force sync
argocd app sync <app-name>
```

### Trino still crashing
- Check if MinIO is running first (Trino depends on MinIO)
- Verify MinIO credentials in Iceberg values
- Check Trino logs: `kubectl logs -n iceberg deployment/trino`

### Repository URL issues
- Ensure all Application files have the correct repoURL
- Verify the repository is accessible
- Check ArgoCD repository connection in UI

## Notes

- **Data Preservation**: Use `--preserve-data` flag if you want to keep existing PVCs
- **Git Repository**: Must be accessible by ArgoCD (public or configured with credentials)
- **Dependencies**: MinIO should deploy first (Iceberg depends on it)
- **Environments**: By default, all environments (dev/staging/prod) will be deployed. You can modify cluster kustomizations to deploy only specific environments.

