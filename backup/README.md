# Backup Directory

This directory contains the original Kubernetes YAML manifests that have been migrated to the GitOps structure.

## Migrated Files

- `flink.yaml` → Now managed via `gitops/helm/flink/`
- `minio.yaml` → Now managed via `gitops/helm/minio/`
- `redpanda.yaml` → Now managed via `gitops/helm/redpanda/`
- `starrocks.yaml` → Now managed via `gitops/helm/starrocks/`
- `iceberg.yaml` → Now managed via `gitops/kustomize/base/iceberg/`
- `iceberg-simple.yaml` → Simplified version, now in `gitops/kustomize/base/iceberg/`

## Migration Date

November 2024

## Notes

These files are kept for reference only. All deployments should now use:
- **Helm charts** for vendor apps (in `gitops/helm/`)
- **Kustomize** for custom apps (in `gitops/kustomize/`)
- **ArgoCD** for GitOps automation (in `gitops/argo/`)

See `gitops/README.md` for the new deployment process.

