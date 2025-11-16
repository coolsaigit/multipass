# Multipass GitOps Repository

Enterprise-grade deployment setup using **Helm** (vendor apps), **Kustomize** (custom apps), and **ArgoCD** (GitOps).

## Repository Structure

```
gitops/
├── argo/
│   ├── apps/                 # ArgoCD ApplicationSets (per app)
│   │   ├── argocd-bootstrap.yaml  # Bootstrap Application (self-management)
│   │   ├── istio-appset.yaml      # Istio service mesh (sync-wave: 1)
│   │   ├── istio-gateway-appset.yaml  # Istio Gateway/VirtualServices (sync-wave: 2)
│   │   ├── prometheus-appset.yaml # Prometheus monitoring (sync-wave: 2)
│   │   ├── grafana-appset.yaml    # Grafana visualization (sync-wave: 3)
│   │   ├── kiali-appset.yaml      # Kiali observability (sync-wave: 3)
│   │   ├── minio-appset.yaml      # ApplicationSet (generates apps for dev/staging/prod)
│   │   ├── redpanda-appset.yaml  # ApplicationSet (generates apps for dev/staging/prod)
│   │   ├── flink-appset.yaml      # ApplicationSet (generates apps for dev/staging/prod)
│   │   ├── starrocks-appset.yaml  # ApplicationSet (generates apps for dev/staging/prod)
│   │   ├── iceberg-appset.yaml   # ApplicationSet (generates apps for dev/staging/prod)
│   │   └── app-of-apps.yaml      # Root application (sync-wave: 2)
│   ├── projects/             # ArgoCD project-level RBAC & scoping
│   │   └── multipass-project.yaml
│   └── bootstrap/            # Install ArgoCD itself (optional)
│       └── argocd-install.yaml
│
├── helm/                     # Helm charts (all apps)
│   ├── argocd/              # ArgoCD installation chart
│   ├── istio/               # Istio service mesh
│   ├── prometheus/          # Prometheus monitoring
│   ├── grafana/             # Grafana visualization
│   ├── kiali/               # Kiali service mesh observability
│   ├── minio/
│   ├── redpanda/
│   ├── flink/
│   ├── starrocks/
│   └── iceberg/
│
├── istio/                    # Istio Gateway and VirtualServices
│   ├── gateway.yaml
│   ├── kustomization.yaml
│   └── virtualservices/
│       ├── argocd-vs.yaml
│       ├── redpanda-console-vs.yaml
│       ├── kiali-vs.yaml
│       └── grafana-vs.yaml
│
└── kustomize/
    └── overlays/             # Environment-specific Helm values overrides
        ├── dev/
        │   ├── istio/values-dev.yaml
        │   ├── prometheus/values-dev.yaml
        │   ├── grafana/values-dev.yaml
        │   ├── kiali/values-dev.yaml
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

### Infrastructure & Observability (Managed by ArgoCD)
- **Istio**: Service mesh for traffic management, security, and observability
  - Gateway: Ingress controller for all services
  - VirtualServices: Routing rules for ArgoCD, Redpanda Console, Grafana, Kiali
- **Prometheus**: Metrics collection and alerting
- **Grafana**: Visualization and dashboards (pre-configured with Prometheus and Istio dashboards)
- **Kiali**: Service mesh observability and management UI

### Application Helm Charts
- **MinIO**: S3-compatible object storage
- **Redpanda**: Kafka-compatible streaming platform
- **Flink**: Stream processing engine
- **StarRocks**: OLAP database
- **Iceberg**: Data lake format with REST catalog and Trino query engine

All apps use Helm charts with environment-specific values files in `kustomize/overlays/{env}/{app}/values-{env}.yaml`

### Deployment Order (Sync Waves)
1. **Wave 0**: ArgoCD project (bootstrap)
2. **Wave 1**: Istio service mesh (infrastructure)
3. **Wave 2**: Istio Gateway/VirtualServices, Prometheus, App of Apps
4. **Wave 3**: Grafana, Kiali, Applications

### ArgoCD (GitOps)
- **App of Apps Pattern**: Single root application manages all child applications
- **ApplicationSets**: Enterprise-grade pattern for multi-environment deployments (used for ALL apps)
- **Project-based RBAC**: Separate admin and developer roles
- **Automated Sync**: Self-healing and automatic synchronization
- **Environment-specific values**: All Helm apps use environment-specific values files

## Prerequisites

1. **Kubernetes Cluster** (k3s, EKS, GKE, AKS, etc.)
2. **kubectl** configured to access your cluster
3. **Helm** v3.x (auto-installed by bootstrap script on macOS/Linux if missing)
4. **kustomize** CLI (optional, for local testing)

**Note**: 
- ArgoCD will be installed automatically by the bootstrap script
- Helm will be auto-installed if missing (requires Homebrew on macOS, or sudo access on Linux)

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
# Deploy infrastructure and observability first
kubectl apply -f gitops/argo/apps/istio-appset.yaml
kubectl apply -f gitops/argo/apps/istio-gateway-appset.yaml
kubectl apply -f gitops/argo/apps/prometheus-appset.yaml
kubectl apply -f gitops/argo/apps/grafana-appset.yaml
kubectl apply -f gitops/argo/apps/kiali-appset.yaml

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

### Access Services via Istio Ingress

After Istio is deployed, all services are accessible via the Istio Gateway (no port-forward needed!):

**Quick Access - Show All Endpoints:**
```bash
./scripts/show-endpoints.sh
```

This script will:
- Show the Istio Gateway IP/address
- Display all service URLs
- Provide commands to access each service
- Show how to update `/etc/hosts` for easy access

**Service URLs** (via Istio Gateway):
- **ArgoCD**: `http://argocd.local`
- **Redpanda Console**: `http://redpanda-console.local`
- **Grafana**: `http://grafana.local`
- **Kiali**: `http://kiali.local`

