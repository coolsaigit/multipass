# RKE2 Cluster Deployment with Terraform + Rancher

This directory contains Terraform configurations to create and manage RKE2 Kubernetes clusters through Rancher Manager.

## 📋 Prerequisites

1. **Rancher Manager Running**
   ```bash
   # Make sure Rancher is accessible
   cd ../scripts
   ./talos-cluster.sh status
   kubectl -n cattle-system port-forward svc/rancher 8443:443 &
   ```

2. **Rancher API Token**
   - Open Rancher UI: https://localhost:8443
   - Click on your user icon (top right) → Account & API Keys
   - Create API Key → Save the token

3. **Terraform Installed**
   ```bash
   brew install terraform
   ```

4. **kubectl Installed** (for cluster access)

## 🚀 Quick Start

### Step 1: Configure

```bash
cd terraform/dev

# Copy example configuration
cp terraform.tfvars.example terraform.tfvars

# Edit with your values
vim terraform.tfvars
```

**Required:** Set your Rancher API token:
```hcl
rancher_token = "token-xxxxx:xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
```

### Step 2: Choose Deployment Type

#### Option A: Local ARM Cluster (Multipass) ⭐ Recommended for Mac ARM

Best for: Local development on Mac ARM, testing RKE on ARM architecture

**Prerequisites:**
```bash
brew install --cask multipass
```

**Automated Workflow:**
```bash
cd terraform/dev

# 1. Create ARM Multipass VMs with Docker pre-installed
./multipass-rke-nodes.sh create

# 2. Configure Terraform (if not done already)
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars and set rancher_token

# 3. Create cluster in Rancher
terraform init
terraform apply

# 4. Register nodes with Rancher (automated)
./multipass-rke-nodes.sh register
```

**Manual Workflow:**
```bash
# 1. Create nodes
./multipass-rke-nodes.sh create

# 2. Check node status
./multipass-rke-nodes.sh status

# 3. After terraform apply, register nodes
terraform output -raw registration_command
./multipass-rke-nodes.sh register
```

**Configuration:**
```hcl
cloud_provider = "custom"
control_plane_count = 3  # Number of control plane VMs
worker_count = 3         # Number of worker VMs
```

**Customize VM resources:**
```bash
export CPU_CORES=4        # CPUs per VM (default: 2)
export MEMORY=8G         # Memory per VM (default: 4G)
export DISK=100G         # Disk per VM (default: 50G)
./multipass-rke-nodes.sh create
```

**Cleanup:**
```bash
./multipass-rke-nodes.sh delete
```

#### Option B: Custom Cluster (Bring Your Own Nodes)

Best for: Existing VMs, bare metal, other infrastructure

```hcl
cloud_provider = "custom"
```

**After `terraform apply`, run the registration command on each node:**
```bash
# Get the command
terraform output -raw registration_command

# Run on each node (as root)
ssh node1 'curl -fsSL https://localhost:8443/... | sudo bash'
ssh node2 'curl -fsSL https://localhost:8443/... | sudo bash'
ssh node3 'curl -fsSL https://localhost:8443/... | sudo bash'
```

#### Option C: AWS Cluster (Automated)

Best for: Production, cloud-based workloads

```hcl
cloud_provider = "aws"
aws_region     = "us-west-2"
aws_access_key = "AKIAXXXXXXXXXXXXXXXX"
aws_secret_key = "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
```

Nodes are automatically provisioned!

### Step 3: Deploy

```bash
# Initialize Terraform
terraform init

# Plan deployment
terraform plan

# Apply (create cluster)
terraform apply
```

**Deployment time:**
- Local ARM (Multipass): ~10-15 minutes (includes VM creation + registration)
- Custom cluster: ~5-10 minutes (after nodes registered)
- AWS cluster: ~15-20 minutes (includes VM provisioning)

### Step 4: Access Cluster

```bash
# Save kubeconfig
terraform output -raw kube_config > ~/.kube/dev-rke2-config

# Set as active config
export KUBECONFIG=~/.kube/dev-rke2-config

# Verify
kubectl get nodes
kubectl get pods -A
```

Or access from Rancher UI → Cluster Management → dev-rke2

## 📁 Directory Structure

```
terraform/
├── dev/
│   ├── provider.tf              # Rancher provider config
│   ├── variables.tf              # All configurable variables
│   ├── main.tf                  # RKE2 cluster resources
│   ├── outputs.tf               # Cluster info & access commands
│   ├── terraform.tfvars         # Your values (gitignored)
│   ├── terraform.tfvars.example # Template
│   └── multipass-rke-nodes.sh   # ARM Multipass node provisioning script
├── staging/
└── production/
```
<｜tool▁calls▁begin｜><｜tool▁call▁begin｜>
read_file

## ⚙️ Configuration Options

### Cluster Settings

| Variable | Description | Default |
|----------|-------------|---------|
| `cluster_name` | Name of the cluster | `dev-rke2` |
| `kubernetes_version` | K8s version | `v1.28.5+rke2r1` |
| `cloud_provider` | `custom` or `aws` | `custom` |

### Node Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `control_plane_count` | Number of control plane nodes | `3` |
| `worker_count` | Number of worker nodes | `3` |
| `instance_type` | AWS instance type | `t3.large` |

