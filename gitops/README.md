# Multipass GitOps Repository

Enterprise-grade deployment setup using **Helm** (vendor apps), **Kustomize** (custom apps), and **ArgoCD** (GitOps).

## Repository Structure

```
gitops/
├── argo/
│   ├── apps/                 # ArgoCD ApplicationSets (per app)
│   │   ├── argocd-bootstrap.yaml  # Bootstrap Application (self-management)
│   │   ├── minio-appset.yaml      # ApplicationSet (generates apps for dev/staging/prod)
│   │   ├── redpanda-appset.yaml  # ApplicationSet (generates apps for dev/staging/prod)
│   │   ├── flink-appset.yaml      # ApplicationSet (generates apps for dev/staging/prod)
│   │   ├── starrocks-appset.yaml  # ApplicationSet (generates apps for dev/staging/prod)
│   │   ├── iceberg-appset.yaml   # ApplicationSet (generates apps for dev/staging/prod)
│   │   └── app-of-apps.yaml
│   ├── projects/             # ArgoCD project-level RBAC & scoping
│   │   └── multipass-project.yaml
│   └── bootstrap/            # Install ArgoCD itself (optional)
│       └── argocd-install.yaml
│
├── helm/                     # Helm charts (all apps)
│   ├── argocd/              # ArgoCD installation chart
│   ├── minio/
│   ├── redpanda/
│   ├── flink/
│   ├── starrocks/
│   └── iceberg/
│
└── kustomize/
    └── overlays/             # Environment-specific Helm values overrides
        ├── dev/
        │   ├── minio/values-dev.yaml
        │   ├── redpanda/values-dev.yaml
        │   ├── flink/values-dev.yaml
        │   ├── starrocks/values-dev.yaml
        │   └── iceberg/values-dev.yaml
        ├── staging/
        │   ├── minio/values-staging.yaml
        │   ├── redpanda/values-staging.yaml
        │   ├── flink/values-staging.yaml
        │   ├── starrocks/values-staging.yaml
        │   └── iceberg/values-staging.yaml
        └── prod/
            ├── minio/values-prod.yaml
            ├── redpanda/values-prod.yaml
            ├── flink/values-prod.yaml
            ├── starrocks/values-prod.yaml
            └── iceberg/values-prod.yaml
│
└── clusters/                 # ArgoCD root ApplicationSets per cluster
    ├── dev/
    │   └── kustomization.yaml
    ├── staging/
    │   └── kustomization.yaml
    └── prod/
        └── kustomization.yaml
```

## Architecture Overview

### Helm Charts (All Apps)
- **MinIO**: S3-compatible object storage
- **Redpanda**: Kafka-compatible streaming platform
- **Flink**: Stream processing engine
- **StarRocks**: OLAP database
- **Iceberg**: Data lake format with REST catalog and Trino query engine

All apps use Helm charts with environment-specific values files in `kustomize/overlays/{env}/{app}/values-{env}.yaml`

### ArgoCD (GitOps)
- **App of Apps Pattern**: Single root application manages all child applications
- **ApplicationSets**: Enterprise-grade pattern for multi-environment deployments (used for ALL apps)
- **Project-based RBAC**: Separate admin and developer roles
- **Automated Sync**: Self-healing and automatic synchronization
- **Environment-specific values**: All Helm apps use environment-specific values files

## Prerequisites

1. **Kubernetes Cluster** (k3s, EKS, GKE, AKS, etc.)
2. **kubectl** configured to access your cluster
3. **Helm** v3.x installed (for bootstrap script)
4. **kustomize** CLI (optional, for local testing)

**Note**: ArgoCD will be installed automatically by the bootstrap script.

## Quick Start (Zero-Touch Bootstrap)

### Automated Bootstrap (Recommended)

Run the bootstrap script for zero-touch deployment:

```bash
./scripts/bootstrap.sh
```

This script will:
1. ✅ Check prerequisites (kubectl, helm)
2. ✅ Add ArgoCD Helm repository
3. ✅ Install ArgoCD
4. ✅ Wait for ArgoCD to be ready
5. ✅ Create ArgoCD project
6. ✅ Create bootstrap Application (self-management)
7. ✅ Create App of Apps (deploys all applications)

**That's it!** All applications will deploy automatically via GitOps.

### Manual Installation (Alternative)

If you prefer manual installation:

#### 1. Install ArgoCD

