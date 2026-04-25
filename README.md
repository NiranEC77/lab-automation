# Field Lab Automation

Welcome to the Field Lab automation project! This repository contains a fully automated bootstrapping script designed to take a completely clean Ubuntu desktop and transform it into a fully configured, ready-to-use VMware Cloud Foundation (VCF) / vSphere with Tanzu environment.

## 🚀 Quick Start

To get started, simply open your terminal and paste the following command. This is all you need to do to kick off the entire deployment:

```bash
echo 'VMware123!VMware123!' | sudo -S sed -i '0,/multiverse/s/multiverse/multiverse\ main\ restricted\ universe/' /etc/apt/sources.list.d/ubuntu.sources && sudo apt update -y && sudo apt install git -y && cd ~/Downloads && rm -rf vcf9-adv-deploy-lab-setup && git clone [https://github.com/bstein-vmware/vcf9-adv-deploy-lab-setup.git](https://github.com/bstein-vmware/vcf9-adv-deploy-lab-setup.git) && cd vcf9-adv-deploy-lab-setup && chmod +x setup.sh && ./setup.sh && rm -rf lab-automation && git clone [https://github.com/NiranEC77/lab-automation](https://github.com/NiranEC77/lab-automation) && cd lab-automation && chmod +x setup-lab.sh && ./setup-lab.sh
```
*(Note: Remove the spaces between the backticks above when using it)*

## ⚠️ Required Manual Steps

While the script automates the vast majority of the infrastructure deployment and tool installation, the process will temporarily pause to allow you to perform a few manual tasks via the vCenter UI and CLI. 

Currently, you will need to manually:

* **Upgrade VKS:** Upgrade the vSphere Kubernetes Service in vCenter.
* **Install ArgoCD:** Deploy the ArgoCD Supervisor Service in vCenter.
* **Create the VKS Context:** Manually create the VKS workload cluster context after the script completes.

> **Note:** The script generates the necessary YAML files for the VKS and ArgoCD steps and places them right on your Desktop to make this easier!

## 🛠️ What This Script Achieves

Behind the scenes, the bootstrap script handles dozens of tasks to ensure your stateless lab is perfectly configured every single time. Here is everything it does:

### 1. Bootstrap (System Preparation)
* **Folder Structure:** Creates standard directories (`~/field-lab`, `~/.local/bin`, and ensures `~/Desktop` exists).
* **Package Management:** Updates Ubuntu, enables universe/multiverse repositories, and automatically fixes any broken APT dependencies.
* **Core Dependencies:** Installs essential tools including `curl`, `unzip`, `git`, `jq`, `gpg`, and `expect`.
* **Infrastructure CLIs:** Downloads and installs the latest stable versions of Kubectl and Terraform.

### 2. Pimp the Terminal
* **Zsh Integration:** Installs `zsh` and sets it as your default shell.
* **Oh My Zsh:** Performs an unattended installation of Oh My Zsh.
* **Theming:** Configures the sleek `fino-time` theme.
* **Productivity Plugins:** Installs and configures auto-suggestions, syntax-highlighting, git, and kubectl autocomplete plugins.
* **Aliases:** Injects persistent shortcuts (e.g., `k` for kubectl, `tf` for terraform) so they are ready the moment the script finishes.

### 3. Deploy the Lab
* **Git Automation:** Clones the `vcfa-terraform-examples` repository.
* **On-the-fly Patching:** Automatically patches the Terraform modules to match your specific lab environment (updates storage policies, VKS versions, and ArgoCD versions).
* **Desktop Helpers:** Drops generated `argocd-service.yaml` and `vks-upgrade.yaml` manifests, alongside a `password.txt` file, directly onto your Desktop for easy access during the manual phases.
* **Terraform Execution:** Initializes and executes the targeted Terraform apply to build out your Supervisor Namespace, workload clusters, and ArgoCD instances.
* **Automated API Bug Fixes:** * **Capacity Bug:** Uses the vCenter API to automatically patch the Namespace memory limits.
    * **Content Library SSL:** Automatically detects and trusts Content Library SSL thumbprints to prevent deployment hang-ups.

### 4. Finish Up (Contexts & Security)
* **Supervisor Login:** Uses an `expect` script to securely and automatically log the VCF CLI into your Supervisor Cluster.
* **API Token Management:** Securely prompts for your VCFA API Token, injects it into the Terraform variables, and saves a backup to your Desktop.
* **Certificate Trust:** Natively downloads the VCFA SSL certificate chain (`chain.pem`) so your CLI tools inherently trust the connection.
* **VCFA Context Creation:** Automatically generates the `vcfa` CLI context using the downloaded certificate chain and API token, dropping you into a fully authenticated Oh My Zsh terminal upon completion.
