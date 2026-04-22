#!/bin/bash
# Stop execution if any command fails
set -e

# --- 1. Variables & Folder Structure ---
echo "Creating folder structure..."
LAB_DIR="$HOME/field-lab"
BIN_DIR="$HOME/.local/bin"
REPO_DIR="$LAB_DIR/vcfa-terraform-examples"

mkdir -p "$LAB_DIR"
mkdir -p "$BIN_DIR"

export PATH="$BIN_DIR:$PATH"

# --- 2. Install CLIs ---
echo "Installing prerequisites (curl, unzip, git)..."
sudo apt-get update -y
sudo apt-get install -y curl unzip git jq apt-transport-https ca-certificates gnupg

# Install Kubectl
if ! command -v kubectl &> /dev/null; then
    echo "Installing kubectl..."
    curl -fsSLO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    chmod +x kubectl
    mv kubectl "$BIN_DIR/"
fi

# Install Terraform
if ! command -v terraform &> /dev/null; then
    echo "Installing Terraform..."
    wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
    echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
    sudo apt-get update -y
    sudo apt-get install -y terraform
fi

# Install VCF CLI (Placeholder)
echo "Installing VCF CLI..."
# ADD VCF CLI INSTALLATION COMMANDS HERE (e.g., pulling the binary from your vCenter plugin URL)


# --- 3. Setup Aliases ---
echo "Setting up aliases..."
cat << 'EOF' > "$HOME/.lab_aliases"
alias k='kubectl'
alias tf='terraform'
EOF

if ! grep -q ".lab_aliases" "$HOME/.bashrc"; then
    echo "source $HOME/.lab_aliases" >> "$HOME/.bashrc"
fi
# Source it for the current script execution
source "$HOME/.lab_aliases"


# --- 4. Pull Git Repo ---
echo "Cloning the Terraform automation repo..."
if [ -d "$REPO_DIR" ]; then
    echo "Repo already exists. Pulling latest..."
    cd "$REPO_DIR"
    git pull
else
    git clone https://github.com/warroyo/vcfa-terraform-examples "$REPO_DIR"
fi


# --- 5. Add Static Variables File ---
# Navigating to the argo-e2e directory (adjust path if your root module is elsewhere)
cd "$REPO_DIR/argo-e2e"

echo "Injecting static variables..."
cat << 'EOF' > terraform.tfvars
# REPLACE THESE WITH YOUR STATIC VARIABLES
vcenter_server      = "vc-wld01-a.site-a.vcf.lab"
vcenter_user        = "administrator@wld.sso"
vcenter_password    = "VMware123!VMware123!"
supervisor_cluster  = "domain-c8"
namespace_name      = "field-e2e-lab-ns"
# Add any other required variables for the argo-e2e module
EOF


# --- 6. Terraform Execution Sequence ---
echo "Initializing Terraform..."
terraform init

echo "Targeting Supervisor Namespace creation..."
terraform apply -target=module.supervisor_namespace -auto-approve

echo "Applying the rest of the infrastructure (ArgoCD, etc.)..."
terraform apply -auto-approve


# --- 7. Create Contexts via VCF CLI ---
echo "Setting up Supervisor and VCFA contexts..."

# SUPERVISOR CONTEXT
# REPLACE WITH YOUR COMMANDS
# Example: vcf login --server <ip> --user <user> ... 

# VCFA CONTEXT
# REPLACE WITH YOUR COMMANDS
# Example: kubectl vsphere login --server <vcfa-ip> ...

echo "Field Lab deployment successfully completed!"
echo "Please run 'source ~/.bashrc' to ensure your aliases are loaded in your current terminal."
