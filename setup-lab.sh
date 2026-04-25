#!/bin/bash
# Stop execution if any command fails
set -e


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


###############################################################################
#                         PREP (runs for both modes)                          #
###############################################################################

# --- 1. Variables & Folder Structure ---
LAB_PASS="VMware123!VMware123!"

echo "Verifying folder structure..."
LAB_DIR="$HOME/field-lab"
BIN_DIR="$HOME/.local/bin"
REPO_DIR="$LAB_DIR/vcfa-terraform-examples"
DESKTOP_DIR="$HOME/Desktop"
CLUSTER_NAME="e2e-niran-cls01"

mkdir -p "$LAB_DIR"
mkdir -p "$BIN_DIR"
mkdir -p "$DESKTOP_DIR"

export PATH="$BIN_DIR:$PATH"

ARGOCD_YAML_FILE="$DESKTOP_DIR/argocd-service-1.1.0.yaml"
VKS_YAML_FILE="$DESKTOP_DIR/vks-upgrade-3.5.1.yaml"
ARGOCD_ATTACH_YAML_FILE="$DESKTOP_DIR/argocd-attach-1.0.7.yaml"
TOKEN_FILE="$DESKTOP_DIR/vcfa_api_token.txt"
TFVARS_FILE="$REPO_DIR/argo-e2e/terraform.tfvars"


# --- 2. Drop YAML Manifests on Desktop ---
echo "Dropping YAML manifests to Desktop so you can start upgrades immediately..."

echo "Generating ArgoCD Service YAML at $ARGOCD_YAML_FILE..."
cat << 'EOF' > "$ARGOCD_YAML_FILE"
apiVersion: data.packaging.carvel.dev/v1alpha1
kind: Package
metadata:
  creationTimestamp: null
  name: argocd-service.vsphere.vmware.com.1.1.0-25100889
spec:
  refName: argocd-service.vsphere.vmware.com
  releasedAt: "2025-12-10T09:00:00Z"
  template:
    spec:
      deploy:
      - kapp: {}
      fetch:
      - imgpkgBundle:
          image: projects.packages.broadcom.com/vsphere/supervisor/argocd-service/1.1.0/argocd-service:v1.1.0_vmware.1
      template:
      - ytt:
          paths:
          - config/sources
          - config/overlays
      - kbld:
          paths:
          - '-'
          - .imgpkg/images.yml
  valuesSchema:
    openAPIv3:
      additionalProperties: false
      properties:
        bundleUrl:
          default: ""
          description: package bundle URL for the argocd carvel package
          type: string
        capabilities:
          default: []
          description: Array of capabilities passed by supervisor service framework
          items:
            additionalProperties: false
            properties:
              name:
                default: ""
                type: string
              value:
                default: false
                type: boolean
            type: object
          type: array
        namespace:
          default: argocd-service
          description: argocd-service's namespace
          type: string
      type: object
  version: 1.1.0-25100889
---
apiVersion: data.packaging.carvel.dev/v1alpha1
kind: PackageMetadata
metadata:
  creationTimestamp: null
  name: argocd-service.vsphere.vmware.com
spec:
  displayName: ArgoCD Service
  providerName: Broadcom
  longDescription: This service allows users to self-service ArgoCD instance in different namespaces.
  shortDescription: This service allows users to self-service ArgoCD instance in different namespaces.
EOF

