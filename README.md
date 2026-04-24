# Field Lab Automation

This project provides a single-click, fully automated bootstrap script to set up a stateless Ubuntu Jumphost and deploy a complete Kubernetes and ArgoCD environment into a VMware Cloud Foundation (VCF) environment using Terraform.

## 🛠️ What It Installs & Configures (Outcomes)

When you run the setup script, it performs the following actions sequentially:

1. **Prepares the OS:** Updates Ubuntu `apt` repositories and automatically fixes any broken or held packages (specifically resolving common `libcurl` stateless image issues).
2. **Installs Core CLI Tools:** Installs `curl`, `unzip`, `git`, `jq`, `gpg`, and `expect`.
3. **Installs Infrastructure CLIs:**
   * **Kubectl:** Downloads and installs the latest stable release.
   * **Terraform:** Adds the official HashiCorp GPG keys and installs Terraform.
4. **Supercharges the Terminal:**
   * Installs **Zsh** and sets it as the default shell.
   * Installs **Oh My Zsh** completely unattended.
   * Downloads and configures custom plugins: `zsh-autosuggestions`, `zsh-syntax-highlighting`, and `kubectl` (for context-aware autocomplete).
   * Sets the terminal theme to `fino-time`.
   * Sets up global aliases: `k` for kubectl and `tf` for terraform.
5. **Prepares Terraform Automation:**
   * Clones the `vcfa-terraform-examples` repository.
   * Automatically patches the Terraform modules to use your specific lab storage policy (`cluster-wld01-01a vSAN Storage Policy`).
6. **Generates Kubernetes Manifests:** Drops an `argocd-service.yaml` file directly into your `~/Downloads` folder.
7. **Orchestrates Infrastructure Deployment:**
   * Prompts the user for their VCFA API token securely.
   * Generates the `terraform.tfvars` file with all static lab parameters and the API token.
   * **Phase 1:** Deploys the vSphere Supervisor Namespace via Terraform.
   * Automatically authenticates and creates a Supervisor Context using the `vcf` CLI (bypassing interactive prompts using `expect`).
   * **Phase 2:** Deploys the Kubernetes cluster and ArgoCD into the new namespace.
   * Drops the user directly into their new Oh My Zsh terminal session.

---

## 🚀 How to Use It

### Step 1: Run the Bootstrap Command
Open a standard terminal on your clean Ubuntu desktop and paste the following one-liner. It will ask for your `sudo` password automatically, clone the repositories, and start the master script.


echo 'VMware123!VMware123!' | sudo -S sed -i '0,/multiverse/s/multiverse/multiverse\ main\ restricted\ universe/' /etc/apt/sources.list.d/ubuntu.sources && sudo apt update -y && sudo apt install git -y && cd ~/Downloads && git clone [https://github.com/bstein-vmware/vcf9-adv-deploy-lab-setup.git](https://github.com/bstein-vmware/vcf9-adv-deploy-lab-setup.git) && cd vcf9-adv-deploy-lab-setup && chmod +x setup.sh && ./setup.sh && git clone [https://github.com/NiranEC77/lab-automation](https://github.com/NiranEC77/lab-automation) && cd lab-automation && chmod +x setup-lab.sh && ./setup-lab.sh

### Step 2: The Manual Intervention Pause
The script will install all your tools, patch the Terraform files, and then **pause**. You will see a warning message on your screen. At this point, you must do two things:

1. **Deploy the ArgoCD Service:** Open a new terminal tab (or use a UI) to apply the YAML file that was just generated for you:
   ```bash
   kubectl apply -f ~/Downloads/argocd-service.yaml
Get your Token: Log into your VCFA portal and generate an API Token.

### Step 3: Resume the Automation
Paste your VCFA API Token into the paused terminal prompt (the text will be hidden for security) and press Enter.

Grab a coffee. The script will automatically deploy the Supervisor Namespace, configure the VCF contexts, and deploy your Kubernetes and ArgoCD environments.
   

