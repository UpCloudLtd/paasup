.PHONY: install
install: install-ingress install-cert-manager install-dokku
.PHONY: uninstall
uninstall: uninstall-dokku uninstall-cert-manager uninstall-ingress

# Set the default target to `help`
.DEFAULT_GOAL := help

.PHONY: help
help:
	@echo "Usage: make <target>"
	@echo ""
	@echo "Available targets:"
	@echo "  install                Install all components (Ingress, Cert-Manager, Dokku)"
	@echo "  uninstall              Uninstall all components"
	@echo "  install-dokku          Install Dokku"
	@echo "  uninstall-dokku        Uninstall Dokku"
	@echo "  install-ingress        Install Ingress"
	@echo "  uninstall-ingress      Uninstall Ingress"
	@echo "  install-cert-manager   Install Cert-Manager"
	@echo "  uninstall-cert-manager Uninstall Cert-Manager"
	@echo "  configure              Configure Dokku with required parameters"
	@echo "  deconfigure            Reset Dokku configuration"
	@echo "  create-app             Create a new app"
	@echo "  delete-app             Delete an app"
	@echo "  list-apps              List all apps"
	@echo "  invoke                 Run arbitrary Dokku commands"
	@echo "  check-dokku            Check if Dokku is installed and ready"
	@echo "  check-ssh              Check if SSH keys are configured"
	@echo "  cleanup-docker         Clean up Docker resources"
	@echo ""
	@echo "Examples:"
	@echo "  make install"
	@echo "  make configure GITHUB_PAT=<token> GITHUB_USERNAME=<username> GLOBAL_DOMAIN=<example.com> CERT_MANAGER_EMAIL=<your@domain.tld>"
	@echo "  make create-app APP_NAME=<app-name>"
	@echo "  make list-apps"
	@echo "  make invoke apps:list"
	@echo "  make delete-app APP_NAME=<app-name>"
	@echo ""


.PHONY: install-dokku
install-dokku:
	@echo "Installing dokku..."
	kubectl kustomize ./dokku --enable-helm | kubectl apply -f -
	@echo "Dokku installed successfully."
	@echo ""

.PHONY: uninstall-dokku
uninstall-dokku:
	kubectl kustomize ./dokku --enable-helm | kubectl delete -f -

.PHONY: install-ingress
install-ingress:
	@echo "Installing ingress-nginx..."
	@helm upgrade --install ingress-nginx ingress-nginx \
      --repo https://kubernetes.github.io/ingress-nginx \
      --namespace ingress-nginx --create-namespace \
      --values ./ingress/values.yaml \
      --hide-notes
	@echo "Ingress-nginx installed successfully."
	@echo ""

.PHONY: uninstall-ingress
uninstall-ingress:
	helm uninstall ingress-nginx --namespace ingress-nginx
	kubectl delete namespace ingress-nginx

.PHONY: install-cert-manager
install-cert-manager:
	@echo "Installing cert-manager..."
	@helm upgrade --install cert-manager cert-manager \
	  --repo https://charts.jetstack.io \
	  --namespace cert-manager --create-namespace \
	  --version v1.11.0 \
	  --set installCRDs=true \
	  --hide-notes
	@echo "Cert-manager installed successfully."
	@echo ""

.PHONY: uninstall-cert-manager
uninstall-cert-manager:
	helm uninstall cert-manager --namespace cert-manager
	kubectl delete namespace cert-manager



GITHUB_PACKAGE_URL ?= ghcr.io
SSH_PATH ?= $(shell ls ~/.ssh/id_* | head -n 1)
SSH_PUB_PATH ?= $(SSH_PATH).pub

define check_required_param
	@if [ -z "$(1)" ]; then \
		echo "Error: $(2) is required"; \
		echo "Usage: $(3)"; \
		exit 1; \
	fi
endef

define get_dokku_pod_name
	kubectl get pods -n dokku -l app=dokku -o jsonpath='{.items[0].metadata.name}'
endef

define get_loadbalancer_address
	kubectl get svc ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
endef

define get_node_external_ip
	kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="ExternalIP")].address}'
endef

.PHONY: check-dokku
check-dokku:
	@kubectl get deployment -n dokku dokku > /dev/null 2>&1 || { echo "Dokku is not installed. Please run 'make install' to install it."; exit 1; }
	@kubectl wait --for=condition=ready --timeout=1s pods -n dokku -l app=dokku > /dev/null 2>&1 || { echo "Dokku pods are not ready. Waiting for up to 5 minutes..."; kubectl wait --for=condition=ready --timeout=300s pods -n dokku -l app=dokku 1> /dev/null ; }
	@echo "check-dokku: Dokku is installed and ready."