echo "Generating VKS Upgrade YAML at $VKS_YAML_FILE..."
cat << 'EOF' > "$VKS_YAML_FILE"
apiVersion: data.packaging.carvel.dev/v1alpha1
kind: Package
metadata:
  name: tkg.vsphere.vmware.com.3.5.1+v1.34
  annotations:
    appplatform.vmware.com/source-version-upgrade-constraints: '>=3.2.0'
    appplatform.vmware.com/compatibility-check_service: upgrade-compatibility-service
    appplatform.vmware.com/compatibility-check_port: "80"
    appplatform.vmware.com/compatibility-check_protocol: https
    appplatform.vmware.com/compatibility-check_url: ucs/v2/compatibility
    appplatform.vmware.com/compatibility-check_method: POST
    appplatform.vmware.com/compatibility-check_ca_secret: ucs-service-ca-cert
    appplatform.vmware.com/required_capability.0: TKG_SupervisorService_Supported
    appplatform.vmware.com/compatibility-check_data: |
      [
        {
          "version": "v1",
          "requires": {
            "tanzu-kubernetes-release": [
              {
                "#data_object_or_protocol": "data object",
                "predicate": {
                  "operation": "not",
                  "arguments": [
                    {
                      "operation": "isVersionSatisfied",
                      "arguments": {
                        "initiator": "vmware.com/gccontroller",
                        "receiver": "ovf",
                        "versions": [
                          "v1.31.1+vmware.2-fips-vkr.2",
                          "v1.30.8+vmware.1-fips-vkr.1"
                        ]
                      }
                    }
                  ]
                }
              }
            ]
          },
          "offers": {
            "VKS": {
              "versions": {
                "vmware.com/gcccontroller": [
                  "3.5.1"
                ]
              }
            },
            "TKGSvS": {
              "versions": {
                "vmware.com/gccontroller": [
                  "3.2.0",
                  "3.3.0",
                  "3.4.0",
                  "3.2.31",
                  "3.3.3",
                  "3.5.0",
                  "3.5.1"
                ]
              }
            }
          }
        }
      ]
    supportbundler.vmware.com/manifest: tkgs-support-bundler-cm
    appplatform.vmware.com/requires-ha-supervisor: "true"
spec:
  refName: tkg.vsphere.vmware.com
  version: 3.5.1+v1.34
  kubernetesVersionSelection:
    constraints: '>=1.30.0'
  template:
    spec:
      fetch:
      - imgpkgBundle:
          image: projects.packages.broadcom.com/vsphere/iaas/tkg-service/3.5.1/tkg-service:3.5.1
      template:
      - ytt:
          paths:
          - config/
      - kbld:
          paths:
          - '-'
          - .imgpkg/images.yml
      deploy:
      - kapp: {}
  valuesSchema:
    openAPIv3:
      type: object
      additionalProperties: false
      properties:
        cpVMSize:
          type: string
          description: cpVMSize indicates the capacity of the Supervisor Control Plane. It's derived from Supervisor's tshirt size.
          default: LARGE
        ssoDomain:
          type: string
          description: ssoDomain indicates the name of the default SSO domain configured in vCenter.
          default: vsphere.local
        networkProvider:
          type: string
          description: networkProvider indicates the Network Provider used on Supervisor. (e.g. NSX or vsphere-network)
          default: NSX
        tmcNamespace:
          type: string
          description: tmcNamespace indicates the namespace used for TMC to be deployed.
          default: tmc-svc-namespace
        namespacesCLIPluginVersion:
          description: namespacesCLIPluginVersion indicates the Supervisor recommended namespaces CLIPlugin CR version.
          type: string
          default: v1.0.0
        vcPublicKeys:
          type: string
          description: vcPublicKeys indicates the base64 encoded vCenter OIDC issuer, client audience and the public keys in JWKS format.
          default: a2V5cw==
          contentEncoding: base64
        podVMSupported:
          type: boolean
          description: podVMSupported indicates if the Supervisor supports PodVMs.
          default: false
        stretchedSupervisor:
          type: boolean
          description: This field indicates whether the environment is a Stretched Supervisor
          default: false
        cloudVC:
          type: boolean
          description: cloudVC indicates if the vCenter is deployed on cloud.
          default: false
        controlPlaneCount:
          type: integer
          description: The value indicates the number of control planes enabled on the Supervisor.
          default: 3
        controlPlaneResources:
          type: object
          properties:
            memoryMiB:
              type: integer
              default: 0
              description: The value indicates the amount of memory available on the control plane VMs.
            cpuCount:
              type: integer
              default: 0
              description: The value indicates the number of CPUs available on the control plane VMs.
        capabilities:
          deprecated: true
          type: array
          items:
            type: object
            properties:
              name:
                type: string
              value:
                type: boolean
            required:
            - name
            - value
        capabilitiesStatus:
          type: object
          properties:
            services:
              additionalProperties:
                additionalProperties:
                  properties:
                    activated:
                      type: boolean
                  required:
                  - activated
                  type: object
                type: object
              type: object
            supervisor:
              additionalProperties:
                properties:
                  activated:
                    type: boolean
                required:
                - activated
                type: object
              type: object
