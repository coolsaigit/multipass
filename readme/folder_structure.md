gitops/
├── argo/
│   ├── apps/                 # ArgoCD Application manifests (per app)
│   │   ├── starrocks.yaml
│   │   ├── flink.yaml
│   │   ├── minio.yaml
│   │   ├── my-service.yaml
│   │   └── ...
│   ├── projects/             # ArgoCD project-level RBAC & scoping
│   │   └── platform-project.yaml
│   └── bootstrap/            # Install ArgoCD itself (optional)
│       └── argocd-install.yaml
│
├── helm/                     # Vendor-provided Helm charts OR custom charts
│   ├── starrocks/            # (optional if using vendor chart directly)
│   ├── minio/
│   ├── my-service/           # Your app as Helm chart (optional)
│   └── ...
│
├── kustomize/
│   ├── base/                 # Base manifests (cluster-agnostic)
│   │   ├── my-service/
│   │   │   ├── deployment.yaml
│   │   │   ├── service.yaml
│   │   │   ├── configmap.yaml
│   │   │   └── kustomization.yaml
│   │   ├── flink-operator/   # Base version if not deployed via Helm
│   │   └── ...
│   │
│   └── overlays/             # Environment-specific patches
│       ├── dev/
│       │   ├── my-service/
│       │   │   ├── kustomization.yaml
│       │   │   └── patch-resources.yaml
│       │   └── starrocks/
│       │       └── values-dev.yaml      # Overrides for Helm Chart
│       │
│       ├── staging/
│       │   ├── my-service/
│       │   └── starrocks/
│       │       └── values-staging.yaml
│       │
│       └── prod/
│           ├── my-service/
│           └── starrocks/
│               └── values-prod.yaml
│
└── clusters/                 # ArgoCD root ApplicationSets per cluster
    ├── dev/
    │   └── kustomization.yaml
    ├── staging/
    │   └── kustomization.yaml
    └── prod/
        └── kustomization.yaml
