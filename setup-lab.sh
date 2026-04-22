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

# Temporarily add to path for this session
export PATH="$BIN_DIR:$PATH"

# --- 2. Install CLIs & Prerequisites ---
echo "Checking prerequisites..."
sudo apt-get update -y

# List of required packages
PACKAGES="curl unzip git jq apt-transport-https ca-certificates gnupg"

for pkg in $PACKAGES; do
    if ! dpkg -s $pkg >/dev/null 2>&1; then
        echo "Installing $pkg..."
        sudo apt-get install -y $pkg
    else
        echo "$pkg is already installed. Skipping."
    fi
done

# Install Kubectl
if ! command -v kubectl &> /dev/null; then
    echo "Installing kubectl..."
    curl -fsSLO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    chmod +x kubectl
    mv kubectl "$BIN_DIR/"
else
    echo "kubectl is already installed."
fi

# Install Terraform
if ! command -v terraform &> /dev/null; then
    echo "Installing Terraform..."
    wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
    echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
    sudo apt-get update -y
    sudo apt-get install -y terraform
else
    echo "Terraform is already installed."
fi

# Install VCF CLI (Placeholder)
echo "Setting up VCF CLI..."
# ADD VCF CLI INSTALLATION COMMANDS HERE
# Example: curl -L <url-to-vcf-cli> -o vcf && chmod +x vcf && mv vcf $BIN_DIR/


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
# Navigating to the argo-e2e directory
cd "$REPO_DIR/argo-e2e"

echo "Injecting static variables..."
cat << 'EOF' > terraform.tfvars
vcenter_server      = "vc-wld01-a.site-a.vcf.lab"
vcenter_user        = "administrator@wld.sso"
vcenter_password    = "VMware123!VMware123!"
supervisor_cluster  = "domain-c8"
namespace_name      = "field-e2e-lab-ns"
EOF


# --- 6. Terraform Execution Sequence ---
echo "Initializing Terraform..."
terraform init

echo "Phase 1: Targeting Supervisor Namespace creation..."
terraform apply -target=module.supervisor_namespace -auto-approve

echo "Phase 2: Applying the rest of the infrastructure (ArgoCD, K8s cluster, etc.)...."
terraform apply -auto-approve


# --- 7. Create Contexts via VCF CLI ---
echo "Setting up Supervisor and VCFA contexts..."

# SUPERVISOR CONTEXT
echo "Logging into Supervisor Cluster..."
# REPLACE WITH YOUR SUPERVISOR LOGIN COMMAND
# Example: vcf login --server <supervisor-ip> --user <user> --password <pass> --insecure

# VCFA CONTEXT
echo "Logging into VCFA..."
# REPLACE WITH YOUR VCFA LOGIN COMMAND
# Example: kubectl vsphere login --server <vcfa-ip> --insecure-skip-tls-verify ...

echo "========================================="
echo "✅ Field Lab deployment successfully completed!"
echo "========================================="
echo "Please run 'source ~/.bashrc' or restart your terminal to ensure your aliases (k, tf) are loaded."
