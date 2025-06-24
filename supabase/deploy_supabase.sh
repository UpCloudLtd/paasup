#!/bin/bash

# ─────────────────────────────────────────────────────────────
# Script: deploy_supabase.sh
# Purpose: Deploy a Supabase instance in a regional K8s cluster
# Requirements:
#   - upctl with API access (env configured)
#   - helm
#   - git
#   - kubectl
#   - jq
# Notes:
#   - This script assumes it's running in a container or env with all tools preinstalled
#   - Assumes you have a custom Helm chart prepared for Supabase - They shipped with the codebase
# ─────────────────────────────────────────────────────────────

set -exuo pipefail

log() {
  echo "[INFO] $1"
}

error_exit() {
  echo "[ERROR] $1" >&2
  exit 1
}

# Resolve root directory of this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

### Input Params ###
LOCATION="$1"
NAME="$2"

if [[ -z "$LOCATION" || -z "$NAME" ]]; then
  echo "Usage: $0 <LOCATION> <NAME>"
  exit 1
fi

# Load environment variables from config file if it exists
# This file contains the configuration for the deployment
CONFIG_FILE="${SCRIPT_DIR}/deploy_supabase.env"
if [[ -f "$CONFIG_FILE" ]]; then
  log "Sourcing config from $CONFIG_FILE"
  # shellcheck disable=SC1090
  source "$CONFIG_FILE"
fi

### Naming Conventions ###
CLUSTER_NAME="kube-paas-${LOCATION}"
PRIVATE_NETWORK_NAME="kube-paas-private-network-${LOCATION}"
# Namespace is unique per region and app name - 
# NOTE: Implement mechanisms to make sure that only the owner of the namespace can access it. For instance,
# to avoid a different user do helm install with the same namespace as other user, overwriting somebody else's deployment.
NAMESPACE="kube-paas-${LOCATION}-${NAME}"

### Paths ###
KUBECONFIG_FILE="/tmp/${CLUSTER_NAME}_kubeconfig.yaml"
CHART_DIR="${SCRIPT_DIR}/charts/supabase"
VALUES_FILE="${CHART_DIR}/values.example.yaml"
UPDATED_VALUES_FILE="${CHART_DIR}/values.update.yaml"
SECURE_VALUES_FILE="${CHART_DIR}/values.secure.yaml"

# set ssupabase keys
source "${SCRIPT_DIR}/supabase_keys.sh"
JWT_SECRET="$(openssl rand -hex 20)"
generate_supabase_keys "$JWT_SECRET" 
log "ANON_KEY: ${ANON_KEY}"
log "SERVICE_ROLE_KEY: ${SERVICE_ROLE_KEY}"

POSTGRES_PASSWORD="$(openssl rand -base64 12 | tr -d '=+/')"
DASHBOARD_USERNAME="${DASHBOARD_USERNAME:-supabase}"
DASHBOARD_PASSWORD="${DASHBOARD_PASSWORD:-$(openssl rand -base64 12 | tr -d '=+/')}"

POOLER_TENANT_ID="${POOLER_TENANT_ID:-tenant-$(openssl rand -hex 3)}"

# SMTP settings coming from configuration file deploy_supabase.env
# Ensure the SMTP configuration settings are set and correct
: "${ENABLE_SMTP:=false}"
if [[ "$ENABLE_SMTP" == "true" ]]; then
  : "${SMTP_HOST:?Must set SMTP_HOST when ENABLE_SMTP=true}"
  : "${SMTP_PORT:?Must set SMTP_PORT when ENABLE_SMTP=true}"
  : "${SMTP_USER:?Must set SMTP_USER when ENABLE_SMTP=true}"
  : "${SMTP_PASS:?Must set SMTP_PASS when ENABLE_SMTP=true}"
  : "${SMTP_SENDER_NAME:?Must set SMTP_SENDER_NAME when ENABLE_SMTP=true}"
  log "SMTP enabled: $SMTP_HOST:$SMTP_PORT as $SMTP_USER"
else
  log "SMTP disabled"
  unset SMTP_HOST SMTP_PORT SMTP_USER SMTP_PASS SMTP_SENDER_NAME
fi

# S3 settings coming from configuration file deploy_supabase.env
# Ensure the S3 configuration settings are set and correct
: "${ENABLE_S3:=false}"
if [[ "$ENABLE_S3" == "true" ]]; then
  : "${S3_BUCKET:?Must set S3_BUCKET when ENABLE_S3=true}"
  : "${S3_ENDPOINT:?Must set S3_ENDPOINT when ENABLE_S3=true}"
  : "${S3_REGION:?Must set S3_REGION when ENABLE_S3=true}"
  : "${S3_KEY_ID:?Must set S3_KEY_ID when ENABLE_S3=true}"
  : "${S3_ACCESS_KEY:?Must set S3_ACCESS_KEY when ENABLE_S3=true}"
  log "S3 enabled: bucket=$S3_BUCKET endpoint=$S3_ENDPOINT region=$S3_REGION"
