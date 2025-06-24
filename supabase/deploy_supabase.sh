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

# Logging helpers
log() { echo "[INFO] $1"; }
error_exit() { echo "[ERROR] $1" >&2; exit 1; }

# Globals variables
SCRIPT_DIR=""
LOCATION=""
NAME=""
CONFIG_FILE=""
CLUSTER_NAME=""
PRIVATE_NETWORK_NAME=""
NAMESPACE=""
KUBECONFIG_FILE=""
CHART_DIR=""
VALUES_FILE=""
UPDATED_VALUES_FILE=""
SECURE_VALUES_FILE=""


parse_args() {
  # Resolve root directory of this script
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  if [[ $# -ne 2 ]]; then
    echo "Usage: $0 <LOCATION> <NAME>"
    exit 1
  fi
  LOCATION="$1"
  NAME="$2"
  CONFIG_FILE="${SCRIPT_DIR}/deploy_supabase.env"
}

# Load environment variables from config file if it exists
# This file contains the configuration for the deployment
load_config() {
  if [[ -f "$CONFIG_FILE" ]]; then
    log "Sourcing config from $CONFIG_FILE"
    # shellcheck disable=SC1090
    source "$CONFIG_FILE"
  fi
}

init_names_and_paths() {
  CLUSTER_NAME="kube-paas-${LOCATION}"
  PRIVATE_NETWORK_NAME="kube-paas-private-network-${LOCATION}"
  NAMESPACE="kube-paas-${LOCATION}-${NAME}"
  KUBECONFIG_FILE="/tmp/${CLUSTER_NAME}_kubeconfig.yaml"
  CHART_DIR="${SCRIPT_DIR}/charts/supabase"
  VALUES_FILE="${CHART_DIR}/values.example.yaml"
  UPDATED_VALUES_FILE="${CHART_DIR}/values.update.yaml"
  SECURE_VALUES_FILE="${CHART_DIR}/values.secure.yaml"
}

generate_keys() {
  source "${SCRIPT_DIR}/supabase_keys.sh"
  JWT_SECRET="$(openssl rand -hex 20)"
  generate_supabase_keys "$JWT_SECRET"
  POOLER_TENANT_ID="${POOLER_TENANT_ID:-tenant-$(openssl rand -hex 3)}"
}

configure_studio() {
  DASHBOARD_USERNAME="${DASHBOARD_USERNAME:-supabase}"
  DASHBOARD_PASSWORD="${DASHBOARD_PASSWORD:-$(openssl rand -base64 12 | tr -d '=+/')}"
}

configure_db() {
  POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-$(openssl rand -base64 12 | tr -d '=+/')}"
}

# SMTP settings coming from configuration file deploy_supabase.env
# Ensure the SMTP configuration settings are set and correct
configure_smtp() {
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
}

# S3 settings coming from configuration file deploy_supabase.env
# Ensure the S3 configuration settings are set and correct
configure_s3() {
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
}

create_cluster() {
  log "Checking if cluster '$CLUSTER_NAME' exists in region $LOCATION..."
  CLUSTER_ID=$(upctl kubernetes list -o json \
    | jq -r ".[] | select(.name==\"$CLUSTER_NAME\" and .zone==\"$LOCATION\").uuid")

  if [[ -z "$CLUSTER_ID" ]]; then
    log "Cluster not found."
    NETWORK_ID=$(upctl network list -o json \
      | jq -r ".networks[] | select(.name==\"$PRIVATE_NETWORK_NAME\" and .zone==\"$LOCATION\").uuid")

    if [[ -z "$NETWORK_ID" ]]; then
      log "Private network not found. Attempting to create with random subnets..."
      for i in {1..10}; do
        X=$(( RANDOM % 254 + 1 ))  # 1-254
        CIDR="10.0.${X}.0/24"
        log "Attempt $i: trying CIDR $CIDR"
        if upctl network create --name "$PRIVATE_NETWORK_NAME" --zone "$LOCATION" \
             --ip-network address=${CIDR},dhcp=true; then
          log "Created private network at $CIDR"
          NETWORK_ID=$(upctl network list -o json \
            | jq -r ".networks[] | select(.name==\"$PRIVATE_NETWORK_NAME\" and .zone==\"$LOCATION\").uuid")
          break
        else
          log "Attempt $i failed for CIDR $CIDR"
        fi
      done
      [[ -z "$NETWORK_ID" ]] && error_exit "Failed to create private network after 10 attempts"
    else
      log "Private network exists: $NETWORK_ID"
    fi

    log "Creating Kubernetes cluster: $CLUSTER_NAME"
    CLUSTER_ID=$(upctl kubernetes create --name "$CLUSTER_NAME" --zone "$LOCATION" \
      --network "$PRIVATE_NETWORK_NAME" --kubernetes-api-allow-ip 0.0.0.0/0 \
      --node-group count=1,name=my-minimal-node-group,plan=2xCPU-4GB \
      -o json | jq -r '.uuid')
      
    if [[ -z "$CLUSTER_ID" ]]; then
      error_exit "Cluster creation failed or not visible yet."
    else
      log "Cluster created with id: $CLUSTER_ID"
    fi

  else
    log "Cluster already exists. Skipping creation."
  fi
}

configure_kubeconfig() {
  log "Downloading kubeconfig..."
  upctl kubernetes config "$CLUSTER_ID" --write "$KUBECONFIG_FILE" \
    || error_exit "Failed to download kubeconfig"
  export KUBECONFIG="$KUBECONFIG_FILE"
  log "Exported KUBECONFIG=$KUBECONFIG"
}

# Write the secure values file
write_secure_values_file() {
  source "${SCRIPT_DIR}/write_secure_values.sh"
  write_secure_values "$SECURE_VALUES_FILE"
}

### There is another issue when deploying 2 supabase instances in the same region, the second one fails to deploy because the LB name collides. 
### I haven't been able to figure out how the LB name is created.

deploy_helm_release() {
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
}

wait_for_loadbalancer() {
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
}

update_dns() {
  log "Updating DNS entries..."
  cd "${SCRIPT_DIR}/dns-config" || error_exit "DNS dir missing"
  DNS_PREFIX="${LB_HOSTNAME%%.upcloudlb.com}"
  go run update_supabase_dns.go "$VALUES_FILE" "$UPDATED_VALUES_FILE" "$DNS_PREFIX" \
    || error_exit "DNS update failed"
}

upgrade_release() {
  log "Upgrading Helm release with final values..."
  helm upgrade "$NAMESPACE" "$CHART_DIR" -n "$NAMESPACE" \
    -f "$UPDATED_VALUES_FILE" -f "$SECURE_VALUES_FILE" \
    || error_exit "Helm upgrade failed"
}

print_summary() {
  log "Supabase deployed successfully!"
  log "Public endpoint: http://$LB_HOSTNAME:8000"
  log "Namespace: $NAMESPACE"
  log "ANON_KEY: ${ANON_KEY}"
  log "SERVICE_ROLE_KEY: ${SERVICE_ROLE_KEY}"
  log "POSTGRES_PASSWORD: ${POSTGRES_PASSWORD:-not set}"
  log "POOLER_TENANT_ID: $POOLER_TENANT_ID"
  log "DASHBOARD_USERNAME: $DASHBOARD_USERNAME"
  log "DASHBOARD_PASSWORD: $DASHBOARD_PASSWORD"
  log "S3 ENABLED: ${ENABLE_S3}"
  log "S3_BUCKET: ${S3_BUCKET:-not set}"
  log "S3_ENDPOINT: ${S3_ENDPOINT:-not set}"
  log "S3_REGION: ${S3_REGION:-not set}"
  log "SMTP ENABLED: ${ENABLE_SMTP}"
  log "SMTP_HOST: ${SMTP_HOST:-not set}"
  log "SMTP_PORT: ${SMTP_PORT:-not set}"
  log "SMTP_USER: ${SMTP_USER:-not set}"
  log "SMTP_SENDER_NAME: ${SMTP_SENDER_NAME:-not set}"
}

main() {
  parse_args "$@"
  load_config
  generate_keys
  configure_studio
  configure_db
  configure_smtp
  configure_s3
  init_names_and_paths
  create_cluster
  configure_kubeconfig
  write_secure_values_file
  deploy_helm_release
  wait_for_loadbalancer
  update_dns
  upgrade_release
  print_summary
}

main "$@"