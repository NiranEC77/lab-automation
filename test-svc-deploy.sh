#!/bin/bash
# =================================================================
# VKS / Supervisor Service Automation Script
# Handles Authentication, Registration (via Pipe), and Upgrade Patch
# =================================================================

VCENTER="https://vc-wld01-a.site-a.vcf.lab"
VCENTER_USER="administrator@wld.sso"
VCENTER_PASS="VMware123!VMware123!"
SUPERVISOR_CLUSTER="domain-c8"
DESKTOP_DIR="$HOME/Desktop"
YAML_PATH="$DESKTOP_DIR/vks-upgrade-3.5.1.yaml"
SVC_ID="tkg.vsphere.vmware.com"

echo "-> Starting VKS Upgrade Automation..."

# 1. AUTHENTICATION
# Gets the session ID required for all subsequent API calls
SID=$(curl -k -s -u "$VCENTER_USER:$VCENTER_PASS" -X POST "$VCENTER/api/session" | tr -d '"')

if [ -z "$SID" ] || [ "$SID" = "null" ]; then
    echo "❌ Authentication failed. Check your credentials or VCenter URL."
    exit 1
fi
echo "✅ Authenticated."

# 2. VERSION REGISTRATION
# This uploads the YAML content to the vCenter Service Catalog.
# We use Python to format the JSON and pipe it (@-) to avoid 'curl' file-read errors.
echo "-> Registering version from $YAML_PATH..."

REG_RESPONSE=$(python3 -c "
import json, sys
try:
    with open('$YAML_PATH', 'r') as f:
        content = f.read()
    print(json.dumps({'spec': {'content_type': 'VSPHERE', 'content': content}}))
except Exception as e:
    print(f'PYTHON_ERROR: {e}', file=sys.stderr)
    sys.exit(1)
" | curl -k -s -X POST \
      -H "vmware-api-session-id: $SID" \
      -H "Content-Type: application/json" \
      -d @- \
      "$VCENTER/api/vcenter/namespace-management/supervisor-services/$SVC_ID/versions")

# 3. ERROR CHECKING
# If the registration failed (HTTP 400), this block prints the REASON.
echo "------------------------------------------------------------"
echo "VCENTER API RESPONSE:"
echo "$REG_RESPONSE" | jq '.' 2>/dev/null || echo "$REG_RESPONSE"
echo "------------------------------------------------------------"

# 4. UPGRADE PATCH
# This command tells the Supervisor Cluster to actually start using the new version.
# Note: Version '3.5.1' must match the 'version' field inside your YAML.
echo "-> Sending Patch command to Cluster $SUPERVISOR_CLUSTER..."
PATCH_STATUS=$(curl -k -s -o /dev/null -w "%{http_code}" -X PATCH \
  -H "vmware-api-session-id: $SID" \
  -H "Content-Type: application/json" \
  -d "{\"spec\": {\"version\": \"3.5.1\"}}" \
  "$VCENTER/api/vcenter/namespace-management/clusters/$SUPERVISOR_CLUSTER/supervisor-services/$SVC_ID")

if [ "$PATCH_STATUS" == "204" ] || [ "$PATCH_STATUS" == "200" ]; then
    echo "✅ Upgrade successfully initiated (HTTP $PATCH_STATUS)."
else
    echo "❌ Patch failed with status $PATCH_STATUS. Check if version '3.5.1' is correct."
fi

echo "-> Workflow Complete."
