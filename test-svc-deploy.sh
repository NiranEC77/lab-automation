#!/bin/bash
# Supervisor Services Automation - Pipe Method

VCENTER="https://vc-wld01-a.site-a.vcf.lab"
VCENTER_USER="administrator@wld.sso"
VCENTER_PASS="VMware123!VMware123!"
SUPERVISOR_CLUSTER="domain-c8"
DESKTOP_DIR="$HOME/Desktop"

ACTION="${1:-list}"

# --- 1. Authenticate ---
echo "-> Authenticating..."
SID=$(curl -k -s -X POST -u "$VCENTER_USER:$VCENTER_PASS" "$VCENTER/api/session" | tr -d '"')

if [ -z "$SID" ] || [ "$SID" = "null" ]; then
    SID=$(curl -k -s -u "$VCENTER_USER:$VCENTER_PASS" -X POST "$VCENTER/rest/com/vmware/cis/session" | jq -r '.value')
fi

[ -z "$SID" ] || [ "$SID" = "null" ] && echo "❌ Auth Failed" && exit 1
echo "   ✅ Authenticated"

# --- Helper: Register Version (The Pipe Method) ---
register_version() {
    local SVC_ID="$1"
    local YAML_FILE="$2"
    local LABEL="$3"
    local CONTENT_TYPE="${4:-VSPHERE}"

    echo "-> Registering $LABEL ($CONTENT_TYPE)..."

    # Generate JSON and pipe it directly to curl using -d @-
    local RESPONSE=$(python3 -c "
import json
with open('$YAML_FILE', 'r') as f:
    print(json.dumps({'spec': {'content_type': '$CONTENT_TYPE', 'content': f.read()}}))
" | curl -k -s -w "\nHTTP_CODE:%{http_code}" -X POST \
      -H "vmware-api-session-id: $SID" \
      -H "Content-Type: application/json" \
      -d @- \
      "$VCENTER/api/vcenter/namespace-management/supervisor-services/$SVC_ID/versions")

    local HTTP_CODE=$(echo "$RESPONSE" | tail -n1 | cut -d: -f2)
    echo "   HTTP Status: $HTTP_CODE"

    if [[ ! "$HTTP_CODE" =~ ^20[0-9]$ ]] && [ "$CONTENT_TYPE" = "VSPHERE" ]; then
        echo "   Retrying as CARVEL..."
        register_version "$SVC_ID" "$YAML_FILE" "$LABEL" "CARVEL"
    fi
}

# --- Helper: Trigger Upgrade ---
upgrade_service() {
    local SVC_ID="$1"
    local VERSION="$2"
    echo "-> Patching Cluster to version $VERSION..."
    curl -k -s -o /dev/null -X PATCH \
      -H "vmware-api-session-id: $SID" \
      -H "Content-Type: application/json" \
      -d "{\"spec\": {\"version\": \"$VERSION\"}}" \
      "$VCENTER/api/vcenter/namespace-management/clusters/$SUPERVISOR_CLUSTER/supervisor-services/$SVC_ID"
    echo "   ✅ Upgrade command sent."
}

# --- Main ---
case "$ACTION" in
    list)
        curl -k -s -H "vmware-api-session-id: $SID" "$VCENTER/api/vcenter/namespace-management/supervisor-services" | jq -r '.[] | "\(.display_name) (\(.supervisor_service // .service))"'
        ;;
    vks)
        # 1. Register the version in the catalog
        register_version "tkg.vsphere.vmware.com" "$DESKTOP_DIR/vks-upgrade-3.5.1.yaml" "VKS v3.5.1"
        # 2. Tell the cluster to actually use that version
        upgrade_service "tkg.vsphere.vmware.com" "3.5.1"
        ;;
    *)
        echo "Usage: $0 [list|vks]"
        ;;
esac