else
  log "S3 disabled"
  unset S3_BUCKET S3_ENDPOINT S3_REGION S3_KEY_ID S3_ACCESS_KEY
fi

### Check if cluster exists ###
log "Checking if cluster '$CLUSTER_NAME' exists in region $LOCATION..."
CLUSTER_ID=$(upctl kubernetes list -o json | jq -r ".[] | select(.name == \"$CLUSTER_NAME\" and .zone == \"$LOCATION\") | .uuid")

if [[ -z "$CLUSTER_ID" ]]; then
  log "Cluster not found."
  NETWORK_ID=$(upctl network list -o json | jq -r ".networks[] | select(.name == \"$PRIVATE_NETWORK_NAME\" and .zone == \"$LOCATION\") | .uuid")

  if [[ -z "$NETWORK_ID" ]]; then
    log "Creating private network: $PRIVATE_NETWORK_NAME"
    ### TODO: Apparently I can't creeate 2 private networks with the same address even in different regions in the same account?
    upctl network create --name "$PRIVATE_NETWORK_NAME" --zone "$LOCATION" --ip-network address=10.0.7.0/24,dhcp=true || error_exit "Failed to create private network"
  else
    log "Private network '$PRIVATE_NETWORK_NAME' already exists with ID: $NETWORK_ID"
  fi

  log "Creating Kubernetes cluster: $CLUSTER_NAME"
  upctl kubernetes create --name "$CLUSTER_NAME" --zone "$LOCATION" --network "$PRIVATE_NETWORK_NAME" --kubernetes-api-allow-ip 0.0.0.0/0 --node-group count=1,name=my-minimal-node-group,plan=2xCPU-4GB, || error_exit "Failed to create Kubernetes cluster"

  sleep 5
  CLUSTER_ID=$(upctl kubernetes list -o json | jq -r ".[] | select(.name == \"$CLUSTER_NAME\" and .zone == \"$LOCATION\") | .uuid")

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
log "To talk to the cluster, run: export KUBECONFIG=$KUBECONFIG"

source "${SCRIPT_DIR}/write_secure_values.sh"

# Write the secure values file
write_secure_values "$SECURE_VALUES_FILE"

### There is another issue when deploying 2 supabase instances in the same region, the second one fails to deploy because the LB name collides. 
### I haven't been able to figure out how the LB name is created.

log "Checking if Helm release '$NAMESPACE' exists..."
if helm status "$NAMESPACE" -n "$NAMESPACE" &>/dev/null; then
  log "Helm release already exists. Skipping install."
else
  log "Installing Supabase via Helm into namespace $NAMESPACE..."
  helm install "$NAMESPACE" "$CHART_DIR" \
        -n "$NAMESPACE" --create-namespace \
        -f "$VALUES_FILE" \
        -f "$SECURE_VALUES_FILE" \
        || error_exit "Helm install failed"
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
  log "Waiting for LoadBalancer... ($i/60)"
done

if [[ -z "$LB_HOSTNAME" ]]; then
  error_exit "Timed out waiting for LoadBalancer hostname."
fi

### Update env URLs ###
log "Updating Supabase values file with real DNS..."
GO_SCRIPT_DIR="${SCRIPT_DIR}/dns-config"
DNS_PREFIX="${LB_HOSTNAME%%.upcloudlb.com}"

# Move into the dns‐config directory and run the Go updater
cd "$GO_SCRIPT_DIR" || error_exit "DNS script directory not found"
go run update_supabase_dns.go \
    "$VALUES_FILE" "$UPDATED_VALUES_FILE" "$DNS_PREFIX" \
  || error_exit "DNS update script failed"

log "Upgrading Helm release with final values..."
helm upgrade "$NAMESPACE" "$CHART_DIR" \
    -n "$NAMESPACE" \
    -f "$UPDATED_VALUES_FILE" \
    -f "$SECURE_VALUES_FILE" \
    || error_exit "Helm upgrade failed"

log "Supabase successfully deployed."
log "Public endpoint: http://$LB_HOSTNAME:8000"
log "Kubernetes Namespace: $NAMESPACE"
log "POSTGRES_PASSWORD: ${POSTGRES_PASSWORD:-not set}"
log "POOLER_TENANT_ID: ${POOLER_TENANT_ID:-not set}"
log "DASHBOARD_USERNAME: ${DASHBOARD_USERNAME:-not set}"
log "DASHBOARD_PASSWORD: ${DASHBOARD_PASSWORD:-not set}"
log "S3 ENABLED: ${ENABLE_S3}"
log "S3_BUCKET: ${S3_BUCKET:-not set}"
log "S3_ENDPOINT: ${S3_ENDPOINT:-not set}"
log "S3_REGION: ${S3_REGION:-not set}"
log "SMTP ENABLED: ${ENABLE_SMTP}"
log "SMTP_HOST: ${SMTP_HOST:-not set}"
log "SMTP_PORT: ${SMTP_PORT:-not set}"
log "SMTP_USER: ${SMTP_USER:-not set}"
log "SMTP_SENDER_NAME: ${SMTP_SENDER_NAME:-not set}"