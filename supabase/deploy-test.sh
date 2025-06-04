#!/bin/bash

# ─────────────────────────────────────────────────────────────
# Script: deploy_supabase.sh
# Purpose: Deploy a Supabase instance in a regional K8s cluster
# Requirements:
#   - upctl with API access (env configured)
#   - helm
#   - git
#   - kubectl
# Notes:
#   - This script assumes it's running in a container or env with all tools preinstalled
#   - Assumes you have a custom Helm chart prepared for Supabase
# ─────────────────────────────────────────────────────────────

set -exuo pipefail

# Resolve root directory of this script, even when symlinked
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

### Input Params ###
REGION="$1"
NAME="$2"

if [[ -z "$REGION" || -z "$NAME" ]]; then
  echo "Usage: $0 <REGION> <NAME>"
  exit 1
fi

### Naming Conventions ###
CLUSTER_NAME="kube-paas-${REGION}"
PRIVATE_NETWORK_NAME="kube-paas-private-network-${REGION}"
# Namespace is unique per region and name - Implement mechanisms to make sure that only the owner of the namespace can access it. For instance,
# to avoid a different user do helm install with the same namespace as other user, overwriting somebody else's deployment.
NAMESPACE="kube-paas-${REGION}-${NAME}"

### Paths ###
KUBECONFIG_FILE="/tmp/${CLUSTER_NAME}_kubeconfig.yaml"
CHART_DIR="${SCRIPT_DIR}/charts/supabase"
VALUES_FILE="${CHART_DIR}/values.example.yaml"
UPDATED_VALUES_FILE="${CHART_DIR}/values.update.yaml"

log() {
  echo "[INFO] $1"
}

error_exit() {
  echo "[ERROR] $1" >&2
  exit 1
}

### Check if cluster exists ###
log "Checking if cluster '$CLUSTER_NAME' exists in region $REGION..."
CLUSTER_ID=$(upctl kubernetes list -o json | jq -r ".[] | select(.name == \"$CLUSTER_NAME\" and .zone == \"$REGION\") | .uuid")

if [[ -z "$CLUSTER_ID" ]]; then
  log "Cluster not found."
  NETWORK_ID=$(upctl network list -o json | jq -r ".networks[] | select(.name == \"$PRIVATE_NETWORK_NAME\" and .zone == \"$REGION\") | .uuid")

  if [[ -z "$NETWORK_ID" ]]; then
    log "Creating private network: $PRIVATE_NETWORK_NAME"
    ### TODO: Apparently I can't creeate 2 private networks with the same address even in different regions in the same account?
    upctl network create --name "$PRIVATE_NETWORK_NAME" --zone "$REGION" --ip-network address=10.0.3.0/24,dhcp=true || error_exit "Failed to create private network"
  else
    log "Private network '$PRIVATE_NETWORK_NAME' already exists with ID: $NETWORK_ID"
  fi

  log "Creating Kubernetes cluster: $CLUSTER_NAME"
  upctl kubernetes create --name "$CLUSTER_NAME" --zone "$REGION" --network "$PRIVATE_NETWORK_NAME" --kubernetes-api-allow-ip 0.0.0.0/0 --node-group count=1,name=my-minimal-node-group,plan=2xCPU-4GB, || error_exit "Failed to create Kubernetes cluster"

  sleep 5
  CLUSTER_ID=$(upctl kubernetes list -o json | jq -r ".[] | select(.name == \"$CLUSTER_NAME\" and .zone == \"$REGION\") | .uuid")

  if [[ -z "$CLUSTER_ID" ]]; then
    error_exit "Cluster creation failed or not visible yet."
  else
    log "Cluster created with id: $CLUSTER_ID"
  fi

else
  log "Cluster already exists. Skipping creation."
fi

log "Downloading kubeconfig..."
upctl kubernetes config "$CLUSTER_ID" --write "$KUBECONFIG_FILE" || error_exit "Failed to download kubeconfig"
export KUBECONFIG="$KUBECONFIG_FILE"

### TODO: Figure out how to allow access from command line into the cluster. Now I have to manually allow access from any IP in the hub.
### In production, ideally we would allow only access from the VM ip this script is running on.
### There is another issue when deploying 2 supabase instances in the same region, the second one fails to deploy because the LB name collides. 
### I haven't been able to figure out how the LB name is created.
log "Checking if Helm release '$NAMESPACE' exists..."
if helm status "$NAMESPACE" -n "$NAMESPACE" &>/dev/null; then
  log "Helm release already exists. Skipping install."
else
  log "Installing Supabase via Helm into namespace $NAMESPACE..."
  helm install "$NAMESPACE" "$CHART_DIR" -n "$NAMESPACE" --create-namespace -f "$VALUES_FILE" || error_exit "Helm install failed"
fi

### Wait for LoadBalancer IP ###
log "Waiting for Kong LoadBalancer external hostname..."
for i in {1..60}; do
  LB_HOSTNAME=$(kubectl get svc "$NAMESPACE-supabase-kong" -n "$NAMESPACE" -o json | jq -r '.status.loadBalancer.ingress[0].hostname // empty')

  if [[ -n "$LB_HOSTNAME" ]]; then
    log "Found LB Hostname: $LB_HOSTNAME"
    break
  fi
  sleep 20
  log "Waiting for LoadBalancer... ($i/30)"
done

if [[ -z "$LB_HOSTNAME" ]]; then
  error_exit "Timed out waiting for LoadBalancer hostname."
fi

### Update env URLs ###
log "Updating Supabase values file with real DNS..."
GO_SCRIPT_DIR="${SCRIPT_DIR}/dns-config"
(
  cd "$GO_SCRIPT_DIR" || error_exit "DNS script directory not found"
  go run update_supabase_dns.go "$VALUES_FILE" "$UPDATED_VALUES_FILE" "$LB_HOSTNAME" || error_exit "DNS update script failed"
)

log "Upgrading Helm release with final values..."
helm upgrade "$NAMESPACE" "$CHART_DIR" -n "$NAMESPACE" -f "$UPDATED_VALUES_FILE" || error_exit "Helm upgrade failed"

log "Supabase successfully deployed."
echo "Public endpoint: http://$LB_HOSTNAME:8000"
echo "Kubernetes Namespace: $NAMESPACE"