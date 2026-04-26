#!/bin/bash
# Supervisor Services Automation - Debug & Pipe Method

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

if [ -z "$SID" ] || [ "$SID" = "null" ]; then echo "❌ Auth Failed"; exit 1; fi
echo "   ✅ Authenticated"

# --- Helper: Register Version ---
register_version() {
    local SVC_ID="$1"
    local YAML_FILE="$2"
    local LABEL="$3"
    local CONTENT_TYPE="${4:-VSPHERE}"

    echo "-> Registering $LABEL ($CONTENT_TYPE)..."

    # Use Python to generate the JSON and pipe it to curl
    # Note: We capture both the Body and the HTTP Code
    local RESPONSE=$(python3 -c "
import json
try:
    with open('$YAML_FILE', 'r') as f:
        print(json.dumps({'spec': {'content_type': '$CONTENT_TYPE', 'content': f.read()}}))
except Exception as e:
    pass
" | curl -k -s -w "\nHTTP_CODE:%{http_code}" -X POST \
      -H "vmware-api-session-id: $SID" \
      -H "Content-Type: application/json" \
      -d @- \
      "$VCENTER/api/vcenter/namespace-management/supervisor-services/$SVC_ID/versions")

    local HTTP_CODE=$(echo "$RESPONSE" | tail -n1 | cut -d: -f2)
    local BODY=$(echo "$RESPONSE" | sed '$d')

    if [[ "$HTTP_CODE" =~ ^20[0-9]$ ]]; then
        echo "   ✅ Version registered successfully!"
        return 0
    else
        echo "   ❌ Failed with Status: $HTTP_CODE"
        echo "   Detailed Error: $BODY"
        
        # If it failed because it already exists, that's actually a 'success' for us
        if [[ "$BODY" == *"already exists"* ]]; then
            echo "   Proceeding because version is already present in catalog."
            return 0
        fi

        if [ "$CONTENT_TYPE" = "VSPHERE" ]; then
            echo "   Retrying as CARVEL..."
            register_version "$SVC_ID" "$YAML_FILE" "$LABEL" "CARVEL"
            return $?
        fi
        return 1
    fi
}

# --- Helper: Trigger Upgrade ---
upgrade_service() {
    local SVC_ID="$1"
    local VERSION="$2"
    echo "-> Patching Cluster $SUPERVISOR_CLUSTER to version $VERSION..."
    
    local RESPONSE=$(curl -k -s -w "\nHTTP_CODE:%{http_code}" -X PATCH \
      -H "vmware-api-session-id: $SID" \
      -H "Content-Type: application/json" \
      -d "{\"spec\": {\"version\": \"$VERSION\"}}" \
      "$VCENTER/api/vcenter/namespace-management/clusters/$SUPERVISOR_CLUSTER/supervisor-services/$SVC_ID")
    
    local HTTP_CODE=$(echo "$RESPONSE" | tail -n1 | cut -d: -f2)
    local BODY=$(echo "$RESPONSE" | sed '$d')

    if [[ "$HTTP_CODE" =~ ^20[0-9]$ ]]; then
        echo "   ✅ Upgrade command accepted by vCenter."
    else
        echo "   ❌ Patch Failed ($HTTP_CODE): $BODY"
    fi
}

# --- Main ---
case "$ACTION" in
    list)
        echo "Listing Services..."
        curl -k -s -H "vmware-api-session-id: $SID" "$VCENTER/api/vcenter/namespace-management/supervisor-services" | jq -r '.[] | "Name: \(.display_name) | ID: \(.supervisor_service // .service)"'
        ;;
    vks)
        # We try to register first. If it returns 0 (Success or Already Exists), we patch.
        if register_version "tkg.vsphere.vmware.com" "$DESKTOP_DIR/vks-upgrade-3.5.1.yaml" "VKS v3.5.1"; then
            echo ""
            upgrade_service "tkg.vsphere.vmware.com" "3.5.1"
        else
            echo ""
            echo "❌ Registration failed. Skipping Patch command to avoid false positives."
        fi
        ;;
    *)
        echo "Usage: $0 [list|vks]"
        ;;
esac