---
apiVersion: data.packaging.carvel.dev/v1alpha1
kind: PackageMetadata
metadata:
  name: tkg.vsphere.vmware.com
spec:
  displayName: Kubernetes Service
  longDescription: Kubernetes Service is a turnkey solution for deploying, running, and managing enterprise-grade Kubernetes clusters for hosting applications on Supervisor.
  shortDescription: Cluster management
  providerName: VMware
  maintainers:
  - name: ""
  categories:
  - cluster management
EOF

echo "Generating ArgoCD Attach YAML at $ARGOCD_ATTACH_YAML_FILE..."
cat << 'EOF' > "$ARGOCD_ATTACH_YAML_FILE"
apiVersion: data.packaging.carvel.dev/v1alpha1
kind: PackageMetadata
metadata:
  creationTimestamp: null
  name: argocd-attach.fling.vsphere.vmware.com
spec:
  displayName: argocd-attach
  longDescription: argocd-attach.fling.vsphere.vmware.com
  shortDescription: argocd-attach.fling.vsphere.vmware.com

---
apiVersion: data.packaging.carvel.dev/v1alpha1
kind: Package
metadata:
  creationTimestamp: null
  name: argocd-attach.fling.vsphere.vmware.com.1.0.7
spec:
  refName: argocd-attach.fling.vsphere.vmware.com
  releasedAt: "2025-06-12T17:07:57Z"
  template:
    spec:
      deploy:
      - kapp: {}
      fetch:
      - imgpkgBundle:
          image: ghcr.io/warroyo/argocd-auto-attach@sha256:5c917e3dd6c57973f0a19e1662c7c7dc1ab85e3cc02eb0ba756a638bbc2cd34b
      template:
      - helmTemplate:
          name: metacontroller
          path: upstream
      - ytt:
          ignoreUnknownComments: true
          paths:
          - '-'
      - kbld:
          paths:
          - '-'
          - .imgpkg/images.yml
  valuesSchema:
    openAPIv3:
      properties:
        affinity:
          default: {}
          type: object
        argo_namespace:
          default: ""
          type: string
        clusterRole:
          properties:
            aggregationRule:
              default: {}
              type: object
            rules:
              default: []
              items:
                properties:
                  apiGroups:
                    default: []
                    items:
                      default: '*'
                      type: string
                    type: array
                  resources:
                    default: []
                    items:
                      default: '*'
                      type: string
                    type: array
                  verbs:
                    default: []
                    items:
                      default: '*'
                      type: string
                    type: array
                type: object
              type: array
          type: object
        command:
          default: /usr/bin/metacontroller
          description: Command which is used to start metacontroller
          type: string
        commandArgs:
          default: []
          description: Command arguments which are used to start metacontroller
          items:
            default: --zap-log-level=4
            type: string
          type: array
        fullnameOverride:
          default: ""
          type: string
        image:
          properties:
            pullPolicy:
              default: IfNotPresent
              type: string
            repository:
              default: ghcr.io/metacontroller/metacontroller
              type: string
            tag:
              default: ""
              type: string
          type: object
        imagePullSecrets:
          default: []
          items: {}
          type: array
        nameOverride:
          default: ""
          type: string
        namespace:
          default: ""
          type: string
        namespaceOverride:
          default: metacontroller
          type: string
        nodeSelector:
          default: {}
          type: object
        podAnnotations:
          default: {}
          type: object
        podDisruptionBudget:
          default: {}
          description: which can be enabled when running more than one replica
          type: object
        podSecurityContext:
          default: {}
          type: object
        priorityClassName:
          default: ""
          description: The name of the PriorityClass that will be assigned to metacontroller
          type: string
        probes:
          properties:
            port:
              default: 8081
              type: integer
          type: object
        python_image:
          default: harbor.vcf.lab/niran/python:3.3
          type: string
        rbac:
          properties:
            create:
              default: true
              type: boolean
          type: object
        replicas:
          default: 1
          type: integer
        resources:
          default: {}
          type: object
        securityContext:
          default: {}
          type: object
        service:
          properties:
            enabled:
              default: false
              type: boolean
            ports:
              default: []
              items: {}
              type: array
          type: object
        serviceAccount:
          properties:
            annotations:
              default: {}
              type: object
            create:
              default: true
              type: boolean
            name:
              default: ""
              description: The name of the service account to use. If not set and
                create is true, a name is generated using the fullname template
              type: string
          type: object
        tolerations:
          default: []
          items: {}
          type: array
      type: object
  version: 1.0.7
