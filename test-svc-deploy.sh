#!/bin/bash
# Refined script for automating Supervisor Services via vCenter REST API.

VCENTER="https://vc-wld01-a.site-a.vcf.lab"
VCENTER_USER="administrator@wld.sso"
VCENTER_PASS="VMware123!VMware123!"
SUPERVISOR_CLUSTER="domain-c8"
DESKTOP_DIR="$HOME/Desktop"

ACTION="${1:-list}"

echo ""
echo "╔═══════════════════════════════════════════╗"
echo "║   Supervisor Services API Test Script     ║"
echo "╚═══════════════════════════════════════════╝"
echo ""

# --- 1. Authenticate ---
echo "-> Authenticating to vCenter..."
# Using -u for Basic Auth to get the Session ID
SID=$(curl -k -s -X POST -u "$VCENTER_USER:$VCENTER_PASS" "$VCENTER/api/session" | tr -d '"')

if [ -z "$SID" ] || [ "$SID" = "null" ]; then
    echo "    Trying legacy session endpoint..."
    SID=$(curl -k -s -u "$VCENTER_USER:$VCENTER_PASS" -X POST "$VCENTER/rest/com/vmware/cis/session" | jq -r '.value')
fi

if [ -z "$SID" ] || [ "$SID" = "null" ]; then
    echo "❌ Failed to authenticate to vCenter."
    exit 1
fi
echo "   ✅ Authenticated (session: ${SID:0:12}...)"
echo ""

# --- Helper: Fetch Services ---
fetch_services() {
    SERVICES_RAW=$(curl -k -s -X GET \
      -H "vmware-api-session-id: $SID" \
      "$VCENTER/api/vcenter/namespace-management/supervisor-services")
}

# --- 2. List Services ---
list_services() {
    echo "-> Listing existing Supervisor Services..."
    fetch_services
    echo "$SERVICES_RAW" | jq -r '.[] | "  ID: \(.supervisor_service // .service // "?")  |  Name: \(.display_name // "?")  |  State: \(.state // "?")"' 2>/dev/null || echo "$SERVICES_RAW"
}

# --- Helper: Register a version for a service ---
register_version() {
    local SVC_ID="$1"
    local YAML_FILE="$2"
    local LABEL="$3"
    local CONTENT_TYPE="${4:-VSPHERE}"

    if [ ! -f "$YAML_FILE" ]; then
        echo "   ❌ YAML file not found: $YAML_FILE"
        return 1
    fi

    echo "-> Registering $LABEL version..."
    
    # Create JSON payload using a robust HereDoc to handle special characters/newlines
    local PAYLOAD_FILE=$(mktemp /tmp/svc-payload.XXXXXX.json)
    
    python3 <<EOF
import json
try:
    with open('$YAML_FILE', 'r') as f:
        yaml_content = f.read()
    payload = {
        'spec': {
            'content_type': '$CONTENT_TYPE',
            'content': yaml_content
        }
    }
    with open('$PAYLOAD_FILE', 'w') as out:
        json.dump(payload, out)
except Exception as e:
    print(f"Python Error: {e}")
EOF

    if [ ! -s "$PAYLOAD_FILE" ]; then
        echo "   ❌ Error: Failed to generate payload file."
        return 1
    fi

    # Using --data-binary to prevent curl from stripping newlines
    local RESPONSE=$(curl -k -s -w "\nHTTP_CODE:%{http_code}" -X POST \
      -H "vmware-api-session-id: $SID" \
      -H "Content-Type: application/json" \
      "$VCENTER/api/vcenter/namespace-management/supervisor-services/$SVC_ID/versions" \
      --data-binary "@$PAYLOAD_FILE")

    rm -f "$PAYLOAD_FILE"

    local HTTP_CODE=$(echo "$RESPONSE" | tail -n1 | cut -d: -f2)
    local BODY=$(echo "$RESPONSE" | sed '$d')

    echo "   HTTP Status: $HTTP_CODE"
    if [[ "$HTTP_CODE" =~ ^20[0-9]$ ]]; then
        echo "   ✅ Version registered successfully!"
    else
        echo "   Response:"
        echo "$BODY" | jq '.' 2>/dev/null || echo "$BODY"
        
        # Retry logic for CARVEL if VSPHERE failed
        if [ "$CONTENT_TYPE" = "VSPHERE" ]; then
             echo "   Retrying with content_type=CARVEL..."
             register_version "$SVC_ID" "$YAML_FILE" "$LABEL" "CARVEL"
        fi
    fi
}

# --- Helper: Install/Upgrade on Cluster ---
install_on_supervisor() {
    local SVC_ID="$1"
    local VERSION="$2"
    
    echo "-> Triggering Install/Upgrade to v$VERSION on $SUPERVISOR_CLUSTER..."
    
    # We try PATCH first as it is used for upgrades/re-configs
    local RESPONSE=$(curl -k -s -w "\nHTTP_CODE:%{http_code}" -X PATCH \
      -H "vmware-api-session-id: $SID" \
      -H "Content-Type: application/json" \
      "$VCENTER/api/vcenter/namespace-management/clusters/$SUPERVISOR_CLUSTER/supervisor-services/$SVC_ID" \
      -d "{\"spec\": {\"version\": \"$VERSION\"}}")

    local HTTP_CODE=$(echo "$RESPONSE" | tail -n1 | cut -d: -f2)
    echo "   HTTP Status: $HTTP_CODE"
}

# --- Main Logic ---
case "$ACTION" in
    list)
        list_services
        ;;
    vks)
        fetch_services
        VKS_SVC_ID=$(echo "$SERVICES_RAW" | jq -r '.[] | select(.display_name | test("Kubernetes|TKG|VKS"; "i")) | .supervisor_service // .service' 2>/dev/null | head -1)
        if [ -n "$VKS_SVC_ID" ]; then
            register_version "$VKS_SVC_ID" "$DESKTOP_DIR/vks-upgrade-3.5.1.yaml" "VKS v3.5.1"
            # Note: Registration only adds the version to the catalog. 
            # You must call install_on_supervisor to actually trigger the upgrade on the cluster.
            install_on_supervisor "$VKS_SVC_ID" "3.5.1"
        else
            echo "❌ Could not find VKS service ID."
        fi
        ;;
    *)
        echo "Usage: $0 [list|vks]"
        exit 1
        ;;
esac

echo ""
echo "Done."
