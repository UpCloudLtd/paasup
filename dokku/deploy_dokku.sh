#!/bin/bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────
# Script: deploy_dokku_stack.sh
# Usage: ./deploy_dokku_stack.sh <create|delete> <LOCATION> <PROJECT_NAME>
# Requires: upctl, kubectl, helm, jq, make, ssh keys, github PAT env vars
# ─────────────────────────────────────────────────────────────

export VERSION=1.0.0
log() { echo "[INFO] $1"; }
error_exit() { echo "[ERROR] $1" >&2; exit 1; }

# Parse args
if [[ $# -ne 3 ]]; then
  echo "Usage: $0 <deploy|delete> <LOCATION> <PROJECT_NAME>"
  exit 1
fi

ACTION="$1"
LOCATION="$2"
PROJECT="$3"
export CLUSTER_NAME="dokku-${PROJECT}-${LOCATION}"
export PRIVATE_NETWORK_NAME="dokku-net-${PROJECT}-${LOCATION}"
export KUBECONFIG_FILE="/tmp/${CLUSTER_NAME}_kubeconfig.yaml"

# Config values
export CERT_MANAGER_EMAIL="${CERT_MANAGER_EMAIL:-ops@example.com}"
export SSH_PATH="${SSH_PATH:-$HOME/.ssh/id_rsa}"
export SSH_PUB_PATH="${SSH_PUB_PATH:-${SSH_PATH}.pub}"
export GITHUB_PACKAGE_URL="${GITHUB_PACKAGE_URL:-ghcr.io}"
GLOBAL_DOMAIN="${GLOBAL_DOMAIN:-}"
export NUM_NODES="${NUM_NODES:-1}"

check_or_create_network() {
  NETWORK_ID=$(upctl network list -o json |
    jq -r ".networks[] | select(.name==\"$PRIVATE_NETWORK_NAME\" and .zone==\"$LOCATION\").uuid")
  if [[ -z "$NETWORK_ID" ]]; then
    log "Private network not found. Attempting to create..."
    for i in {1..10}; do
      CIDR="10.0.$(( RANDOM % 254 + 1 )).0/24"
      log "Trying CIDR $CIDR..."
      if upctl network create --name "$PRIVATE_NETWORK_NAME" --zone "$LOCATION" \
        --ip-network address=${CIDR},dhcp=true; then
        log "Created private network at $CIDR"
        return
      fi
    done
    error_exit "Failed to create private network after 10 attempts"
  else
    log "Private network already exists: $NETWORK_ID"
  fi
}

create_cluster() {
  CLUSTER_ID=$(upctl kubernetes list -o json |
    jq -r ".[] | select(.name==\"$CLUSTER_NAME\" and .zone==\"$LOCATION\").uuid")
  if [[ -z "$CLUSTER_ID" ]]; then

    check_or_create_network

    log "Creating Kubernetes cluster: $CLUSTER_NAME"
    upctl kubernetes create --name "$CLUSTER_NAME" --zone "$LOCATION" \
        --network "$PRIVATE_NETWORK_NAME" \
        --kubernetes-api-allow-ip 0.0.0.0/0 \
        --label "stacks.upcloud.com/created-by=dokku-script" \
        --label "stacks.upcloud.com/stack=dokku" \
        --label "stacks.upcloud.com/dokku-version=0.35.18" \
        --label "stacks.upcloud.com/script-vers=$VERSION" \
        --node-group count=$NUM_NODES,name=default,plan=2xCPU-4GB \
        -o json | jq -r '.uuid'
  else
    # TODO: Check what happens if we rerun the installation. Does it nuke existing Dokku apps?
    log "Cluster already exists: $CLUSTER_NAME"
  fi
}

download_kubeconfig() {
  CLUSTER_ID=$(upctl kubernetes list -o json |
    jq -r ".[] | select(.name==\"$CLUSTER_NAME\" and .zone==\"$LOCATION\").uuid")
  [[ -n "$CLUSTER_ID" ]] || error_exit "Cluster not found"
  upctl kubernetes config "$CLUSTER_ID" --write "$KUBECONFIG_FILE"
  export KUBECONFIG="$KUBECONFIG_FILE"
  log "KUBECONFIG=$KUBECONFIG_FILE"
}

wait_for_kubernetes_api() {
  log "Waiting for Kubernetes API to become available..."
  for i in {1..30}; do
    if kubectl version --request-timeout=5s >/dev/null 2>&1; then
      log "Kubernetes API is ready."
      return 0
    fi
    sleep 10
    log "Still waiting for Kubernetes API... ($i/30)"
  done
  error_exit "Timed out waiting for Kubernetes API to become available"
}

wait_for_ingress_hostname() {
  if [[ -n "$GLOBAL_DOMAIN" ]]; then
    log "GLOBAL_DOMAIN was provided: $GLOBAL_DOMAIN"
    return
  fi

  log "Waiting for LoadBalancer external hostname from ingress-nginx..."
  for i in {1..30}; do
  HOSTNAME=$(kubectl get svc ingress-nginx-controller -n ingress-nginx \
      -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)
  if [[ -n "$HOSTNAME" ]]; then
      GLOBAL_DOMAIN="$HOSTNAME"
      break
  fi
  sleep 30
  log "Still waiting for ingress LB hostname... ($i/30)"
  done

  if [[ -z "$GLOBAL_DOMAIN" ]]; then
  error_exit "Timed out waiting for ingress LB hostname"
  fi

  log "Ingress external hostname resolved: $GLOBAL_DOMAIN"
}

create_stack() {
  create_cluster
  download_kubeconfig
  wait_for_kubernetes_api

  log "Installing ingress-nginx"
  make install-ingress

  wait_for_ingress_hostname

  log "Installing certification manager"
  make install-cert-manager

  log "Installing Dokku"
  make install-dokku

  log "Configuring Dokku with provided parameters..."
  make configure \
    GITHUB_USERNAME="$GITHUB_USERNAME" \
    GITHUB_PAT="$GITHUB_PAT" \
    GLOBAL_DOMAIN="$GLOBAL_DOMAIN" \
    CERT_MANAGER_EMAIL="$CERT_MANAGER_EMAIL"
}

delete_stack() {
  CLUSTER_ID=$(upctl kubernetes list -o json |
    jq -r ".[] | select(.name==\"$CLUSTER_NAME\" and .zone==\"$LOCATION\").uuid")
  [[ -n "$CLUSTER_ID" ]] || error_exit "No such cluster: $CLUSTER_NAME"

  log "Deleting Kubernetes cluster: $CLUSTER_NAME"
  upctl kubernetes delete --uuid "$CLUSTER_ID"

  log "Deleting private network if exists..."
  NETWORK_ID=$(upctl network list -o json |
    jq -r ".networks[] | select(.name==\"$PRIVATE_NETWORK_NAME\" and .zone==\"$LOCATION\").uuid")
  if [[ -n "$NETWORK_ID" ]]; then
    upctl network delete --uuid "$NETWORK_ID"
  fi

  log "Deleted Dokku stack: $PROJECT"
}

print_final_instructions() {
  log ""
  log "Dokku installed and configured successfully!"
  log ""
  log "Deploy your first app:"
  log ""
  log "1. Create Dokku app:"
  log "   make create-app APP_NAME=demo-app"
  log ""
  log "2. Clone a sample app (e.g. Heroku Node.js sample):"
  log "   mkdir apps && cd apps"
  log "   git clone https://github.com/heroku/node-js-sample.git demo-app"
  log "   cd demo-app"
  log ""
  log "3. Set the Git remote:"
  log "   git remote add dokku dokku@dokku:demo-app"
  log ""
  log "4. Push the app:"
  log "   git push dokku master"
  log ""
  log "---------------------------------------------"
  log "Local testing (if you don't have a real DNS)"
  log ""
  log "1. Get the external IP of the load balancer:"
  log "   dig +short $GLOBAL_DOMAIN"
  log "2. Edit your local /etc/hosts file:"
  log "   sudo vim /etc/hosts"
  log ""
  log "   Add a line like this:"
  log "     <EXTERNAL-IP> demo-app.${GLOBAL_DOMAIN}"
  log ""
  log "   Example:"
  log "     5.22.219.157 demo-app.${GLOBAL_DOMAIN}"
  log ""
  log "3. Open your browser and visit:"
  log "   https://demo-app.${GLOBAL_DOMAIN}"
  log ""
  log "You can repeat this for more apps using:"
  log "   make create-app APP_NAME=another-app"
  log "   git remote add dokku dokku@dokku:another-app"
  log "   git push dokku master"
  log ""
  log "---------------------------------------------"
  log "Connectiing to the cluster"
  log "export KUBECONFIG=$KUBECONFIG_FILE"
  log ""
  log "Enjoy 🚀"
}


main() {
  case "$ACTION" in
    deploy)
      create_stack
      print_final_instructions
      ;;
    delete)
      delete_stack
      ;;
    *)
      error_exit "Unknown action: $ACTION. Use 'create' or 'delete'"
      ;;
  esac
}

main