**Important Setup Steps**:

1. **Configure ArgoCD for Insecure Mode** (required when behind Istio):
   ```bash
   kubectl patch configmap argocd-cmd-params-cm -n argocd --type merge -p '{"data":{"server.insecure":"true"}}'
   kubectl rollout restart deployment argocd-server -n argocd
   ```
   Or apply the ConfigMap from GitOps:
   ```bash
   kubectl apply -f gitops/istio/argocd-config/configmap.yaml
   kubectl rollout restart deployment argocd-server -n argocd
   ```

2. **Access via Port-Forward** (if LoadBalancer not available):
   
   **Recommended: Use unified access script** (handles all services via single port-forward):
   ```bash
   ./scripts/access-all-services.sh
   ```
   This script:
   - Starts a single port-forward to Istio Gateway (port 8080)
   - Provides access to ALL services via hostname routing
   - Avoids port conflicts (ArgoCD and Redpanda both use 8080 internally, but accessed via Gateway)
   
   **Manual port-forward:**
   ```bash
   kubectl port-forward svc/istio-ingressgateway -n istio-system 8080:80
   ```
   Then access: `http://localhost:8080` with Host header `argocd.local` or use:
   ```bash
   curl -H "Host: argocd.local" http://localhost:8080
   ```
   
   **Important**: Always use Istio Gateway for access. Do NOT port-forward directly to individual services (ArgoCD or Redpanda Console) as they both use port 8080 internally and would conflict.

3. **Update /etc/hosts** (for local access):
   ```bash
   # Get Istio Gateway IP
   ISTIO_IP=$(kubectl get svc istio-ingressgateway -n istio-system -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
   # If no LoadBalancer, use port-forward method above
   
   # Add to /etc/hosts
   echo "$ISTIO_IP argocd.local redpanda-console.local grafana.local kiali.local" | sudo tee -a /etc/hosts
   ```

### Access ArgoCD UI

