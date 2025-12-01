# Complete Talos + Rancher + RKE2 Setup

This repository contains a complete local Kubernetes development platform.

## 🏗️ Architecture Overview

```
┌─────────────────────────────────────────────────────────┐
│  Management Cluster (Talos on Docker)                   │
│  ├── Kubernetes v1.33.0 (3 control plane nodes)         │
│  ├── Rancher Manager v2.12.3                           │
│  ├── Fleet GitOps                                       │
│  └── cert-manager                                       │
│  Managed by: Bash scripts                              │
└─────────────────────────────────────────────────────────┘
                         │
                         │ manages
                         ▼
┌─────────────────────────────────────────────────────────┐
│  User/Downstream Clusters (RKE2)                        │
│  ├── Dev cluster                                        │
│  ├── Staging cluster                                    │
│  └── Production cluster                                 │
│  Managed by: Terraform                                  │
└─────────────────────────────────────────────────────────┘
```

## 📁 Repository Structure

```
multipass/
├── scripts/                    # Management cluster scripts
│   ├── talos-cluster.sh        # Create/manage Talos cluster
│   ├── install-rancher.sh      # Install Rancher Manager
│   ├── uninstall-rancher.sh    # Clean up Rancher
│   └── _out/                   # Generated configs
│       └── kubeconfig          # Management cluster access
│
├── terraform/                  # User cluster IaC
│   ├── README.md               # Terraform documentation
│   ├── quick-start.sh          # Interactive deployment
│   ├── dev/                    # Dev environment
│   │   ├── provider.tf         # Rancher2 provider
│   │   ├── variables.tf        # Configurable options
│   │   ├── main.tf             # RKE2 cluster definition
│   │   ├── outputs.tf          # Access commands
│   │   └── terraform.tfvars.example
│   ├── staging/                # Staging environment
│   └── production/             # Production environment
│
└── backup/                     # Old configs (archived)
```

## 🚀 Complete Workflow

### 1. Create Management Cluster (5 minutes)

```bash
cd scripts

# Create 3-node HA Talos cluster
./talos-cluster.sh create

# Check status
./talos-cluster.sh status
```

**Result:** 
- Talos cluster with 3 control plane nodes
- Kubernetes v1.33.0
- ~6GB RAM usage

### 2. Install Rancher Manager (5-7 minutes)

```bash
# Install Rancher
./install-rancher.sh

# Access Rancher UI (in separate terminal)
kubectl -n cattle-system port-forward svc/rancher 8443:443
```

**Open:** https://localhost:8443  
**Login:** admin / admin

**Result:**
- Rancher Manager running (3 replicas)
- Fleet GitOps enabled
- cert-manager installed
- Total memory: ~8-10GB

### 3. Create User Clusters with Terraform (10-20 minutes)

```bash
cd ../terraform

# Interactive deployment
./quick-start.sh

# Or manual
cd dev
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your Rancher API token
terraform init
terraform apply
```

**Result:**
- RKE2 cluster created via Rancher
- Monitoring enabled
- Projects and namespaces configured
- Kubeconfig generated

### 4. Access User Cluster

```bash
# Save kubeconfig
cd terraform/dev
terraform output -raw kube_config > ~/.kube/dev-rke2.yaml

# Use cluster
export KUBECONFIG=~/.kube/dev-rke2.yaml
kubectl get nodes
kubectl get pods -A
```

## 📝 Common Tasks

### Management Cluster

```bash
cd scripts

# Check status
./talos-cluster.sh status

# Get access info
./talos-cluster.sh info

# Delete cluster (frees 6GB RAM)
./talos-cluster.sh delete

# Uninstall Rancher
./uninstall-rancher.sh
```

### User Clusters

```bash
cd terraform/dev

# Create cluster
terraform apply

# Scale workers
# Edit terraform.tfvars: worker_count = 5
terraform apply

# Upgrade Kubernetes
# Edit terraform.tfvars: kubernetes_version = "v1.29.0+rke2r1"  
terraform apply

# Get kubeconfig
terraform output -raw kube_config > ~/.kube/my-cluster.yaml

# Destroy cluster
terraform destroy
```

