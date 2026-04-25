#!/bin/bash
# Stop execution if any command fails
set -e

# --- 1. Variables & Folder Structure ---
echo "Creating folder structure..."
LAB_DIR="$HOME/field-lab"
BIN_DIR="$HOME/.local/bin"
REPO_DIR="$LAB_DIR/vcfa-terraform-examples"
VCFA_HOST="auto-a.site-a.vcf.lab"

mkdir -p "$LAB_DIR"
mkdir -p "$BIN_DIR"

# Temporarily add to path for this session
export PATH="$BIN_DIR:$PATH"

# --- 2. Install CLIs & Prerequisites ---
echo "Checking prerequisites..."
sudo apt-get update -y
sudo apt-get --fix-broken install -y

TOOLS="curl unzip git jq gpg zsh"
for tool in $TOOLS; do
    if ! command -v $tool &> /dev/null; then
        echo "Installing $tool..."
        if [ "$tool" = "curl" ]; then
            sudo apt-get install -y curl libcurl4t64 || sudo apt-get install -y curl
        else
            sudo apt-get install -y $tool
        fi
    else
        echo "$tool is already installed. Skipping."
    fi
done

for pkg in apt-transport-https ca-certificates; do
    if ! dpkg -s $pkg >/dev/null 2>&1; then
        echo "Installing $pkg..."
        sudo apt-get install -y $pkg
    fi
done

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

# --- 3. Setup Zsh & Oh My Zsh ---
echo "Setting up Zsh and Oh My Zsh..."

if [ "$SHELL" != "$(which zsh)" ]; then
    echo "Changing default shell to zsh..."
    sudo chsh -s $(which zsh) $(whoami)
fi

if [ ! -d "$HOME/.oh-my-zsh" ]; then
    echo "Installing Oh My Zsh..."
    RUNZSH=no CHSH=no sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
fi

ZSH_CUSTOM="$HOME/.oh-my-zsh/custom"

if [ ! -d "$ZSH_CUSTOM/plugins/zsh-autosuggestions" ]; then
    git clone https://github.com/zsh-users/zsh-autosuggestions "$ZSH_CUSTOM/plugins/zsh-autosuggestions"
fi
if [ ! -d "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" ]; then
    git clone https://github.com/zsh-users/zsh-syntax-highlighting "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting"
fi

sed -i 's/^ZSH_THEME=.*/ZSH_THEME="fino-time"/' "$HOME/.zshrc"
sed -i 's/^plugins=(git)/plugins=(git zsh-autosuggestions zsh-syntax-highlighting kubectl)/' "$HOME/.zshrc"

cat << 'EOF' > "$HOME/.lab_aliases"
alias k='kubectl'
alias tf='terraform'
EOF

if ! grep -q ".lab_aliases" "$HOME/.zshrc"; then
    echo "source $HOME/.lab_aliases" >> "$HOME/.zshrc"
fi

# --- 4. Trust VCFA Certificate Chain (THE FIX) ---
echo "Downloading and trusting VCFA Certificate Chain natively in Ubuntu..."
# We use openssl to pull the cert, format it, and inject it into the OS trust store
openssl s_client -showcerts -connect $VCFA_HOST:443 </dev/null 2>/dev/null | awk '/BEGIN CERTIFICATE/,/END CERTIFICATE/{print}' | sudo tee /usr/local/share/ca-certificates/vcfa.crt > /dev/null
sudo update-ca-certificates

# --- 5. Pull Git Repo & Patch Module ---
echo "Cloning the Terraform automation repo..."
if [ -d "$REPO_DIR" ]; then
    cd "$REPO_DIR"
    git pull
else
    git clone https://github.com/warroyo/vcfa-terraform-examples "$REPO_DIR"
fi

echo "Patching storage policy in the namespace module..."
sed -i 's/"vSAN Default Storage Policy"/"cluster-wld01-01a vSAN Storage Policy"/g' "$REPO_DIR/modules/namespace/main.tf"

# --- 6. Interactive Prompts & Variables ---
echo ""
read -s -p "🔑 Enter your VCFA API Token (input will be hidden): " VCFA_TOKEN
echo ""
echo "Token captured."

cd "$REPO_DIR/argo-e2e"

echo "Injecting static and dynamic variables..."
cat << EOF > terraform.tfvars
vcenter_server      = "vc-wld01-a.site-a.vcf.lab"
vcenter_user        = "administrator@wld.sso"
vcenter_password    = "VMware123!VMware123!"
supervisor_cluster  = "domain-c8"
region_name         = "us-west-region"
vpc_name            = "us-west-region-default-vpc"
zone_name           = "z-wld-a"
vcfa_org            = "all-apps"
vcfa_url            = "https://auto-a.site-a.vcf.lab"
namespace           = "e2e-ns"
cluster             = "e2e-niran-cls01"
bootstrap_revision  = "1.0.1"
vcfa_refresh_token  = "$VCFA_TOKEN"
EOF

# --- 7. Terraform Execution Sequence ---
echo "Initializing Terraform..."
terraform init

echo "Phase 1: Targeting Supervisor Namespace creation..."
terraform apply -target=module.supervisor_namespace -auto-approve

echo "Phase 2: Applying the rest of the infrastructure (ArgoCD, K8s cluster, etc.)..."
terraform apply -auto-approve

# --- 8. Create Contexts via VCF CLI ---
echo "Setting up Supervisor and VCFA contexts..."

# SUPERVISOR CONTEXT
echo "Logging into Supervisor Cluster..."
# REPLACE WITH YOUR SUPERVISOR LOGIN COMMAND

# VCFA CONTEXT
echo "Logging into VCFA..."
# REPLACE WITH YOUR VCFA LOGIN COMMAND

echo "========================================="
echo "✅ Field Lab deployment successfully completed!"
echo "========================================="
echo "Please completely close this terminal window and open a new one to start using Zsh and your new plugins!"
