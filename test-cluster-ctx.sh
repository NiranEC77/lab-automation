#!/bin/bash
# Standalone test script for VKS Cluster Context Configuration (Section 11)
# Run this directly to test/debug the cluster context setup without re-running the full script.

set -e
CLUSTER_NAME="e2e-niran-cls01"

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
echo "✅ Done!"
