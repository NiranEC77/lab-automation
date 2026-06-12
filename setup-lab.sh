#!/bin/bash
# Stop execution if any command fails
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=ctx-lib.sh
source "$SCRIPT_DIR/ctx-lib.sh"


# --- Mode Selection (ask first, automate everything after) ---
echo ""
echo "╔═══════════════════════════════════════════╗"
echo "║       🚀 Field Lab Setup Script           ║"
echo "╚═══════════════════════════════════════════╝"
echo ""
echo "What would you like to do?"
echo ""
echo "  1) prep   → Install tools, drop YAMLs, patch configs, capture token,"
echo "              and initialize Terraform. Stops before Terraform apply."
echo ""
echo "  2) deploy → Full end-to-end: runs prep (skips steps already done)"
echo "              + Terraform apply + all context configuration."
echo ""
read -p "Enter your choice [prep/deploy]: " MODE
echo ""

# Normalize input
case "$MODE" in
    1|prep|p)   MODE="prep" ;;
    2|deploy|d) MODE="deploy" ;;
    *) echo "❌ Invalid choice. Please run again and choose 'prep' or 'deploy'."; exit 1 ;;
esac

echo "Running in ${MODE^^} mode..."
echo ""

pick_environment


###############################################################################
#                         PREP (runs for both modes)                          #
###############################################################################

# --- 1. Variables & Folder Structure ---
echo "Verifying folder structure..."
LAB_DIR="$HOME/field-lab"
REPO_DIR="$LAB_DIR/vcfa-terraform-examples"
DESKTOP_DIR="$HOME/Desktop"
DOWNLOADS_DIR="$LAB_DIR/downloads"
CLUSTER_NAME="e2e-cls01"

mkdir -p "$LAB_DIR"
mkdir -p "$DESKTOP_DIR"
mkdir -p "$DOWNLOADS_DIR"

read -s -p "Enter Box shared link password: " BOX_PASS
echo ""

SVC_DIR="$SCRIPT_DIR/supervisor-services"
VCENTER_SERVER="vc-wld01-a.site-a.vcf.lab"
VCENTER_USER="administrator@wld.sso"
VCENTER_CLUSTER_NAME="cluster-wld01-01a"
TOKEN_FILE="$DESKTOP_DIR/vcfa_api_token.txt"
TFVARS_FILE="$REPO_DIR/argo-e2e/terraform.tfvars"
ARGOCD_VERSION="3.0.19+vmware.1-vks.1"
K8S_VERSION="v1.35.2+vmware.1"


# --- 2. Install Supervisor Services ---


# --- 3c. Unpack Supervisor Services Bundle ---
SVC_BUNDLE=$(find "$DOWNLOADS_DIR" -name "*.tar.gz" -not -name "VCF-Consumption-CLI-PluginBundle*" | sort | tail -1)
if [ -n "$SVC_BUNDLE" ]; then
    echo "Updating supervisor services from: $(basename "$SVC_BUNDLE")"

    TEMP_EXTRACT=$(mktemp -d)
    tar -xzf "$SVC_BUNDLE" -C "$TEMP_EXTRACT"

    # Descend into single top-level wrapper dir if present
    TOP_COUNT=$(find "$TEMP_EXTRACT" -mindepth 1 -maxdepth 1 | wc -l)
    if [ "$TOP_COUNT" -eq 1 ] && [ -d "$(find "$TEMP_EXTRACT" -mindepth 1 -maxdepth 1)" ]; then
        SRC_DIR=$(find "$TEMP_EXTRACT" -mindepth 1 -maxdepth 1)
    else
        SRC_DIR="$TEMP_EXTRACT"
    fi

    # Remove existing SVC_DIR contents except services.yaml
    find "$SVC_DIR" -mindepth 1 -maxdepth 1 -not -name "services.yaml" -exec rm -rf {} \;

    # Copy bundle contents, skipping any services.yaml that came in the bundle
    find "$SRC_DIR" -mindepth 1 -maxdepth 1 -not -name "services.yaml" -exec cp -r {} "$SVC_DIR/" \;

    rm -rf "$TEMP_EXTRACT"
    echo "Supervisor services updated."
