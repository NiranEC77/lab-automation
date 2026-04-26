#!/bin/bash
# Test script for automating Supervisor Services deployment via vCenter REST API.
# Attempts to register service versions and install them without the vCenter UI.
#
# Usage: ./test-svc-deploy.sh [vks|argocd|argoattach|all|list]
#   list       - List existing supervisor services (default)
#   vks        - Register VKS v3.5.1 upgrade
#   argocd     - Register & install ArgoCD Service
#   argoattach - Register & install ArgoCD Attach Fling
#   all        - Do everything

VCENTER="https://vc-wld01-a.site-a.vcf.lab"
VCENTER_USER="administrator@wld.sso"
VCENTER_PASS="VMware123!VMware123!"
SUPERVISOR_CLUSTER="domain-c8"
DESKTOP_DIR="$HOME/Desktop"

ACTION="${1:-list}"

echo ""
echo "╔═══════════════════════════════════════════╗"
echo "║  Supervisor Services API Test Script      ║"
echo "╚═══════════════════════════════════════════╝"
echo ""
echo "Action: $ACTION"
echo ""


# --- Helper: Convert YAML file to JSON-escaped string ---
yaml_to_json_string() {
    python3 -c 'import sys,json; print(json.dumps(sys.stdin.read()))' < "$1"
}


# --- 1. Authenticate ---
echo "-> Authenticating to vCenter..."
SID=$(curl -k -s -X POST -u "$VCENTER_USER:$VCENTER_PASS" "$VCENTER/api/session" | tr -d '"')

if [ -z "$SID" ] || [ "$SID" = "null" ]; then
    # Fallback to legacy session endpoint
    echo "   Trying legacy session endpoint..."
    SID=$(curl -k -s -X POST -u "$VCENTER_USER:$VCENTER_PASS" "$VCENTER/rest/com/vmware/cis/session" | jq -r '.value')
fi

if [ -z "$SID" ] || [ "$SID" = "null" ]; then
    echo "❌ Failed to authenticate to vCenter."
    exit 1
fi
echo "   ✅ Authenticated (session: ${SID:0:12}...)"
echo ""


# --- 2. List Supervisor Services ---
list_services() {
    echo "-> Listing existing Supervisor Services..."
    echo ""
    SERVICES_RAW=$(curl -k -s -X GET \
      -H "vmware-api-session-id: $SID" \
      "$VCENTER/api/vcenter/namespace-management/supervisor-services")

    # Pretty print with key info
    echo "$SERVICES_RAW" | jq -r '.[] | "  ID: \(.supervisor_service // .service // "?")  |  Name: \(.display_name // "?")  |  State: \(.state // "?")"' 2>/dev/null || echo "$SERVICES_RAW"
    echo ""
    echo "Full JSON response:"
    echo "$SERVICES_RAW" | jq '.' 2>/dev/null || echo "$SERVICES_RAW"
}

# Store services for later lookups
fetch_services() {
    SERVICES_RAW=$(curl -k -s -X GET \
      -H "vmware-api-session-id: $SID" \
      "$VCENTER/api/vcenter/namespace-management/supervisor-services")
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
    echo "   Service ID: $SVC_ID"
    echo "   YAML file: $YAML_FILE"
    echo "   Content type: $CONTENT_TYPE"

    local YAML_JSON=$(yaml_to_json_string "$YAML_FILE")

    local RESPONSE=$(curl -k -s -w "\nHTTP_CODE:%{http_code}" -X POST \
      -H "vmware-api-session-id: $SID" \
      -H "Content-Type: application/json" \
      "$VCENTER/api/vcenter/namespace-management/supervisor-services/$SVC_ID/versions" \
      -d "{\"spec\": {\"content_type\": \"$CONTENT_TYPE\", \"content\": $YAML_JSON}}")

    local HTTP_CODE=$(echo "$RESPONSE" | grep "HTTP_CODE:" | cut -d: -f2)
    local BODY=$(echo "$RESPONSE" | grep -v "HTTP_CODE:")

    echo "   HTTP Status: $HTTP_CODE"
    if [ "$HTTP_CODE" = "204" ] || [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "201" ]; then
        echo "   ✅ Version registered successfully!"
    else
        echo "   Response:"
        echo "$BODY" | jq '.' 2>/dev/null || echo "$BODY"
    fi
    echo ""

    # If VSPHERE didn't work, try CARVEL
    if [ "$HTTP_CODE" != "204" ] && [ "$HTTP_CODE" != "200" ] && [ "$HTTP_CODE" != "201" ] && [ "$CONTENT_TYPE" = "VSPHERE" ]; then
        echo "   Retrying with content_type=CARVEL..."
        register_version "$SVC_ID" "$YAML_FILE" "$LABEL" "CARVEL"
    fi
}