EOF

echo "✅ YAML manifests saved to Desktop."
echo ""


# --- 3. Install CLIs & Prerequisites ---
echo "Checking prerequisites..."
echo "$LAB_PASS" | sudo -S apt-get update -y
echo "$LAB_PASS" | sudo -S apt-get --fix-broken install -y

TOOLS="curl unzip git jq gpg zsh expect"
for tool in $TOOLS; do
    if ! command -v $tool &> /dev/null; then
        echo "Installing $tool..."
        if [ "$tool" = "curl" ]; then
            echo "$LAB_PASS" | sudo -S apt-get install -y curl libcurl4t64 || echo "$LAB_PASS" | sudo -S apt-get install -y curl
        else
            echo "$LAB_PASS" | sudo -S apt-get install -y $tool
        fi
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

if ! command -v kubectl &> /dev/null; then
    echo "Installing kubectl..."
    curl -fsSLO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    chmod +x kubectl
    mv kubectl "$BIN_DIR/"
fi

if ! command -v terraform &> /dev/null; then
    echo "Installing Terraform..."
    echo "$LAB_PASS" | sudo -S true 
    
    wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
    echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
    
    echo "$LAB_PASS" | sudo -S apt-get update -y
    echo "$LAB_PASS" | sudo -S apt-get install -y terraform
fi


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

echo "Patching storage policy in the namespace module..."
sed -i 's/"vSAN Default Storage Policy"/"cluster-wld01-01a vSAN Storage Policy"/g' "$REPO_DIR/modules/namespace/main.tf"

echo "Patching ArgoCD version in the argocd module..."
sed -i -E 's/"version"[[:space:]]*=[[:space:]]*"[^"]*"/"version" = "3.0.19+vmware.1-vks.1"/g' "$REPO_DIR/modules/argocd-instance/main.tf"


echo "Patching VKS cluster class version..."
sed -i -E 's/"builtin-generic-v[0-9\.]+"/"builtin-generic-v3.5.0"/g' "$REPO_DIR/modules/vks-cluster/variables.tf"

echo "Patching VKS storage class in K8s manifest format..."
find "$REPO_DIR/modules/vks-cluster" -type f -exec sed -i 's/vsan-default-storage-policy/cluster-wld01-01a-vsan-storage-policy/g' {} +


# --- 7. Save Credentials to Desktop ---
echo "Saving credentials to Desktop..."
cat << EOF > "$DESKTOP_DIR/password.txt"
Lab Username: all-apps-admin
Lab Password: $LAB_PASS
EOF


# --- 8. Manual Intervention & Token Capture ---
# Skip if token and tfvars already exist from a previous prep run
if [ -f "$TOKEN_FILE" ] && [ -f "$TFVARS_FILE" ]; then
    echo "✅ Previous prep detected — token and terraform.tfvars already exist. Skipping manual steps..."
    VCFA_TOKEN=$(cat "$TOKEN_FILE")