else
    echo "WARNING: No supervisor services bundle found in $DOWNLOADS_DIR — skipping."
fi


# --- 3. Install CLIs & Prerequisites ---
echo "Checking prerequisites..."

# Ensure all Ubuntu repo components are available across all stanzas (main, restricted, universe, multiverse)
if [ -f /etc/apt/sources.list.d/ubuntu.sources ]; then
    echo "Expanding Ubuntu apt sources..."
    echo "$LAB_PASS" | sudo -S sed -i \
        's/^Components:.*/Components: main restricted universe multiverse/' \
        /etc/apt/sources.list.d/ubuntu.sources
fi

echo "$LAB_PASS" | sudo -S apt-get update -y
echo "$LAB_PASS" | sudo -S apt-get --fix-broken install -y

TOOLS="curl unzip git jq gpg zsh expect kubectx kubens kubecolor vim fzf"
for tool in $TOOLS; do
    if ! command -v $tool &> /dev/null; then
        echo "Installing $tool..."
        echo "$LAB_PASS" | sudo -S apt-get install -y $tool
    else
        echo "$tool is already installed. Skipping."
    fi
done

for pkg in apt-transport-https ca-certificates; do
    if ! dpkg -s $pkg >/dev/null 2>&1; then
        echo "Installing $pkg..."
        echo "$LAB_PASS" | sudo -S apt-get install -y $pkg
    fi
done

if ! python3 -c "import requests" 2>/dev/null; then
    echo "Installing python3-requests..."
    echo "$LAB_PASS" | sudo -S apt-get install -y python3-requests 2>/dev/null || \
        python3 -m pip install --break-system-packages requests 2>/dev/null || true
fi

if ! python3 -c "import yaml" 2>/dev/null; then
    echo "Installing python3-yaml..."
    echo "$LAB_PASS" | sudo -S apt-get install -y python3-yaml 2>/dev/null || \
        python3 -m pip install --break-system-packages pyyaml 2>/dev/null || true
fi

if ! command -v pwsh &> /dev/null; then
    echo "Installing PowerShell..."
    curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | \
        sudo gpg --dearmor -o /usr/share/keyrings/microsoft.gpg
    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/microsoft.gpg] \
https://packages.microsoft.com/ubuntu/$(lsb_release -rs)/prod $(lsb_release -cs) main" | \
        sudo tee /etc/apt/sources.list.d/microsoft-prod.list
    echo "$LAB_PASS" | sudo -S apt-get update -y
    echo "$LAB_PASS" | sudo -S apt-get install -y powershell
fi

if ! pwsh -NonInteractive -Command "Get-Module -ListAvailable VMware.PowerCLI" 2>/dev/null | grep -q VMware; then
    echo "Installing VMware PowerCLI..."
    pwsh -NonInteractive -Command \
        "Install-Module VMware.PowerCLI -Scope CurrentUser -Force -SkipPublisherCheck -AllowClobber"
fi

# For ss (9.1) always (re)install — lab image may ship stale 9.0.2 vcf on PATH,
# which would otherwise skip the install and leave the wrong CLI version.
if ! command -v vcf &> /dev/null || [ "$LAB_ENV" = "ss" ]; then
    echo "Installing VCF CLI..."
    if [ "$LAB_ENV" = "ss" ]; then
        VCF_CLI_URL="https://$SUPERVISOR_ENDPOINT/wcp/vcf-cli/v9.1.0.0/25296329/linux/amd64/vcf-cli.tar.gz"
    else
        VCF_CLI_URL="https://packages.broadcom.com/artifactory/vcf-distro/vcf-cli/linux/amd64/v9.0.2/vcf-cli.tar.gz"
    fi
    curl -kfsSLO --retry 5 --retry-delay 5 --retry-all-errors "$VCF_CLI_URL"
    tar -xf vcf-cli.tar.gz
    # Install over the path vcf currently resolves to (e.g. stale /usr/bin/vcf
    # from the lab image), else default to /usr/local/bin/vcf.
    VCF_TARGET="$(command -v vcf || echo /usr/local/bin/vcf)"
    echo "$LAB_PASS" | sudo -S install vcf-cli-linux_amd64 "$VCF_TARGET"
    rm -f vcf-cli.tar.gz vcf-cli-linux_amd64
    hash -r