## 🎯 Recommended Setup

### Local Development (Current)
```bash
# Management: Talos on Docker Desktop
./scripts/talos-cluster.sh create
./scripts/install-rancher.sh

# User clusters: Custom (VMs/bare metal)
cd terraform/dev
# Set: cloud_provider = "custom"
terraform apply
```

### Cloud Production
```bash
# Management: Still local Talos
# (Rancher can manage remote clusters)

# User clusters: AWS automated
cd terraform/production
# Set: cloud_provider = "aws"
# Configure AWS credentials
terraform apply
```

## 💡 Key Features

### Management Cluster (Bash)
✅ Fast setup/teardown (< 5 minutes)  
✅ No cloud costs (runs on Docker)  
✅ HA by default (3 control planes)  
✅ Rancher for multi-cluster management  
✅ Easy to destroy and recreate  

### User Clusters (Terraform)
✅ Infrastructure as Code  
✅ Version controlled  
✅ Repeatable deployments  
✅ Multi-environment support  
✅ Cloud provider agnostic  
✅ Rolling upgrades  

## 🔧 Configuration

### Management Cluster Settings
File: `scripts/talos-cluster.sh`
- Kubernetes version: `1.33.0`
- Control plane nodes: `3`
- Memory per node: `2GB`
- CPUs per node: `2`

### User Cluster Settings
File: `terraform/dev/terraform.tfvars`
- Kubernetes version: `v1.28.5+rke2r1`
- Control plane count: `3`
- Worker count: `3`
- CNI: `calico`
- Monitoring: `enabled`

## 📊 Resource Usage

| Component | CPU | Memory | Storage |
|-----------|-----|--------|---------|
| Talos Cluster (3 nodes) | 6 cores | 6GB | 20GB |
| Rancher Manager | 1 core | 2GB | 5GB |
| **Total Management** | **7 cores** | **8GB** | **25GB** |
| | | | |
| RKE2 Dev Cluster (custom) | Depends on VMs | Depends on VMs | Depends on VMs |
| RKE2 AWS Cluster | Depends on EC2 | Depends on EC2 | EBS volumes |

## 🐛 Troubleshooting

### Management Cluster Issues

**Cluster won't start:**
```bash
# Delete and recreate
./scripts/talos-cluster.sh delete
./scripts/talos-cluster.sh create
```

**Rancher not accessible:**
```bash
# Check pods
kubectl get pods -n cattle-system

# Restart port-forward
pkill -f "port-forward.*rancher"
kubectl -n cattle-system port-forward svc/rancher 8443:443
```

### Terraform Issues

**"Error: Unable to connect to Rancher":**
- Ensure Rancher is running
- Verify port-forward is active
- Check API token is valid

**"Cluster stuck in Provisioning":**
- For custom: Nodes not registered
- Check Rancher UI for detailed status
- Verify network connectivity

## 📚 Documentation

- Management cluster: `scripts/` directory
- User clusters: `terraform/README.md`
- Talos: https://www.talos.dev/
- Rancher: https://rancher.com/docs/
- RKE2: https://docs.rke2.io/

## 🎉 Success Criteria

After complete setup, you should have:

✅ Talos cluster with 3 nodes running  
✅ Rancher UI accessible at https://localhost:8443  
✅ Ability to create RKE2 clusters via Terraform  
✅ Kubeconfig for accessing clusters  
✅ Projects and namespaces configured  
✅ Monitoring enabled  

## 🔐 Security Notes

- Management cluster uses self-signed certs (OK for local dev)
- Never commit `terraform.tfvars` (contains secrets)
- Rotate Rancher API tokens regularly
- Use separate tokens per environment
- Consider Terraform Cloud for state management

## 🚦 Next Steps

1. ✅ Management cluster running
2. ✅ Rancher installed
3. ✅ Terraform configured
4. ⏭️ Create first user cluster
5. ⏭️ Deploy applications
6. ⏭️ Set up monitoring
7. ⏭️ Configure GitOps with Fleet

---

**You now have a complete Kubernetes platform!** 🎊

