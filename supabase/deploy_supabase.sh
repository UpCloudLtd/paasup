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

set -euo pipefail

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
NAMESPACE="kube-paas-${REGION}-${NAME}-$(date +%s)"

### Paths ###
KUBECONFIG_FILE="/tmp/${CLUSTER_NAME}_kubeconfig.yaml"
CHART_DIR="/opt/supabase-chart"
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
  log "Cluster not found. Creating private network: $PRIVATE_NETWORK_NAME"
  upctl network create --name "$PRIVATE_NETWORK_NAME" --zone "$REGION" --ip-network address=10.0.2.0/24,dhcp=true || error_exit "Failed to create private network"

  log "Creating Kubernetes cluster: $CLUSTER_NAME"
  upctl kubernetes create --name "$CLUSTER_NAME" --zone "$REGION" --network "$PRIVATE_NETWORK_NAME" --node-group count=1,name=my-minimal-node-group,plan=2xCPU-4GB, || error_exit "Failed to create Kubernetes cluster"

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

### Clone Supabase chart (pre-patched version) ###
# This should point to your already-patched repo
if [[ ! -d "$CHART_DIR" ]]; then
  log "Cloning custom Supabase chart repository..."
  git clone --depth 1 https://your-forked-repo/supabase-kubernetes "$CHART_DIR" || error_exit "Failed to clone chart"
fi

cd "$CHART_DIR/charts/supabase"

log "Installing Supabase via Helm into namespace $NAMESPACE..."
helm install "$NAMESPACE" . -n supabase --create-namespace -f "$VALUES_FILE" || error_exit "Helm install failed"

### Wait for LoadBalancer IP ###
log "Waiting for Kong LoadBalancer external hostname..."
for i in {1..30}; do
  LB_HOSTNAME=$(kubectl get svc -n supabase -o jsonpath="{.items[?(@.metadata.name=='${NAMESPACE}-kong')].status.loadBalancer.ingress[0].hostname}" || true)
  if [[ -n "$LB_HOSTNAME" ]]; then
    log "Found LB Hostname: $LB_HOSTNAME"
    break
  fi
  sleep 5
  log "Waiting for LoadBalancer... ($i/30)"
done

if [[ -z "$LB_HOSTNAME" ]]; then
  error_exit "Timed out waiting for LoadBalancer hostname."
fi

### Update env URLs ###
log "Updating Supabase values file with real DNS..."
go run /opt/tools/update_supabase_dns.go "$VALUES_FILE" "$UPDATED_VALUES_FILE" "$LB_HOSTNAME" || error_exit "DNS update script failed"

log "Upgrading Helm release with final values..."
helm upgrade "$NAMESPACE" . -n supabase -f "$UPDATED_VALUES_FILE" || error_exit "Helm upgrade failed"

log "✅ Supabase successfully deployed."
echo "Public endpoint: http://$LB_HOSTNAME:8000"
echo "Kubernetes Namespace: $NAMESPACE"