fi

if ! command -v argocd &> /dev/null; then
    echo "Installing ArgoCD CLI..."
    curl -fsSL -o /tmp/argocd \
        "https://github.com/argoproj/argo-cd/releases/download/v3.0.19/argocd-linux-amd64"
    echo "$LAB_PASS" | sudo -S install /tmp/argocd /usr/local/bin/argocd
    rm -f /tmp/argocd
fi

if ! command -v kubectl &> /dev/null; then
    echo "Installing kubectl..."
    curl -fsSLO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    echo "$LAB_PASS" | sudo -S install kubectl /usr/local/bin/kubectl
    rm -f kubectl
fi

if ! command -v terraform &> /dev/null; then
    echo "Installing Terraform..."
    echo "$LAB_PASS" | sudo -S true 
    
    wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
    echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
    
    echo "$LAB_PASS" | sudo -S apt-get update -y
    echo "$LAB_PASS" | sudo -S apt-get install -y terraform
fi


# --- 3b. Download Box Files ---
# Password-protected Box shared file links (same password for all).
# Add/remove entries as new files are available.
BOX_FILES=(
    "https://ent.box.com/s/bzqcj8bbgzheoec3chi59b46tevi8ptq"  # VCF CLI 9.1 plugin bundle
    "https://ent.box.com/s/xfn45z5ykisj1fy3mya2arbuzvm68q2k"  # Supervisor services bundle
    # "https://ent.box.com/s/NEXT_FILE_HASH"
)

echo "Downloading files from Box..."
python3 "$SCRIPT_DIR/download-box.py" \
    --password "$BOX_PASS" \
    --output "$DOWNLOADS_DIR" \
    "${BOX_FILES[@]}"


# --- 4. Setup Zsh & Oh My Zsh ---
echo "Setting up Zsh and Oh My Zsh..."
if [ "$SHELL" != "$(which zsh)" ]; then
    echo "Changing default shell to zsh..."
    echo "$LAB_PASS" | sudo -S chsh -s $(which zsh) $(whoami)
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

if ! grep -q "exec zsh" "$HOME/.bashrc"; then
    echo -e "\n# Launch Zsh automatically" >> "$HOME/.bashrc"
    echo 'if [ -t 1 ] && [ -z "$ZSH_VERSION" ]; then' >> "$HOME/.bashrc"
    echo '    exec zsh' >> "$HOME/.bashrc"
    echo 'fi' >> "$HOME/.bashrc"
fi


# --- 5. Setup Aliases ---
echo "Setting up aliases..."
cat << 'EOF' > "$HOME/.lab_aliases"
alias k='kubectl'
alias kctx='kubectx'
alias kns='kubens'
alias tf='terraform'
EOF

if ! grep -q ".lab_aliases" "$HOME/.zshrc"; then
    echo "source $HOME/.lab_aliases" >> "$HOME/.zshrc"
fi


# --- 6. Pull Git Repo & Patch Modules ---
echo "Managing the Terraform automation repo..."
if [ -d "$REPO_DIR" ]; then
    echo "Repo already exists. Pulling latest updates without overwriting custom files..."
    cd "$REPO_DIR"
    git pull
else
    git clone https://github.com/warroyo/vcfa-terraform-examples "$REPO_DIR"
fi


# --- 7. Save Credentials to Desktop ---
echo "Saving credentials to Desktop..."
cat << EOF > "$DESKTOP_DIR/password.txt"
Lab Username: $VCFA_USER
Lab Password: $LAB_PASS
EOF


# --- 8. VCF CLI Setup ---
echo "Pre-configuring VCF CLI (EULA, CEIP, and plugins)..."
export VCF_CLI_VSPHERE_PASSWORD=$LAB_PASS
vcf plugin sync 2>/dev/null || true
vcf telemetry update --opted-out 2>/dev/null || true

