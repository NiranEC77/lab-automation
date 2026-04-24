#!/bin/bash
# Stop execution if any command fails
set -e

# --- 1. Variables & Folder Structure ---
LAB_PASS="VMware123!VMware123!"

echo "Verifying folder structure..."
LAB_DIR="$HOME/field-lab"
BIN_DIR="$HOME/.local/bin"
REPO_DIR="$LAB_DIR/vcfa-terraform-examples"
DESKTOP_DIR="$HOME/Desktop"

mkdir -p "$LAB_DIR"
mkdir -p "$BIN_DIR"
mkdir -p "$DESKTOP_DIR"

export PATH="$BIN_DIR:$PATH"

# --- 2. Install CLIs & Prerequisites ---
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


# --- 3. Setup Zsh & Oh My Zsh ---
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


# --- 4. Setup Aliases ---
echo "Setting up aliases..."
cat << 'EOF' > "$HOME/.lab_aliases"
alias k='kubectl'
alias tf='terraform'
EOF

if ! grep -q ".lab_aliases" "$HOME/.zshrc"; then
    echo "source $HOME/.lab_aliases" >> "$HOME/.zshrc"
fi


# --- 5. Pull Git Repo & Patch Modules ---
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
sed -i 's/"builtin-generic-v3.4.0"/"builtin-generic-v3.6.2"/g' "$REPO_DIR/modules/vks-cluster/variables.tf"

echo "Patching VKS storage class in K8s manifest format..."
find "$REPO_DIR/modules/vks-cluster" -type f -exec sed -i 's/vsan-default-storage-policy/cluster-wld01-01a-vsan-storage-policy/g' {} +


# --- 6. Drop YAML Manifests (Desktop) ---
ARGOCD_YAML_FILE="$DESKTOP_DIR/argocd-service-1.1.0.yaml"
VKS_YAML_FILE="$DESKTOP_DIR/vks-upgrade-3.6.2.yaml"

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
  name: tkg.vsphere.vmware.com.3.6.2+v1.35
  annotations:
    appplatform.vmware.com/source-version-upgrade-constraints: '>=3.3.0'
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
          "offers": {
            "VKS": {
              "versions": {
                "vmware.com/gcccontroller": [
                  "3.6.2"
                ]
              }
            },
            "TKGSvS": {
              "versions": {
                "vmware.com/gccontroller": [
                  "3.3.0",
                  "3.3.3",
                  "3.4.0",
                  "3.4.1",
                  "3.4.2",
                  "3.5.0",
                  "3.5.1",
                  "3.6.0",
                  "3.6.1",
                  "3.6.2"
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
  version: 3.6.2+v1.35
  kubernetesVersionSelection:
    constraints: '>1.30.0'
  template:
    spec:
      fetch:
      - imgpkgBundle:
          image: projects.packages.broadcom.com/vsphere/iaas/vsphere-kubernetes-service/3.6.2/vsphere-kubernetes-service:3.6.2
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
        misconfiguredSoftwareChecksDryrunIntervalDuration:
          type: string
          description: Duration after which the dry-run controller should be run again. Examples are '24h', '1d23h45m12s' etc. Defaults to 24h.
          default: 24h
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


# --- 7. Save Credentials to Desktop ---
echo "Saving credentials to Desktop..."
cat << EOF > "$DESKTOP_DIR/password.txt"
Lab Username: all-apps-admin
Lab Password: $LAB_PASS
EOF


# --- 8. Manual Intervention & Token Capture ---
echo ""
echo "====================================================================="
echo "⚠️  MANUAL ACTION REQUIRED: DEPLOY ARGOCD, UPGRADE VKS, & GET TOKEN"
echo "1. Log into vCenter and navigate to Workload Management -> Services."
echo "2. Deploy the ArgoCD Service."
echo "   (If needed, use $ARGOCD_YAML_FILE)"
echo "3. Upgrade the vSphere Kubernetes Service (VKS)."
echo "   (If needed, use $VKS_YAML_FILE)"
echo "4. WHILE they install, go to VCFA (https://auto-a.site-a.vcf.lab) and get your API token."
echo "   (Credentials are saved on your Desktop in password.txt)"
echo "====================================================================="
echo ""
read -s -p "🔑 Paste your VCFA API Token here and hit Enter (input hidden): " VCFA_TOKEN
echo ""
echo "Token captured! Resuming automation..."

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


# --- 9. Terraform Execution Sequence & Bug Fixes ---
echo "Initializing Terraform..."
terraform init

echo "Phase 1: Targeting Supervisor Namespace creation..."
terraform apply -target=module.supervisor_namespace -auto-approve

echo "Creating VCF Supervisor Context (waiting for plugins if needed)..."
cat << EOF > vcf-login.exp
#!/usr/bin/expect -f
set timeout -1
spawn vcf context create supervisor-ctx --endpoint 10.1.0.2 --username administrator@wld.sso --insecure-skip-tls-verify -t kubernetes --auth-type basic
expect -nocase "*password*"
send "$LAB_PASS\r"
expect eof
EOF

chmod +x vcf-login.exp
./vcf-login.exp
rm -f vcf-login.exp


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

# Re-enable exit-on-error for the final Terraform apply
set -e


echo "Phase 2: Applying the rest of the infrastructure (ArgoCD, K8s cluster, etc.)..."
terraform apply -auto-approve

echo "========================================="
echo "✅ Field Lab deployment successfully completed!"
echo "========================================="
echo "Dropping you into Oh My Zsh immediately..."

exec zsh