### Networking

| Variable | Description | Default |
|----------|-------------|---------|
| `enable_network_policy` | Enable Kubernetes NetworkPolicy | `true` |
| `cni` | CNI plugin (`calico`, `canal`, `cilium`) | `calico` |

### Features

| Variable | Description | Default |
|----------|-------------|---------|
| `enable_monitoring` | Enable Prometheus monitoring | `true` |

## 🔧 Common Operations

### View Cluster Info

```bash
terraform output
```

### Get Registration Command

```bash
# For custom clusters
terraform output -raw registration_command
```

### Get Kubeconfig

```bash
terraform output -raw kube_config > ~/.kube/my-cluster.yaml
export KUBECONFIG=~/.kube/my-cluster.yaml
kubectl get nodes
```

### Update Cluster

```bash
# Modify terraform.tfvars
vim terraform.tfvars

# Apply changes
terraform plan
terraform apply
```

### Scale Workers

```bash
# Edit terraform.tfvars
worker_count = 5

# Apply
terraform apply
```

### Upgrade Kubernetes

```bash
# Edit terraform.tfvars
kubernetes_version = "v1.29.0+rke2r1"

# Apply (rolling upgrade)
terraform apply
```

### Destroy Cluster

```bash
terraform destroy
```

**⚠️ Warning:** This deletes the entire cluster and all workloads!

## 📊 What Gets Created

### In Rancher:
- ✅ RKE2 Kubernetes cluster
- ✅ Default Project
- ✅ Applications namespace
- ✅ Resource quotas
- ✅ Monitoring (if enabled)

### In AWS (if using AWS):
- ✅ EC2 instances (control plane + workers)
- ✅ Security groups
- ✅ IAM instance profiles
- ✅ EBS volumes

## 🎯 Multi-Environment Setup

### Development
```bash
cd terraform/dev
terraform apply
```

### Staging
```bash
cd terraform/staging
# Copy and modify configs
terraform apply
```

### Production
```bash
cd terraform/production
# Copy and modify configs
terraform apply
```

## 🔐 Security Best Practices

1. **Never commit `terraform.tfvars`** (contains secrets)
   ```bash
   # Already in .gitignore
   echo "terraform.tfvars" >> .gitignore
   ```

2. **Use environment variables** (alternative to tfvars)
   ```bash
   export TF_VAR_rancher_token="token-xxxxx:xxxxx"
   export TF_VAR_aws_access_key="AKIAXXXXX"
   export TF_VAR_aws_secret_key="xxxxxxxx"
   terraform apply
   ```

3. **Use Terraform Cloud/Enterprise** for state management
   ```hcl
   terraform {
     backend "remote" {
       organization = "my-org"
       workspaces {
         name = "dev-rke2"
       }
     }
   }
   ```

## 🐛 Troubleshooting

### "Error: Unable to connect to Rancher"
- Ensure Rancher is running: `./scripts/talos-cluster.sh status`
- Port-forward is active: `kubectl -n cattle-system port-forward svc/rancher 8443:443`
- Token is valid (regenerate if needed)

### "Cluster stays in Provisioning state"
- For custom clusters: Nodes not registered yet
- Check Rancher UI for detailed errors
- Verify network connectivity

### "Nodes not joining"
- For custom clusters: Run registration command on nodes
- Check firewall rules (ports 6443, 9345, 2379-2380)
- Verify Ubuntu/RHEL nodes meet RKE2 requirements

### AWS Provisioning Errors
- Verify AWS credentials
- Check VPC/subnet configuration
- Ensure AMI availability in region

### Multipass/ARM Issues
- **"multipass: command not found"**: Install with `brew install --cask multipass`
- **VMs not starting**: Check Multipass daemon: `multipass list`
- **Docker not installed on nodes**: Run `./multipass-rke-nodes.sh prepare`
- **Registration fails**: Ensure Rancher port-forward is active and registration command is valid
- **ARM64 compatibility**: Multipass automatically uses ARM64 images on Apple Silicon Macs

## 📚 Additional Resources

- [RKE2 Documentation](https://docs.rke2.io/)
- [Rancher Documentation](https://rancher.com/docs/)
- [Terraform Rancher2 Provider](https://registry.terraform.io/providers/rancher/rancher2/latest/docs)

## 💡 Tips

1. **Start with custom cluster** for testing (faster, no cloud costs)
2. **Use separate state per environment** (dev, staging, prod)
3. **Enable monitoring** to track cluster health
4. **Set resource quotas** to prevent resource exhaustion
5. **Tag everything** for cost tracking (in cloud environments)

## 🎉 Success Criteria

After `terraform apply`, you should see:

```
Apply complete! Resources: 5 added, 0 changed, 0 destroyed.

Outputs:

access_instructions = <<-EOT

╔══════════════════════════════════════════════════════════════╗
║           RKE2 Cluster Created Successfully                  ║
╚══════════════════════════════════════════════════════════════╝

Cluster Name: dev-rke2
Kubernetes Version: v1.28.5+rke2r1
...
EOT
```

Access your cluster and verify:
```bash
kubectl get nodes
# All nodes should be Ready
```

**🚀 You're ready to deploy workloads!**