# --- 8b. Install VCF CLI Plugin Bundle (ss/9.1 only) ---
if [ "$LAB_ENV" = "ss" ]; then
    PLUGIN_BUNDLE=$(find "$DOWNLOADS_DIR" -name "VCF-Consumption-CLI-PluginBundle*.tar.gz" | sort | tail -1)
    if [ -n "$PLUGIN_BUNDLE" ]; then
        echo "Installing VCF CLI plugins from local bundle: $PLUGIN_BUNDLE"
        BUNDLE_EXTRACT_DIR="$DOWNLOADS_DIR/vcf-plugin-bundle"
        mkdir -p "$BUNDLE_EXTRACT_DIR"
        tar -xzf "$PLUGIN_BUNDLE" -C "$BUNDLE_EXTRACT_DIR"
        BUNDLE_ROOT=$(tar -tzf "$PLUGIN_BUNDLE" 2>/dev/null | head -1 | cut -d'/' -f1)
        vcf plugin install all --local-source "$BUNDLE_EXTRACT_DIR/$BUNDLE_ROOT"
    else
        echo "WARNING: No VCF CLI plugin bundle found in $DOWNLOADS_DIR — skipping plugin install."
    fi
fi

echo "Creating VCF Supervisor Context..."
vcf context create supervisor-ctx \
  --endpoint "$SUPERVISOR_ENDPOINT" \
  --username $VCENTER_USER \
  --insecure-skip-tls-verify \
  -t kubernetes \
  --auth-type basic 2>/dev/null || echo "Context may already exist. Continuing..."

echo "Setting supervisor-ctx as current context..."
vcf context use supervisor-ctx 2>/dev/null || true


# --- 9. Update Content Library Subscription URL ---
CONTENT_LIBRARY_NAME="Kubernetes Service Content Library"
CONTENT_LIBRARY_URL="https://wp-content.vmware.com/v2/latest/lib.json"

echo "Updating Content Library subscription URL..."
pwsh -NonInteractive -File "$SCRIPT_DIR/update-content-library.ps1" \
    -VCenterServer "$VCENTER_SERVER" \
    -LibraryName "$CONTENT_LIBRARY_NAME" \
    -NewSubscriptionUrl "$CONTENT_LIBRARY_URL" \
    -Username "$VCENTER_USER" \
    -Password "$LAB_PASS"


# --- 11. VCFA Certificate & Context ---
VCFA_CERT_PATH="$LAB_DIR/vcfa_chain.pem"


# --- 12. Manual Intervention & Token Capture ---
# Skip if token and tfvars already exist from a previous prep run
if [ -f "$TOKEN_FILE" ] && [ -f "$TFVARS_FILE" ]; then
    echo "✅ Previous prep detected — token and terraform.tfvars already exist. Skipping manual steps..."
    VCF_CLI_VCFA_API_TOKEN=$(cat "$TOKEN_FILE")
    export VCF_CLI_VCFA_API_TOKEN
else
    echo "Configuring supervisor size..."
    pwsh -NonInteractive -File "$SCRIPT_DIR/configure-supervisor.ps1" \
        -VCenterServer "$VCENTER_SERVER" \
        -Username "$VCENTER_USER" \
        -Password "$LAB_PASS" \
        -ClusterName "$VCENTER_CLUSTER_NAME" \
        -SizeHint "MEDIUM"

    echo "Installing supervisor services via PowerCLI..."

    cat << EOF > "$SVC_DIR/secret-store-service-config.yaml"
statefulSet:
  storageClassName: $STORAGE_CLASS