.PHONY: check-ssh
check-ssh:
	@echo "Checking SSH keys..."
	@if [ ! -f $(SSH_PATH) ]; then \
		echo "SSH key not found at $(SSH_PATH). Please generate an SSH private key and/or provide it to SSH_PATH"; \
		exit 1; \
	fi
	@if [ ! -f $(SSH_PUB_PATH) ]; then \
		echo "SSH key not found at $(SSH_PUB_PATH). Please provide public SSH key to SSH_PUB_PATH"; \
		exit 1; \
	fi
	@echo "SSH keys are configured correctly."

.PHONY: configure
configure: check-dokku check-ssh
	$(call check_required_param,$(GITHUB_PAT),GITHUB_PAT,make configure GITHUB_PAT=your_token GITHUB_USERNAME=your_user GLOBAL_DOMAIN=example.com CERT_MANAGER_EMAIL=you@example.com)
	$(call check_required_param,$(GITHUB_USERNAME),GITHUB_USERNAME,make configure GITHUB_PAT=your_token GITHUB_USERNAME=your_user GLOBAL_DOMAIN=example.com CERT_MANAGER_EMAIL=you@example.com)
	$(call check_required_param,$(GLOBAL_DOMAIN),GLOBAL_DOMAIN,make configure GITHUB_PAT=your_token GITHUB_USERNAME=your_user GLOBAL_DOMAIN=example.com CERT_MANAGER_EMAIL=you@example.com)
	$(call check_required_param,$(CERT_MANAGER_EMAIL),CERT_MANAGER_EMAIL,make configure GITHUB_PAT=your_token GITHUB_USERNAME=your_user GLOBAL_DOMAIN=example.com CERT_MANAGER_EMAIL=you@example.com)
	@echo "Configuring with parameters..."
	$(eval POD_NAME := $(shell $(call get_dokku_pod_name)))
	@echo "Using pod: $(POD_NAME)"
	@echo ""
	@cat $(SSH_PUB_PATH) | kubectl exec -i $(POD_NAME) -n dokku -- dokku ssh-keys:add admin 1> /dev/null
	@echo $(GITHUB_PAT) | kubectl exec -i $(POD_NAME) -n dokku -- dokku registry:login $(GITHUB_PACKAGE_URL) $(GITHUB_USERNAME) --password-stdin 1> /dev/null
	@kubectl exec -i $(POD_NAME) -n dokku -- sh -c "kubectl create secret generic registry-credential --from-file=.dockerconfigjson=/home/dokku/.docker/config.json --type=kubernetes.io/dockerconfigjson --dry-run=client -o yaml | kubectl apply -n dokku -f -"
	@kubectl exec -i $(POD_NAME) -n dokku -- dokku config:set --global CERT_MANAGER_EMAIL=$(CERT_MANAGER_EMAIL) 1> /dev/null
	@kubectl exec -i $(POD_NAME) -n dokku -- dokku domains:set-global $(GLOBAL_DOMAIN) 1> /dev/null
	@kubectl exec -i $(POD_NAME) -n dokku -- dokku registry:set --global server $(GITHUB_PACKAGE_URL) 1> /dev/null
	@kubectl exec -i $(POD_NAME) -n dokku -- dokku registry:set --global image-repo-template "$(GITHUB_USERNAME)/{{ .AppName }}" 1> /dev/null
	@kubectl exec -i $(POD_NAME) -n dokku -- dokku builder:set --global selected herokuish # Use herokuish globally since CNB requires Docker access
	@echo "Waiting for load balancer address up to 10 minutes..."
	@kubectl wait --for=jsonpath=".status.loadBalancer.ingress[0].hostname" --timeout=10m svc/ingress-nginx-controller -n ingress-nginx 1> /dev/null
	@LB_ADDRESS=$$($(call get_loadbalancer_address)); \
	if [ -z "$$LB_ADDRESS" ]; then \
	  echo "Load balancer address not found. Waiting additional 30 seconds..."; \
	  sleep 30; \
	  LB_ADDRESS=$$($(call get_loadbalancer_address)); \
	  if [ -z "$$LB_ADDRESS" ]; then \
		echo "ERROR: Load balancer address still not available after waiting"; \
	  fi; \
	fi; \
	echo "Load balancer address: $$LB_ADDRESS"; \
	$(eval NODE_IP := $(shell $(call get_node_external_ip))) \
	echo ""; \
	echo "-----------------------"; \
	echo "Successfully configured"; \
	echo "Now add the following DNS record to your domain:"; \
	echo "  CNAME *.$(GLOBAL_DOMAIN) $${LB_ADDRESS:-<load-balancer-address>}"; \
	echo "After that you need to also add ssh config to your ~/.ssh/config (create it if you don't have it already):\n"; \
	echo "Host dokku"; \
	echo "  Hostname $(NODE_IP)"; \
	echo "  Port 30022"; \
	echo "  User dokku"; \
	echo "  IdentityFile $(SSH_PATH)"; \
	echo ""

