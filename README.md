# Field Lab Automation

Welcome to the Field Lab automation project! This repository contains a fully automated bootstrapping script designed to take a completely clean Ubuntu desktop and transform it into a fully configured, ready-to-use VMware Cloud Foundation (VCF) / vSphere with Tanzu environment.

## 🚀 Quick Start

To get started, simply open your terminal and paste the following command. This is all you need to do to kick off the entire deployment:

```bash
echo 'VMware123!VMware123!' | sudo -S sed -i '0,/multiverse/s/multiverse/multiverse\ main\ restricted\ universe/' /etc/apt/sources.list.d/ubuntu.sources && sudo apt update -y && sudo apt install git -y && cd ~/Downloads && rm -rf vcf9-adv-deploy-lab-setup && git clone https://github.com/bstein-vmware/vcf9-adv-deploy-lab-setup.git && cd vcf9-adv-deploy-lab-setup && chmod +x setup.sh && ./setup.sh && rm -rf lab-automation && git clone https://github.com/NiranEC77/lab-automation && cd lab-automation && chmod +x setup-lab.sh && ./setup-lab.sh
```

## 🎛️ Modes of Operation

The script starts by asking you to choose a mode. After that, everything is automated.

### `prep` — Install & Configure (stops before Terraform deploy)

Choose this when you want to get the environment ready while VKS upgrades and ArgoCD deployments are still installing in vCenter.

- Drops YAML manifests to the Desktop immediately
- Installs all CLIs & prerequisites
- Configures Zsh + Oh My Zsh
- Clones and patches the Terraform repo
- Captures your VCFA API token
- Writes `terraform.tfvars` and runs `terraform init`
- **Stops here** — does NOT run `terraform apply`

### `deploy` — Full End-to-End

Choose this for the complete flow. Deploy runs **all prep steps first** (skipping anything already done), then continues with:

- Terraform apply (namespace + full infrastructure)
- Automated vCenter API bug fixes
- VCF CLI context configuration (Supervisor, VCFA, and VKS cluster)
- Drops you into a fully authenticated Oh My Zsh terminal

> **Re-run friendly:** If prep was already completed, deploy detects the existing token and `terraform.tfvars` and skips straight to the Terraform and context setup phases.

## ⚠️ Required Manual Steps

While the script automates the vast majority of the deployment, it pauses once to let you perform a few manual tasks in the vCenter UI. The script generates all necessary YAML files and places them on your Desktop to make this easy.

During the pause, you will need to:

| Step | Action | YAML on Desktop |
|------|--------|----------------|
| 1 | **Upgrade VKS** to v3.5 | `vks-upgrade-3.5.1.yaml` |
| 2 | **Deploy ArgoCD Service** | `argocd-service-1.1.0.yaml` |
| 3 | **Deploy ArgoCD Attach Fling** | `argocd-attach-1.0.7.yaml` |
| 4 | **Get VCFA API Token** | *(paste into script prompt)* |

> Navigate to **vCenter → Workload Management → Supervisor Services** to perform steps 1–3. For step 4, log into VCFA at `https://auto-a.site-a.vcf.lab` with credentials from `~/Desktop/password.txt` and generate a refresh token.

## 🛠️ What This Script Does

### 1. YAML Manifests (Dropped First)
Before anything else, the script writes three YAML manifests to your Desktop so you can start manual upgrades in vCenter immediately while the rest of the setup runs in parallel:
* `argocd-service-1.1.0.yaml` — ArgoCD Supervisor Service package
* `vks-upgrade-3.5.1.yaml` — VKS (Kubernetes Service) v3.5.1 upgrade package
* `argocd-attach-1.0.7.yaml` — ArgoCD Attach Fling package

### 2. Bootstrap (System Preparation)
* **Folder Structure:** Creates standard directories (`~/field-lab`, `~/.local/bin`, `~/Desktop`).
* **Package Management:** Updates Ubuntu and automatically fixes broken APT dependencies.
* **Core Dependencies:** Installs `curl`, `unzip`, `git`, `jq`, `gpg`, `zsh`, and `expect`.
* **Infrastructure CLIs:** Downloads and installs the latest stable versions of Kubectl and Terraform.

### 3. Pimp the Terminal
* **Zsh Integration:** Installs `zsh` and sets it as your default shell.
* **Oh My Zsh:** Performs an unattended installation with the `fino-time` theme.
* **Productivity Plugins:** Auto-suggestions, syntax-highlighting, git, and kubectl autocomplete.
* **Aliases:** Persistent shortcuts — `k` for kubectl, `tf` for terraform.

### 4. Terraform Repo & Patching
* **Git Automation:** Clones the `vcfa-terraform-examples` repository.
* **On-the-fly Patching:** Automatically patches modules before deploy:
  * Storage policy → `cluster-wld01-01a vSAN Storage Policy`
  * VKS cluster class → `builtin-generic-v3.5.0`
  * ArgoCD version → `3.0.19+vmware.1-vks.1`
  * Storage class → `cluster-wld01-01a-vsan-storage-policy`

### 5. Terraform Execution
* **Phase 1:** Targeted apply for Supervisor Namespace creation.
* **Phase 2:** Full apply for ArgoCD instances, VKS clusters, and remaining infrastructure.
* **Smart Retry:** Automatically handles the known VKS CRD provider bug with state refresh and retry logic.

### 6. Automated API Bug Fixes
* **Capacity Bug:** Uses the vCenter API to patch Namespace memory limits so the namespace doesn't get stuck.
* **Content Library SSL:** Detects and trusts Content Library SSL thumbprints, then forces a sync to prevent deployment hang-ups.

### 7. VCF CLI Context Configuration
The script automatically configures three VCF CLI contexts:

| Context | Type | Purpose |
|---------|------|---------|
| `supervisor-ctx` | Kubernetes | Supervisor cluster access (10.1.0.2) |
| `vcfa` | VCFA | VCFA org-level access (auto-a.site-a.vcf.lab) |
| `e2e-niran-cls-01` | CCI | VKS workload cluster access |

For the VKS cluster context, the script:
1. Auto-detects the VCFA namespace context
2. Registers the VCFA JWT authenticator on the cluster
3. Fetches the kubeconfig
4. Parses the context name and creates the CCI context

> All VCF CLI commands include timeout protection and automatic prompt handling to prevent the script from hanging.

### 8. Finish Up
* **Certificate Trust:** Downloads the VCFA SSL certificate chain for CLI trust.
* **API Token Management:** Securely captures and stores your VCFA refresh token.
* **Credentials:** Saves lab username/password to `~/Desktop/password.txt`.
* **Oh My Zsh:** Drops you into a fully authenticated, themed terminal when complete.

## 📁 Files in This Repo

| File | Description |
|------|-------------|
| `setup-lab.sh` | Main automation script (prep/deploy modes) |
| `test-cluster-ctx.sh` | Standalone test script for VKS cluster context setup |
| `argo-attach.yaml` | ArgoCD Attach Fling package YAML (reference) |
| `vks3.5.1.yaml` | VKS 3.5.1 upgrade package YAML (reference) |
| `README.md` | This file |