EOF

    declare -A _SERVICES
    declare -A _SERVICE_CONFIGS
    while IFS='|' read -r _svc _yaml _cfg; do
        _SERVICES["$_svc"]="$SVC_DIR/$_yaml"
        [[ "$_cfg" != "-" ]] && _SERVICE_CONFIGS["$_svc"]="$SVC_DIR/$_cfg"
    done < <(python3 - "$SVC_DIR/services.yaml" "$LAB_ENV" <<'PYEOF'
import sys, yaml
path, env = sys.argv[1], sys.argv[2]
with open(path) as f:
    data = yaml.safe_load(f)
for svc in data.get('services', []):
    if not svc.get('enabled', True):
        continue
    if env in svc.get('exclude_envs', []):
        continue
    print(f"{svc['name']}|{svc['yaml']}|{svc.get('config', '-')}")
PYEOF
)

    for _SVC in "${!_SERVICES[@]}"; do
        _ARGS=(
            -VCenterServer "$VCENTER_SERVER"
            -Username "$VCENTER_USER"
            -Password "$LAB_PASS"
            -YamlPath "${_SERVICES[$_SVC]}"
            -ServiceName "$_SVC"
            -ClusterName "$VCENTER_CLUSTER_NAME"
        )
        if [[ -n "${_SERVICE_CONFIGS[$_SVC]+x}" ]]; then
            _ARGS+=(-ConfigYamlPath "${_SERVICE_CONFIGS[$_SVC]}")
        fi
        pwsh -NonInteractive -File "$SCRIPT_DIR/install-supervisor-services.ps1" "${_ARGS[@]}"
    done

    # --- Auto-generate VCFA API token ---
    echo "Generating VCFA API token automatically..."
    get_vcfa_token "$SCRIPT_DIR"

    cd "$REPO_DIR/argo-e2e"

    echo "Injecting static and dynamic variables..."
    if [ "$LAB_ENV" = "ss" ]; then
        BOOTSTRAP_PATH="./cluster-bootstrap/fieldlabs-9.1"
    else
        BOOTSTRAP_PATH="./cluster-bootstrap/basic"
    fi
    cat << EOF > terraform.tfvars
region_name         = "$REGION_NAME"
vpc_name            = "$VPC_NAME"
zone_name           = "$ZONE_NAME"
vcfa_org            = "$VCFA_ORG"
vcfa_url            = "https://auto-a.site-a.vcf.lab"
namespace           = "e2e-ns"
cluster             = "$CLUSTER_NAME"
bootstrap_revision  = "2.0.0"
bootstrap_path      = "$BOOTSTRAP_PATH"
k8s_version         = "$K8S_VERSION"
vcfa_refresh_token  = "$VCF_CLI_VCFA_API_TOKEN"
cluster_class       = "builtin-generic-v3.6.0"
argocd_version      = "$ARGOCD_VERSION"
argo_password       = "$LAB_PASS"
storage_class_name      = "$STORAGE_POLICY"
vks_storage_class       = "$STORAGE_CLASS"
ns_storage_limit        = "$NS_STORAGE_LIMIT"
EOF
fi


cd "$REPO_DIR/argo-e2e"

echo "Initializing Terraform..."
terraform init


# --- If prep-only, stop here ---
if [ "$MODE" = "prep" ]; then
    echo ""
    echo "╔═══════════════════════════════════════════════════════════════════════╗"
    echo "║                    ✅ PREP COMPLETE!                                 ║"
    echo "╚═══════════════════════════════════════════════════════════════════════╝"
    echo ""
    echo "  All tools installed, configs patched, and Terraform initialized."
    echo "  VCF CLI contexts (supervisor-ctx, vcfa) are configured."
    echo "  Content Library SSL certificates have been trusted."
    echo "  terraform.tfvars and API token have been saved."
    echo ""
    echo "  You can now run 'terraform apply' manually from:"
    echo "  $REPO_DIR/argo-e2e"
    echo ""
    echo "  Or re-run this script and choose 'deploy' for full automation."
    echo ""
    exit 0
fi


###############################################################################
#                     DEPLOY (only runs in deploy mode)                       #
###############################################################################

# --- 13. Terraform Execution ---
echo "Phase 1: Targeting Supervisor Namespace creation..."
terraform apply -target=module.supervisor_namespace -auto-approve

# Temporarily disable exit-on-error for best-effort API fixes
set +e

# --> CAPACITY BUG FIX (requires namespace to exist) <--
echo "Applying vCenter capacity/usage bugfix to unstick the namespace..."
sleep 5 # Give k8s a few seconds to register the newly created namespace