**Via Istio Gateway (Recommended):**
```bash
# Use the show-endpoints script
./scripts/show-endpoints.sh

# Or access directly
# Add to /etc/hosts: <GATEWAY_IP> argocd.local
# Then open: http://argocd.local
```

**Direct Access (Bypass Istio - if needed):**
```bash
# Port forward to access ArgoCD UI directly
kubectl port-forward svc/argocd-server -n argocd 8443:443

# Get admin password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

Access ArgoCD at: https://localhost:8443 (username: `admin`)

**Note**: ArgoCD must be configured for insecure mode when behind Istio. This is handled automatically by the `argocd-config/configmap.yaml` in the Istio Gateway ApplicationSet.

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
- `gitops/helm/istio/values.yaml`
- `gitops/helm/prometheus/values.yaml`
- `gitops/helm/grafana/values.yaml`
- `gitops/helm/kiali/values.yaml`
- `gitops/helm/minio/values.yaml`
- `gitops/helm/redpanda/values.yaml`
- `gitops/helm/flink/values.yaml`
- `gitops/helm/starrocks/values.yaml`
- `gitops/helm/iceberg/values.yaml`

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

## Observability Stack

### Prometheus
- **Metrics Collection**: Collects metrics from all services and Istio
- **Retention**: 30 days (production), 7 days (dev)
- **Storage**: Persistent volumes for metrics data
- **Access**: Via Grafana dashboards

### Grafana
- **Pre-configured Dashboards**: 
  - Istio Service Dashboard
  - Istio Workload Dashboard
  - General Istio Dashboard
- **Data Sources**: Prometheus (default)
- **Access**: `http://grafana.local` via Istio Gateway (default: admin/admin)

### Kiali
- **Service Mesh Visualization**: Interactive graph of service mesh topology
- **Traffic Management**: View and manage traffic flows
- **Metrics Integration**: Connected to Prometheus
- **Access**: `http://kiali.local` via Istio Gateway

## Best Practices

1. **Never commit secrets**: Use Sealed Secrets, External Secrets Operator, or Vault
2. **Use environment-specific overlays**: Keep base configurations generic
3. **Enable automated sync for dev/staging**: Manual approval for production
4. **Version control everything**: All manifests should be in Git
5. **Use App of Apps pattern**: Simplifies management of multiple applications
6. **Use ApplicationSets for multi-environment apps**: Reduces duplication and scales better
7. **Regular sync policies**: Configure retry and backoff strategies
8. **Istio for ingress**: Use Istio Gateway instead of port-forwarding for production access
9. **Observability first**: Deploy monitoring (Prometheus/Grafana) before applications
10. **Service mesh benefits**: Leverage Istio for traffic management, security, and observability

## Troubleshooting

### Cannot Access Services via Istio Gateway

**Issue**: `http://argocd.local` not accessible

**Solutions**:

1. **Verify Istio is deployed**:
   ```bash
   kubectl get pods -n istio-system
   kubectl get svc istio-ingressgateway -n istio-system
   ```

2. **Check Gateway and VirtualService**:
   ```bash
   kubectl get gateway -n istio-system
   kubectl get virtualservice -A
   ```

3. **Verify ArgoCD is in insecure mode**:
   ```bash
   kubectl get configmap argocd-cmd-params-cm -n argocd -o yaml | grep insecure
   # Should show: server.insecure: "true"
   ```
   If not set, apply:
   ```bash
   kubectl apply -f gitops/istio/argocd-config/configmap.yaml
   kubectl rollout restart deployment argocd-server -n argocd
   ```

4. **Test with port-forward**:
   ```bash
   kubectl port-forward svc/istio-ingressgateway -n istio-system 8080:80
   curl -H "Host: argocd.local" http://localhost:8080
   ```

5. **Check Istio Gateway logs**:
   ```bash
   kubectl logs -n istio-system -l istio=ingressgateway --tail=50
   ```

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

