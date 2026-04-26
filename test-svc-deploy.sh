#!/bin/bash
# VKS Upgrade - URL Encoded & Direct Injection Method

VCENTER="https://vc-wld01-a.site-a.vcf.lab"
VCENTER_USER="administrator@wld.sso"
VCENTER_PASS="VMware123!VMware123!"
SUPERVISOR_CLUSTER="domain-c8"
YAML_PATH="$HOME/Desktop/vks-upgrade-3.5.1.yaml"

# URL Encoded ID for tkg.vsphere.vmware.com
SVC_ID="tkg.vsphere.vmware.com"

# 1. AUTH
SID=$(curl -k -s -u "$VCENTER_USER:$VCENTER_PASS" -X POST "$VCENTER/api/session" | tr -d '"')
if [ -z "$SID" ] || [ "$SID" == "null" ]; then echo "❌ Auth Fail"; exit 1; fi

# 2. REGISTER (Direct JSON construction in Python to avoid shell escaping)
echo "-> Attempting Registration of $SVC_ID..."

python3 -c "
import json, requests, urllib3
urllib3.disable_warnings()

with open('$YAML_PATH', 'r') as f:
    yaml_content = f.read()

url = '$VCENTER/api/vcenter/namespace-management/supervisor-services/$SVC_ID/versions'
headers = {
    'vmware-api-session-id': '$SID',
    'Content-Type': 'application/json'
}
payload = {'spec': {'content_type': 'VSPHERE', 'content': yaml_content}}

resp = requests.post(url, json=payload, verify=False)
print(f'Status: {resp.status_code}')
print(f'Body: {resp.text}')
"

# 3. PATCH
echo "-> Sending Patch..."
curl -k -s -X PATCH \
  -H "vmware-api-session-id: $SID" \
  -H "Content-Type: application/json" \
  -d "{\"spec\": {\"version\": \"3.5.1\"}}" \
  "$VCENTER/api/vcenter/namespace-management/clusters/$SUPERVISOR_CLUSTER/supervisor-services/$SVC_ID"

echo "Done."