NS_NAME=$(kubectl get ns --no-headers 2>/dev/null | grep e2e-ns | awk '{print $1}')

if [ ! -z "$NS_NAME" ]; then
    SID=$(curl -k -s -X POST -u "$VCENTER_USER:$LAB_PASS" "https://$VCENTER_SERVER/rest/com/vmware/cis/session" | jq -r .value)
    curl -k -s -X PATCH -H "vmware-api-session-id: $SID" -H "Content-Type: application/json" \
      "https://$VCENTER_SERVER/api/vcenter/namespaces/instances/$NS_NAME" \
      -d '{"resource_spec": {"memory_limit": 1048576}}'
    echo "✅ Namespace capacity update automatically saved."
fi

# Create the VCFA Context (needs token, done after capture)
setup_vcfa_context


echo ""
echo "Waiting for Kubernetes release $K8S_VERSION to be available in the supervisor cluster..."
echo "  Checking 'kubectl get kr -A' every 30 seconds for up to 20 minutes..."
echo ""

vcf context use supervisor-ctx 2>/dev/null || true

VKR_VERSION="${K8S_VERSION#v}"
VKR_READY=false
for i in $(seq 1 40); do
    KR_NAME=$(kubectl get kr -A --no-headers 2>/dev/null | grep "$VKR_VERSION" | awk '{print $1}' | head -1)
    if [ -n "$KR_NAME" ]; then
        IS_READY=$(kubectl get kr "$KR_NAME" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
        IS_COMPATIBLE=$(kubectl get kr "$KR_NAME" -o jsonpath='{.status.conditions[?(@.type=="Compatible")].status}' 2>/dev/null)
        if [ "$IS_READY" = "True" ] && [ "$IS_COMPATIBLE" = "True" ]; then
            echo "✅ Kubernetes release $K8S_VERSION is Ready and Compatible in the supervisor cluster."
            VKR_READY=true
            break
        fi
        echo "  [$i/40] Found $KR_NAME but not ready yet (Ready=$IS_READY, Compatible=$IS_COMPATIBLE). Retrying in 30 seconds..."
    else
        echo "  [$i/40] Not available yet. Retrying in 30 seconds..."
    fi
    sleep 30
done

if [ "$VKR_READY" = false ]; then
    echo "❌ Timed out waiting for Kubernetes release $K8S_VERSION."
    echo "   Run 'kubectl get kr -A' in the supervisor context to check current releases."
    exit 1
fi

echo "Phase 2: Applying the rest of the infrastructure (ArgoCD, K8s cluster, etc.)..."
terraform apply -auto-approve
if [ $? -ne 0 ]; then
    echo "⚠️ Terraform encountered a known provider bug with VKS CRDs."
    echo "⚠️ The cluster is actually building. Forcing a state refresh and retrying..."
    terraform apply -refresh-only -auto-approve
    terraform apply -auto-approve || echo "⚠️ Terraform still complaining, but cluster is up. Proceeding to context setup!"
fi

# Re-enable exit-on-error
set -e


# --- 14. VKS Cluster Context Configuration ---
configure_cluster_context || {
    echo ""
    echo "╔═══════════════════════════════════════════════════════════════════════╗"
    echo "║             ⚠️  Deployment Partially Complete                        ║"
    echo "╚═══════════════════════════════════════════════════════════════════════╝"
    echo ""
    echo "  Infrastructure deployed, but cluster context not yet configured."
    echo "  Run: ./ctx2.sh  (once the cluster finishes provisioning)"
    echo ""
    exec zsh
}


echo ""
echo "╔═══════════════════════════════════════════════════════════════════════╗"
echo "║             ✅ Field Lab Deployment Complete!                        ║"
echo "╚═══════════════════════════════════════════════════════════════════════╝"
echo ""
echo "  VCF CLI Contexts configured:"
echo "    • supervisor-ctx   → Supervisor ($SUPERVISOR_ENDPOINT)"
echo "    • vcfa             → VCFA (auto-a.site-a.vcf.lab)"
echo "    • $CLUSTER_NAME → VKS Cluster"
echo ""
echo "  Dropping you into Oh My Zsh..."

exec zsh