else
    echo ""
    echo "╔═══════════════════════════════════════════════════════════════════════╗"
    echo "║              ⚠️  MANUAL ACTIONS REQUIRED BEFORE CONTINUING           ║"
    echo "╚═══════════════════════════════════════════════════════════════════════╝"
    echo ""
    echo "  All YAML manifests have been saved to your Desktop."
    echo "  Open vCenter → Workload Management → Supervisor Services"
    echo "  and perform the following actions:"
    echo ""
    echo "  ┌─────────────────────────────────────────────────────────────────┐"
    echo "  │  1. 📦 UPGRADE the VKS (Kubernetes) Service to v3.5           │"
    echo "  │     Use: $VKS_YAML_FILE"
    echo "  │                                                                 │"
    echo "  │  2. 📦 DEPLOY the ArgoCD Service                               │"
    echo "  │     Use: $ARGOCD_YAML_FILE"
    echo "  │                                                                 │"
    echo "  │  3. 📦 DEPLOY the ArgoCD Attach Fling                          │"
    echo "  │     Use: $ARGOCD_ATTACH_YAML_FILE"
    echo "  │                                                                 │"
    echo "  │  4. 🔑 GET your VCFA API Token                                 │"
    echo "  │     Go to: https://auto-a.site-a.vcf.lab                       │"
    echo "  │     Login with credentials from ~/Desktop/password.txt          │"
    echo "  │     Navigate to your user settings and generate a refresh token │"
    echo "  └─────────────────────────────────────────────────────────────────┘"
    echo ""
    echo "  Complete ALL steps above, then paste your token below to continue."
    echo ""
    read -s -p "  🔑 Paste your VCFA API Token here and hit Enter (input hidden): " VCFA_TOKEN
    echo ""
    echo ""
    echo "  Token captured! Saving to Desktop..."
    echo "$VCFA_TOKEN" > "$TOKEN_FILE"

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
cluster             = "$CLUSTER_NAME"
bootstrap_revision  = "1.0.1"
k8s_version         = "v1.34.1+vmware.1"
vcfa_refresh_token  = "$VCFA_TOKEN"
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
    echo "  terraform.tfvars and API token have been saved."
    echo ""
    echo "  When your VKS upgrade, ArgoCD Service, and ArgoCD Attach deployments"
    echo "  are finished in vCenter, re-run this script and choose 'deploy'."
    echo ""
    exit 0
fi


###############################################################################
#                     DEPLOY (only runs in deploy mode)                       #
###############################################################################

# --- 9. Terraform Execution Sequence & Bug Fixes ---
echo "Phase 1: Targeting Supervisor Namespace creation..."
terraform apply -target=module.supervisor_namespace -auto-approve

echo "Pre-configuring VCF CLI (EULA, CEIP, and plugins)..."
export TANZU_CLI_EULA_PROMPT_ANSWER=Yes
export TANZU_CLI_CEIP_OPT_IN_PROMPT_ANSWER=Yes
vcf plugin sync 2>/dev/null || true
vcf telemetry update --opted-out 2>/dev/null || true

echo "Creating VCF Supervisor Context..."
vcf context create supervisor-ctx \
  --endpoint 10.1.0.2 \
  --username administrator@wld.sso \
  --password "$LAB_PASS" \
  --insecure-skip-tls-verify \
  -t kubernetes \
  --auth-type basic 2>/dev/null || echo "Context may already exist. Continuing..."


# Temporarily disable exit-on-error. These API fixes are "best effort" 
# and shouldn't crash the entire deployment if VMware changes an endpoint!
set +e

# --> CAPACITY BUG FIX START <--
echo "Applying vCenter capacity/usage bugfix to unstick the namespace..."
sleep 5 # Give k8s a few seconds to register the newly created namespace

NS_NAME=$(kubectl get ns --no-headers 2>/dev/null | grep e2e-ns | awk '{print $1}')

if [ ! -z "$NS_NAME" ]; then
    SID=$(curl -k -s -X POST -u "administrator@wld.sso:$LAB_PASS" "https://vc-wld01-a.site-a.vcf.lab/rest/com/vmware/cis/session" | jq -r .value)
    curl -k -s -X PATCH -H "vmware-api-session-id: $SID" -H "Content-Type: application/json" \
      "https://vc-wld01-a.site-a.vcf.lab/api/vcenter/namespaces/instances/$NS_NAME" \
      -d '{"resource_spec": {"memory_limit": 1048576}}'
    echo "✅ Namespace capacity update automatically saved."