# --- Helper: Create a new Supervisor Service ---
create_service() {
    local DISPLAY_NAME="$1"
    local DESCRIPTION="$2"

    echo "-> Creating new Supervisor Service: $DISPLAY_NAME"

    local RESPONSE=$(curl -k -s -w "\nHTTP_CODE:%{http_code}" -X POST \
      -H "vmware-api-session-id: $SID" \
      -H "Content-Type: application/json" \
      "$VCENTER/api/vcenter/namespace-management/supervisor-services" \
      -d "{\"display_name\": \"$DISPLAY_NAME\", \"description\": \"$DESCRIPTION\"}")

    local HTTP_CODE=$(echo "$RESPONSE" | grep "HTTP_CODE:" | cut -d: -f2)
    local BODY=$(echo "$RESPONSE" | grep -v "HTTP_CODE:")

    echo "   HTTP Status: $HTTP_CODE"
    echo "   Response:"
    echo "$BODY" | jq '.' 2>/dev/null || echo "$BODY"
    echo ""

    # Return the service ID from the response
    echo "$BODY" | jq -r '.' 2>/dev/null | tr -d '"'
}


# --- Helper: Install/enable a service on the supervisor ---
install_on_supervisor() {
    local SVC_ID="$1"
    local VERSION="$2"
    local LABEL="$3"

    echo "-> Installing $LABEL (v$VERSION) on Supervisor cluster $SUPERVISOR_CLUSTER..."

    # First, check what the API expects
    local RESPONSE=$(curl -k -s -w "\nHTTP_CODE:%{http_code}" -X POST \
      -H "vmware-api-session-id: $SID" \
      -H "Content-Type: application/json" \
      "$VCENTER/api/vcenter/namespace-management/clusters/$SUPERVISOR_CLUSTER/supervisor-services/$SVC_ID" \
      -d "{\"spec\": {\"version\": \"$VERSION\"}}")

    local HTTP_CODE=$(echo "$RESPONSE" | grep "HTTP_CODE:" | cut -d: -f2)
    local BODY=$(echo "$RESPONSE" | grep -v "HTTP_CODE:")

    echo "   HTTP Status: $HTTP_CODE"
    if [ "$HTTP_CODE" = "204" ] || [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "201" ]; then
        echo "   ✅ Service installed/updated successfully!"
    else
        echo "   Response:"
        echo "$BODY" | jq '.' 2>/dev/null || echo "$BODY"

        # Try PATCH instead of POST
        echo ""
        echo "   Trying PATCH instead..."
        RESPONSE=$(curl -k -s -w "\nHTTP_CODE:%{http_code}" -X PATCH \
          -H "vmware-api-session-id: $SID" \
          -H "Content-Type: application/json" \
          "$VCENTER/api/vcenter/namespace-management/clusters/$SUPERVISOR_CLUSTER/supervisor-services/$SVC_ID" \
          -d "{\"spec\": {\"version\": \"$VERSION\"}}")

        HTTP_CODE=$(echo "$RESPONSE" | grep "HTTP_CODE:" | cut -d: -f2)
        BODY=$(echo "$RESPONSE" | grep -v "HTTP_CODE:")

        echo "   HTTP Status: $HTTP_CODE"
        echo "   Response:"
        echo "$BODY" | jq '.' 2>/dev/null || echo "$BODY"
    fi
    echo ""
}


