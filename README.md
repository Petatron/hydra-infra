# hydra-infra

Terraform + CI/CD pipeline to declaratively manage KVM worker VMs and join them to the home Kubernetes control plane.

## Architecture

```
  terraform.tfvars           sync-nodes.sh             GitHub Actions
  ┌──────────────┐          ┌──────────────┐          ┌──────────────┐
  │ workers = {  │  ─plan─► │ drain removed│  ◄────── │ push to main │
  │   wk1 = {}  │  ─apply► │ tf apply     │          │ PR → plan    │
  │   wk2 = {}  │          │ join new     │          │ manual trigger│
  │ }            │          │ label nodes  │          └──────────────┘
  └──────────────┘          └──────────────┘
         │                         │
         ▼                         ▼
  libvirt/KVM VMs          kubeadm join → K8s cluster
  (br0 bridge, DHCP)       (Cilium CNI)
```

**To add a worker**: add an entry to `workers` in `terraform.tfvars`, push to `main`.
**To remove a worker**: delete the entry, push to `main`. The pipeline drains the K8s node first.
**To resize a worker**: change vcpus/ram_mb/disk_gb. This recreates the VM (drain → destroy → create → join).

## Prerequisites

| Tool | Version | Install |
|------|---------|---------|
| Terraform | >= 1.5 | [Install guide](https://developer.hashicorp.com/terraform/install) |
| jq | any | `apt install jq` |
| libvirt + KVM | (already installed) | See `~/vms/setup-host.sh` |
| kubectl | (already installed) | kubeconfig at `~/.kube/config` |

## Quick Start

```bash
# 1. Copy and edit your config
cp terraform.tfvars.example terraform.tfvars
vi terraform.tfvars

# 2. First-time migration: destroy existing manual VMs
for vm in wk1 wk2 wk3; do
  kubectl drain $vm --ignore-daemonsets --delete-emptydir-data || true
  kubectl delete node $vm || true
  sudo virsh destroy $vm || true
  sudo virsh undefine $vm --remove-all-storage || true
done

# 3. Init + plan + apply
make init
make plan     # review changes
make apply    # creates VMs, waits for boot, joins to K8s

# 4. Verify
kubectl get nodes -o wide
```

## CI/CD Setup (GitHub Actions Self-Hosted Runner)

Since Terraform manages local libvirt VMs, the CI runner must run on the worker host.

```bash
# Install the self-hosted runner (one-time)
# Go to: GitHub repo → Settings → Actions → Runners → New self-hosted runner
# Follow the download/configure instructions, then:
cd ~/actions-runner
sudo ./svc.sh install
sudo ./svc.sh start
```

### Pipeline Triggers

| Trigger | Action |
|---------|--------|
| Push to `main` (tf/template files changed) | `apply` — creates/removes VMs and joins/drains nodes |
| Pull request to `main` | `plan` — shows what would change |
| Manual dispatch: `plan` | Dry-run |
| Manual dispatch: `apply` | Full apply + join |
| Manual dispatch: `destroy` | Drains all nodes, destroys all VMs |

## Repo Layout

```
├── main.tf                 # libvirt resources (pool, volumes, domains)
├── variables.tf            # input variables
├── outputs.tf              # VM IPs, names
├── versions.tf             # provider requirements
├── terraform.tfvars        # your config (gitignored)
├── terraform.tfvars.example
├── templates/
│   ├── user-data.tpl       # cloud-init: K8s bootstrap (containerd + kubeadm)
│   └── meta-data.tpl       # cloud-init: hostname
├── scripts/
│   └── sync-nodes.sh       # lifecycle orchestrator (drain → apply → join)
├── .github/workflows/
│   └── manage-nodes.yml    # CI/CD pipeline
└── Makefile
```

## Related

- **[hydra-gitops](../hydra-gitops)** — K8s add-ons and workloads (ArgoCD, KEDA, Cilium, Helm releases)