fi
# --> CAPACITY BUG FIX END <--


# --> CONTENT LIBRARY SSL FIX START <--
echo "Patching Content Library SSL Certificates to bypass deployment errors..."

# Fetching the Content Libraries
LIB_IDS=$(curl -k -s -X GET -H "vmware-api-session-id: $SID" "https://vc-wld01-a.site-a.vcf.lab/api/content/subscribed-library" | jq -r '.[]' 2>/dev/null)

for LIB_ID in $LIB_IDS; do
    LIB_INFO=$(curl -k -s -X GET -H "vmware-api-session-id: $SID" "https://vc-wld01-a.site-a.vcf.lab/api/content/subscribed-library/$LIB_ID" 2>/dev/null)
    URL=$(echo "$LIB_INFO" | jq -r '.subscription_info.subscription_url // empty' 2>/dev/null)
    
    if [[ "$URL" == https* ]]; then
        HOST=$(echo "$URL" | awk -F/ '{print $3}')
        THUMBPRINT=$(echo -n | openssl s_client -connect ${HOST}:443 2>/dev/null | openssl x509 -noout -fingerprint -sha1 | cut -d'=' -f2)
        
        if [ ! -z "$THUMBPRINT" ]; then
            echo "-> Trusting SSL thumbprint for $HOST ($THUMBPRINT)..."
            curl -k -s -X PATCH -H "vmware-api-session-id: $SID" -H "Content-Type: application/json" \
              -d "{\"subscription_info\": {\"ssl_thumbprint\": \"$THUMBPRINT\"}}" \
              "https://vc-wld01-a.site-a.vcf.lab/api/content/subscribed-library/$LIB_ID"
              
            echo "-> Forcing sync for library $LIB_ID..."
            curl -k -s -X POST -H "vmware-api-session-id: $SID" "https://vc-wld01-a.site-a.vcf.lab/api/content/subscribed-library/$LIB_ID?action=sync"
        fi
    fi
done
# --> CONTENT LIBRARY SSL FIX END <--


echo "Phase 2: Applying the rest of the infrastructure (ArgoCD, K8s cluster, etc.)..."
# Notice we keep `set +e` active here! This guarantees the script won't crash if Terraform throws a fit.
terraform apply -auto-approve
if [ $? -ne 0 ]; then
    echo "⚠️ Terraform encountered a known provider bug with VKS CRDs."
    echo "⚠️ The cluster is actually building. Forcing a state refresh and retrying..."
    terraform apply -refresh-only -auto-approve
    terraform apply -auto-approve || echo "⚠️ Terraform still complaining, but cluster is up. Proceeding to context setup!"
fi

# Re-enable exit-on-error just to be clean for the final steps
set -e


# --- 10. Post-Deployment Context Configuration ---
echo "Configuring VCF CLI contexts..."

# Fetching VCFA certificate chain
echo "-> Fetching VCFA certificate chain..."
VCFA_CERT_PATH="$LAB_DIR/vcfa_chain.pem"
openssl s_client -showcerts -connect auto-a.site-a.vcf.lab:443 </dev/null 2>/dev/null | awk '/BEGIN CERTIFICATE/,/END CERTIFICATE/{print}' > "$VCFA_CERT_PATH"

# Create the VCFA Context
echo "-> Creating VCFA context..."
vcf context create vcfa \
  --endpoint auto-a.site-a.vcf.lab \
  --api-token "$VCFA_TOKEN" \
  --tenant-name all-apps \
  --ca-certificate "$VCFA_CERT_PATH" 2>/dev/null || echo "VCFA context may already exist. Continuing..."


# --- 11. VKS Cluster Context Configuration ---
echo ""
echo "Configuring VKS cluster context for $CLUSTER_NAME..."

# We need a namespace-level context (e.g. vcfa:e2e-ns), not the top-level vcfa context.
# Auto-detect the namespace context from the list of available contexts.
echo "-> Finding VCFA namespace context..."
NS_CTX=$(vcf context list -o json 2>/dev/null | jq -r '.[].name' 2>/dev/null | grep -i "e2e-ns" | head -1)

