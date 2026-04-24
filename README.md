# Field Lab Automation

This project provides a single-click, fully automated bootstrap script to set up a stateless Ubuntu Jumphost, install necessary DevOps tools, supercharge your terminal, and deploy a complete Kubernetes and ArgoCD environment into a VMware Cloud Foundation (VCF) lab using Terraform.

## 🌟 What It Installs & Configures (Outcomes)

### 🚀 The Bootstrap Script
* Updates Ubuntu `apt` repositories to include `multiverse`, `restricted`, and `universe`.
* Installs `git` automatically.
* Clones the upstream VMware lab setup repository and runs its native setup.
* Clones this custom automation repository.
* Automatically triggers the master `setup-lab.sh` script to begin the heavy lifting.

### 🛠️ Automated Tools Installation
* Automatically fixes any broken or held `apt` packages (resolving common `libcurl` stateless image issues).
* Installs core infrastructure CLI utilities: `curl`, `unzip`, `jq`, `gpg`, and `expect`.
* **Kubernetes:** Downloads and installs the latest stable release of `kubectl`.
* **Terraform:** Injects HashiCorp's official GPG keys and installs the `terraform` CLI.

### 🎨 Pimp the Terminal
* Installs **Zsh** and safely configures it as the default shell.
* Installs **Oh My Zsh** entirely unattended.
* Injects and enables powerful Oh My Zsh plugins: 
  * `zsh-autosuggestions` (predictive typing based on history).
  * `zsh-syntax-highlighting` (color-codes valid vs invalid commands).
  * `kubectl` (enables context-aware K8s autocomplete).
* Sets the sleek and informative `fino-time` terminal theme.
* Configures global `.bashrc` and `.zshrc` aliases (`k` for `kubectl`, `tf` for `terraform`).
* Uses `exec zsh` to hot-swap your terminal session instantly at the end of the script without requiring a logout.

### ⚙️ Automated Lab Deployment
* **Terraform Patching:** Automatically patches the cloned Terraform modules to:
  * Use the correct vCenter Storage Policy (`cluster-wld01-01a vSAN Storage Policy`).
  * Override the ArgoCD module to deploy version `3.0.19+vmware.1-vks.1`.
  * Update the VKS cluster module `cluster_class` to use `builtin-generic-v3.6.2` to support the upgraded service tier.
* **Manifest Generation:** Creates `argocd-service.yaml` and `vks-upgrade.yaml` files directly on your Desktop (`~/Desktop/`).
* **Credentials Backup:** Saves your Lab Password and standard admin username to `~/Desktop/password.txt`.
* **Variable Injection:** Captures your VCFA API token securely and generates a complete `terraform.tfvars` file for the `argo-e2e` module.
* **Phase 1 Execution:** Executes `terraform apply` targeted specifically at creating the vSphere Supervisor Namespace.
* **vCenter API Bug Fix:** Automatically authenticates against the vCenter REST API in the background to inject a dummy limit update, fixing the known "Namespace Capacity/Usage" bug that prevents resources from deploying.
* **Supervisor Context Creation:** Automatically logs into the Supervisor Cluster and creates your local Kubernetes context (`supervisor-ctx`), using an `expect` script to securely and invisibly bypass the interactive `vcf` CLI prompts.
* **Phase 2 Execution:** Executes the final `terraform apply` to deploy the workload K8s cluster and ArgoCD instance into the unstuck namespace.

---

## 🚀 How to Deploy

### Step 1: Run the Bootstrap Command

Open a standard terminal on your clean Ubuntu desktop, copy the command block below, and paste it. It will pass your lab password automatically, clone the repositories, and kick off the entire process.

```bash
echo 'VMware123!VMware123!' | sudo -S sed -i '0,/multiverse/s/multiverse/multiverse\ main\ restricted\ universe/' /etc/apt/sources.list.d/ubuntu.sources && sudo apt update -y && sudo apt install git -y && cd ~/Downloads && git clone https://github.com/bstein-vmware/vcf9-adv-deploy-lab-setup.git && cd vcf9-adv-deploy-lab-setup && chmod +x setup.sh && ./setup.sh && git clone https://github.com/NiranEC77/lab-automation && cd lab-automation && chmod +x setup-lab.sh && ./setup-lab.sh
```

### Step 2: The Manual Intervention Pause

The script will configure the OS, install all your tools, patch the Terraform modules, and then **pause**. You will see a warning message on your screen.

1. **Deploy the ArgoCD Service:** Log into **vCenter**, navigate to **Workload Management** -> **Services**, and deploy the ArgoCD service through the UI. *(The spec is saved at `~/Desktop/argocd-service.yaml` if you need to register it).*
2. **Upgrade VKS:** From the same UI, apply the upgrade for the vSphere Kubernetes Service. *(The spec is saved at `~/Desktop/vks-upgrade.yaml` if you need to register it).*
3. **Get your Token:** *While the services are installing*, log into your VCFA portal (`https://auto-a.site-a.vcf.lab`) and generate a new API Token. (Your standard lab credentials are saved on your Desktop if you need them).

### Step 3: Resume the Automation

1. Go back to your paused terminal window.
2. Paste your **VCFA API Token** into the prompt (the text will be hidden for security) and press `Enter`.
3. Sit back and watch. The script will deploy the namespace, execute the vCenter API capacity bugfix, log into the Supervisor context, and finish the K8s/ArgoCD deployment automatically.

### Step 4: Ready to Work

Once the Terraform apply finishes, the script will automatically replace your standard Bash shell with your newly configured **Oh My Zsh** environment. All your plugins, aliases, and K8s contexts are immediately active and ready to use!
