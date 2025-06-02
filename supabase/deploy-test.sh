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
  log "Cluster not found."
  NETWORK_ID=$(upctl network list -o json | jq -r ".networks[] | select(.name == \"$PRIVATE_NETWORK_NAME\" and .zone == \"$REGION\") | .uuid")

  if [[ -z "$NETWORK_ID" ]]; then
    log "Creating private network: $PRIVATE_NETWORK_NAME"
    upctl network create --name "$PRIVATE_NETWORK_NAME" --zone "$REGION" --ip-network address=10.0.2.0/24,dhcp=true || error_exit "Failed to create private network"
  else
    log "Private network '$PRIVATE_NETWORK_NAME' already exists with ID: $NETWORK_ID"
  fi

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