```bash
# Option 1: Using Helm (recommended)
helm repo add argo https://argoproj.github.io/argo-helm
helm install argocd argo/argo-cd --namespace argocd --create-namespace

# Option 2: Using kubectl
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

#### 2. Configure Git Repository

Update the `repoURL` in all ArgoCD Application manifests:
- `gitops/argo/apps/*.yaml`
- Replace `https://github.com/coolsaigit/multipass.git` with your actual repository URL

#### 3. Create ArgoCD Project

```bash
kubectl apply -f gitops/argo/projects/multipass-project.yaml
```

#### 4. Deploy Applications

**Option A: App of Apps Pattern (Recommended)**
```bash
kubectl apply -f gitops/argo/apps/app-of-apps.yaml
```

**Option B: Individual ApplicationSets**
```bash
# Deploy all apps via ApplicationSets (generates Applications for all environments)
kubectl apply -f gitops/argo/apps/minio-appset.yaml
kubectl apply -f gitops/argo/apps/redpanda-appset.yaml
kubectl apply -f gitops/argo/apps/flink-appset.yaml
kubectl apply -f gitops/argo/apps/starrocks-appset.yaml
kubectl apply -f gitops/argo/apps/iceberg-appset.yaml
```

**Option C: Cluster-specific Deployment**
```bash
# Deploy all apps for a specific environment
kubectl apply -k gitops/clusters/dev/
```

### Access ArgoCD UI

```bash
# Port forward to access ArgoCD UI
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Get admin password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

Access ArgoCD at: https://localhost:8080 (username: `admin`)

## Local Testing (Without ArgoCD)

### Deploy Helm Charts Directly

```bash
# MinIO
helm install minio gitops/helm/minio --namespace minio --create-namespace

# Redpanda
helm install redpanda gitops/helm/redpanda --namespace redpanda --create-namespace

# Flink
helm install flink gitops/helm/flink --namespace flink --create-namespace

# StarRocks
helm install starrocks gitops/helm/starrocks --namespace starrocks --create-namespace
```

### Deploy Kustomize Manifests

```bash
# Development environment
kubectl apply -k gitops/kustomize/overlays/dev/iceberg/

# Staging environment
kubectl apply -k gitops/kustomize/overlays/staging/iceberg/

# Production environment
kubectl apply -k gitops/kustomize/overlays/prod/iceberg/
```

## Environment-Specific Configurations

### Development
- Minimal resources
- Single replica deployments
- Fast iteration cycles

### Staging
- Medium resources
- 2 replicas for high availability
- Production-like configuration

### Production
- Full resources
- 3+ replicas for high availability
- Manual sync approval (prune: false)

## Customization

### Modifying Helm Values

**Base values** (common across all environments):
- `gitops/helm/minio/values.yaml`
- `gitops/helm/redpanda/values.yaml`
- `gitops/helm/flink/values.yaml`
- `gitops/helm/starrocks/values.yaml`

**Environment-specific overrides**:
- `gitops/kustomize/overlays/{dev,staging,prod}/{app}/values-{env}.yaml`
- These override base values for specific environments

### Modifying Environment-Specific Values

Edit the environment-specific values files:
- `gitops/kustomize/overlays/{dev,staging,prod}/{app}/values-{env}.yaml`
- These override base values from `helm/{app}/values.yaml`

### Adding New Applications

1. **Create Helm chart**: 
   - Create chart in `gitops/helm/{app-name}/`
   - Include base `values.yaml` with default configuration
2. **Create environment-specific values**: 
   - Create values files in `gitops/kustomize/overlays/{dev,staging,prod}/{app-name}/values-{env}.yaml`
   - These override base values for each environment
3. **Create ApplicationSet**: 
   - Create `gitops/argo/apps/{app-name}-appset.yaml`
   - Follow the pattern of existing ApplicationSets
4. **Update cluster configs**: 
   - Add ApplicationSet to `gitops/clusters/{env}/kustomization.yaml`

**Note**: All apps use Helm charts + ApplicationSets for consistency and scalability.

### ApplicationSets (Enterprise Pattern)

**All apps use ApplicationSets** for consistent, enterprise-grade multi-environment deployments:

- **Single definition** per app manages dev, staging, and prod
- **Automatic generation** of Applications per environment
- **Environment-specific configs** via generator elements
- **Scalable** - easy to add new environments

**All Apps** (minio, redpanda, flink, starrocks, iceberg):
- Each ApplicationSet generates: `{app}-dev`, `{app}-staging`, `{app}-prod`
- Each references environment-specific Helm values files from `overlays/{env}/{app}/values-{env}.yaml`
- Base values from `helm/{app}/values.yaml` + environment overrides

Example: The MinIO ApplicationSet generates:
- `minio-dev` → uses `helm/minio/values.yaml` + `overlays/dev/minio/values-dev.yaml`
- `minio-staging` → uses `helm/minio/values.yaml` + `overlays/staging/minio/values-staging.yaml`
- `minio-prod` → uses `helm/minio/values.yaml` + `overlays/prod/minio/values-prod.yaml` (manual approval)

Example: The Iceberg ApplicationSet generates:
- `iceberg-dev` → uses `helm/iceberg/values.yaml` + `overlays/dev/iceberg/values-dev.yaml`
- `iceberg-staging` → uses `helm/iceberg/values.yaml` + `overlays/staging/iceberg/values-staging.yaml`
- `iceberg-prod` → uses `helm/iceberg/values.yaml` + `overlays/prod/iceberg/values-prod.yaml` (manual approval)

## Best Practices

1. **Never commit secrets**: Use Sealed Secrets, External Secrets Operator, or Vault
2. **Use environment-specific overlays**: Keep base configurations generic
3. **Enable automated sync for dev/staging**: Manual approval for production
4. **Version control everything**: All manifests should be in Git
5. **Use App of Apps pattern**: Simplifies management of multiple applications
6. **Use ApplicationSets for multi-environment apps**: Reduces duplication and scales better
7. **Regular sync policies**: Configure retry and backoff strategies

## Troubleshooting

### ArgoCD Application Not Syncing

```bash
# Check application status
kubectl get applications -n argocd

# View application details
kubectl describe application <app-name> -n argocd

# Force sync
argocd app sync <app-name>
```

### Helm Chart Issues

```bash
# Dry run to see what would be deployed
helm install <app-name> gitops/helm/<app-name> --dry-run --debug

# Check chart values
helm show values gitops/helm/<app-name>
```

### Kustomize Build Issues

```bash
# Build and preview
kubectl kustomize gitops/kustomize/overlays/dev/iceberg/

# Validate
kubectl kustomize gitops/kustomize/overlays/dev/iceberg/ | kubectl apply --dry-run=client -f -
```

## Resources

- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
- [Helm Documentation](https://helm.sh/docs/)
- [Kustomize Documentation](https://kustomize.io/)
- [GitOps Principles](https://www.gitops.tech/)

## License

[Your License Here]