# --- Main Logic ---
case "$ACTION" in

    list)
        list_services
        ;;

    vks)
        echo "========================================="
        echo "  VKS v3.5.1 Upgrade"
        echo "========================================="
        echo ""
        fetch_services

        # Find existing VKS service ID
        VKS_SVC_ID=$(echo "$SERVICES_RAW" | jq -r '.[] | select(.display_name | test("Kubernetes|TKG|VKS"; "i")) | .supervisor_service // .service' 2>/dev/null | head -1)

        if [ -z "$VKS_SVC_ID" ]; then
            echo "   ⚠️ Could not find VKS service. Listing all services for reference:"
            list_services
            echo ""
            read -p "   Enter the VKS service ID manually: " VKS_SVC_ID
        fi

        echo "   Found VKS service: $VKS_SVC_ID"
        register_version "$VKS_SVC_ID" "$DESKTOP_DIR/vks-upgrade-3.5.1.yaml" "VKS v3.5.1"
        ;;

    argocd)
        echo "========================================="
        echo "  ArgoCD Service Deployment"
        echo "========================================="
        echo ""
        fetch_services

        ARGOCD_SVC_ID=$(echo "$SERVICES_RAW" | jq -r '.[] | select(.display_name | test("ArgoCD"; "i")) | select(.display_name | test("attach"; "i") | not) | .supervisor_service // .service' 2>/dev/null | head -1)

        if [ -z "$ARGOCD_SVC_ID" ]; then
            echo "   ArgoCD service not found. Will try to create it..."
            ARGOCD_SVC_ID=$(create_service "ArgoCD Service" "ArgoCD Supervisor Service for self-service ArgoCD instances")
        else
            echo "   Found existing ArgoCD service: $ARGOCD_SVC_ID"
        fi

        register_version "$ARGOCD_SVC_ID" "$DESKTOP_DIR/argocd-service-1.1.0.yaml" "ArgoCD v1.1.0"
        install_on_supervisor "$ARGOCD_SVC_ID" "1.1.0-25100889" "ArgoCD Service"
        ;;

    argoattach)
        echo "========================================="
        echo "  ArgoCD Attach Fling Deployment"
        echo "========================================="
        echo ""
        fetch_services

        ATTACH_SVC_ID=$(echo "$SERVICES_RAW" | jq -r '.[] | select(.display_name | test("attach"; "i")) | .supervisor_service // .service' 2>/dev/null | head -1)

        if [ -z "$ATTACH_SVC_ID" ]; then
            echo "   ArgoCD Attach service not found. Will try to create it..."
            ATTACH_SVC_ID=$(create_service "ArgoCD Attach" "ArgoCD Attach Fling for auto-attaching clusters")
        else
            echo "   Found existing ArgoCD Attach service: $ATTACH_SVC_ID"
        fi

        register_version "$ATTACH_SVC_ID" "$DESKTOP_DIR/argocd-attach-1.0.7.yaml" "ArgoCD Attach v1.0.7"
        install_on_supervisor "$ATTACH_SVC_ID" "1.0.7" "ArgoCD Attach"
        ;;

    all)
        echo "Running all service deployments..."
        echo ""

        fetch_services

        echo "========================================="
        echo "  Step 1/3: VKS v3.5.1 Upgrade"
        echo "========================================="
        VKS_SVC_ID=$(echo "$SERVICES_RAW" | jq -r '.[] | select(.display_name | test("Kubernetes|TKG|VKS"; "i")) | .supervisor_service // .service' 2>/dev/null | head -1)
        if [ -n "$VKS_SVC_ID" ]; then
            echo "   Found VKS service: $VKS_SVC_ID"
            register_version "$VKS_SVC_ID" "$DESKTOP_DIR/vks-upgrade-3.5.1.yaml" "VKS v3.5.1"
        else
            echo "   ⚠️ Could not find VKS service ID. Skipping."
        fi
        echo ""

        echo "========================================="
        echo "  Step 2/3: ArgoCD Service"
        echo "========================================="
        ARGOCD_SVC_ID=$(echo "$SERVICES_RAW" | jq -r '.[] | select(.display_name | test("ArgoCD"; "i")) | select(.display_name | test("attach"; "i") | not) | .supervisor_service // .service' 2>/dev/null | head -1)
        if [ -z "$ARGOCD_SVC_ID" ]; then
            ARGOCD_SVC_ID=$(create_service "ArgoCD Service" "ArgoCD Supervisor Service")
        else
            echo "   Found existing ArgoCD service: $ARGOCD_SVC_ID"
        fi
        register_version "$ARGOCD_SVC_ID" "$DESKTOP_DIR/argocd-service-1.1.0.yaml" "ArgoCD v1.1.0"
        install_on_supervisor "$ARGOCD_SVC_ID" "1.1.0-25100889" "ArgoCD Service"
        echo ""

        echo "========================================="
        echo "  Step 3/3: ArgoCD Attach Fling"
        echo "========================================="
        ATTACH_SVC_ID=$(echo "$SERVICES_RAW" | jq -r '.[] | select(.display_name | test("attach"; "i")) | .supervisor_service // .service' 2>/dev/null | head -1)
        if [ -z "$ATTACH_SVC_ID" ]; then
            ATTACH_SVC_ID=$(create_service "ArgoCD Attach" "ArgoCD Attach Fling")
        else
            echo "   Found existing ArgoCD Attach service: $ATTACH_SVC_ID"
        fi
        register_version "$ATTACH_SVC_ID" "$DESKTOP_DIR/argocd-attach-1.0.7.yaml" "ArgoCD Attach v1.0.7"
        install_on_supervisor "$ATTACH_SVC_ID" "1.0.7" "ArgoCD Attach"
        ;;

    *)
        echo "Usage: $0 [list|vks|argocd|argoattach|all]"
        exit 1
        ;;
esac

echo ""
echo "========================================="
echo "  Done! Review the outputs above."
echo "========================================="