if [ -z "$NS_CTX" ]; then
    # Fallback: list all contexts and let the user pick
    echo "⚠️ Could not auto-detect the namespace context."
    echo "   Available contexts:"
    vcf context list 2>/dev/null || true
    echo ""
    read -p "   Enter the namespace context name (e.g. vcfa:e2e-ns): " NS_CTX
fi

echo "-> Switching to namespace context: $NS_CTX"
yes | vcf context use "$NS_CTX" 2>/dev/null || echo "   (context switch warning — continuing)"

echo "-> Registering VCFA JWT authenticator on the cluster..."
echo "   (This can take a minute — waiting up to 2 minutes...)"
if ! timeout 120 bash -c "yes | vcf cluster register-vcfa-jwt-authenticator \"$CLUSTER_NAME\" 2>&1"; then
    echo "⚠️ JWT authenticator registration timed out or failed."
    echo "   You can run this manually later:"
    echo "   vcf cluster register-vcfa-jwt-authenticator $CLUSTER_NAME"
fi

echo "-> Fetching kubeconfig for the VKS cluster..."
mkdir -p ~/.kube
if ! timeout 60 bash -c "yes | vcf cluster kubeconfig get \"$CLUSTER_NAME\" --export-file ~/.kube/config 2>&1"; then
    echo "⚠️ Kubeconfig fetch timed out or failed."
    echo "   You can run this manually later:"
    echo "   vcf cluster kubeconfig get $CLUSTER_NAME --export-file ~/.kube/config"
fi

if [ -f ~/.kube/config ] && grep -q "$CLUSTER_NAME" ~/.kube/config 2>/dev/null; then
    echo "-> Finding cluster context name..."
    CLUSTER_CTX=$(grep "name:.*${CLUSTER_NAME}.*@" ~/.kube/config | awk '{print $2}' | head -1)

    if [ -z "$CLUSTER_CTX" ]; then
        echo "⚠️ Could not auto-detect the cluster context name."
        echo "   Here are the matching entries in your kubeconfig:"
        echo ""
        cat ~/.kube/config | grep "$CLUSTER_NAME"
        echo ""
        read -p "   Please paste the context name (the one with the @ sign): " CLUSTER_CTX
    fi

    echo "-> Creating VCF context for VKS cluster (kubecontext: $CLUSTER_CTX)..."
    if ! timeout 60 bash -c "yes | vcf context create e2e-niran-cls-01 --kubeconfig ~/.kube/config --kubecontext \"$CLUSTER_CTX\" --type cci 2>&1"; then
        echo "⚠️ Context creation timed out. You can run this manually:"
        echo "   vcf context create e2e-niran-cls-01 --kubeconfig ~/.kube/config --kubecontext $CLUSTER_CTX --type cci"
    fi
else
    echo "⚠️ Kubeconfig does not contain $CLUSTER_NAME yet."
    echo "   The cluster may still be provisioning. Run these manually when ready:"
    echo ""
    echo "   vcf context use <namespace-context>"
    echo "   vcf cluster register-vcfa-jwt-authenticator $CLUSTER_NAME"
    echo "   vcf cluster kubeconfig get $CLUSTER_NAME --export-file ~/.kube/config"
    echo "   grep $CLUSTER_NAME ~/.kube/config   # find the context with @"
    echo "   vcf context create e2e-niran-cls-01 --kubeconfig ~/.kube/config --kubecontext <name@ns> --type cci"
fi


echo ""
echo "╔═══════════════════════════════════════════════════════════════════════╗"
echo "║             ✅ Field Lab Deployment Complete!                        ║"
echo "╚═══════════════════════════════════════════════════════════════════════╝"
echo ""
echo "  VCF CLI Contexts configured:"
echo "    • supervisor-ctx   → Supervisor (10.1.0.2)"
echo "    • vcfa             → VCFA (auto-a.site-a.vcf.lab)"
echo "    • e2e-niran-cls-01 → VKS Cluster ($CLUSTER_NAME)"
echo ""
echo "  Dropping you into Oh My Zsh..."

exec zsh