.PHONY: deconfigure
deconfigure: check-dokku
	$(call check_required_param,$(GLOBAL_DOMAIN),GLOBAL_DOMAIN,make deconfigure GLOBAL_DOMAIN=<example.com>)
	@echo "Resetting configuration ..."
	$(eval POD_NAME := $(shell $(call get_dokku_pod_name)))
	@echo "Using pod: $(POD_NAME)"
	@kubectl exec -i $(POD_NAME) -n dokku -- dokku ssh-keys:remove admin 1> /dev/null
	@kubectl delete secret registry-credential -n dokku 1> /dev/null
	@kubectl exec -i $(POD_NAME) -n dokku -- dokku config:unset --global CERT_MANAGER_EMAIL 1> /dev/null
	@kubectl exec -i $(POD_NAME) -n dokku -- dokku domains:remove-global $(GLOBAL_DOMAIN) 1> /dev/null
	@kubectl exec -i $(POD_NAME) -n dokku -- dokku registry:set --global server 1> /dev/null
	@kubectl exec -i $(POD_NAME) -n dokku -- dokku registry:set --global image-repo-template 1> /dev/null
	@echo "Successful reset configuration"

.PHONY: create-app
create-app: check-dokku
	$(call check_required_param,$(APP_NAME),APP_NAME,make configure APP_NAME=<name of an app>)
	@echo "Creating an app $(APP_NAME)..."
	$(eval POD_NAME := $(shell $(call get_dokku_pod_name)))
	@echo "Using pod: $(POD_NAME)"
	@kubectl exec -i $(POD_NAME) -n dokku -- dokku apps:create $(APP_NAME)
	@kubectl exec -i $(POD_NAME) -n dokku -- dokku config:set $(APP_NAME) DOKKU_APP_PROXY_TYPE=nginx-ingress
	@kubectl exec -i $(POD_NAME) -n dokku -- dokku scheduler-kubernetes:set $(APP_NAME) namespace $(APP_NAME)
	@kubectl exec -i $(POD_NAME) -n dokku -- dokku scheduler-kubernetes:set $(APP_NAME) cert-manager-enabled true
	@kubectl exec -i $(POD_NAME) -n dokku -- dokku scheduler-kubernetes:set $(APP_NAME) imagePullSecrets registry-credential
	@kubectl exec -i $(POD_NAME) -n dokku -- dokku domains:set $(APP_NAME) $(APP_NAME).$(GLOBAL_DOMAIN)
	@kubectl create namespace $(APP_NAME) --dry-run=client -o yaml | kubectl apply -f -
	@kubectl get secret registry-credential -n dokku -o yaml | sed "s/namespace: dokku/namespace: $(APP_NAME)/" | kubectl apply -n $(APP_NAME)  -f -
	@echo "\n\nSuccessfully created an app"
	@echo "You can now deploy your app using the following remote:"
	@echo "  dokku@dokku:$(APP_NAME)"
	@echo "Here are example commands:"
	@echo "  git remote add dokku dokku@dokku:$(APP_NAME)"
	@echo "  git push dokku main"

.PHONY: delete-app
delete-app: check-dokku
	$(call check_required_param,$(APP_NAME),APP_NAME,make delete-app APP_NAME=<name of an app>)
	@echo "Deleting app $(APP_NAME)..."
	$(eval POD_NAME := $(shell $(call get_dokku_pod_name)))
	@echo "Using pod: $(POD_NAME)"
	@kubectl exec -i $(POD_NAME) -n dokku -- dokku apps:destroy $(APP_NAME)
	@kubectl delete namespace $(APP_NAME)
	@echo "Successfully deleted app $(APP_NAME)"

.PHONY: list-apps
list-apps: check-dokku
	$(eval POD_NAME := $(shell $(call get_dokku_pod_name)))
	@echo "Using pod: $(POD_NAME)"
	@echo ""
	@kubectl exec -i $(POD_NAME) -n dokku -- dokku apps:list
	@echo ""

.PHONY: dokku
dokku: check-dokku
	$(eval POD_NAME := $(shell $(call get_dokku_pod_name)))
	@echo "Using pod: $(POD_NAME)"
	@kubectl exec -i $(POD_NAME) -n dokku -- dokku $(filter-out $@,$(MAKECMDGOALS))

.PHONY: cleanup-docker
cleanup-docker:
	@echo "Cleaning up docker..."
	$(eval POD_NAME := $(shell $(call get_dokku_pod_name)))
	@echo "Using pod: $(POD_NAME)"
	@kubectl exec -i $(POD_NAME) -n dokku -- docker system prune
	@echo "Docker cleanup completed."

# Prevent make from treating arguments as targets
%:
	@:
