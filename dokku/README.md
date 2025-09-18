# Dokku on Kubernetes – Git-Push PaaS on UpCloud

Deploy and manage web apps on UpCloud Managed Kubernetes with Dokku — using simple `git push` workflows and no CI/CD pipelines.

This project automates the provisioning of a full Dokku PaaS builder in a Kubernetes cluster, backed by UpCloud's infrastructure.

## What Is This?

This setup runs a Dokku builder inside Kubernetes and lets you:

- Push apps via Git (`git push dokku@...`)
- Run apps in real Kubernetes pods
- Access apps through a single Ingress controller using wildcard domains
- Use Kubernetes-native features like scaling, pod scheduling, and self-healing

Great for developers, internal tools, MVPs, client projects, and even microservice experimentation.

## Features

- One-command deployment with `./deploy_dokku.sh deploy <region> <project>`
- Optional wildcard domain support (e.g. `*.yourdomain.com`)
- Ingress and TLS support via cert-manager
- Multi-app support with custom app names
- Compatible with public or private GitHub Container Registry (GHCR)

## Architecture
<img width="1133" height="722" alt="Screenshot from 2025-07-10 12-45-41" src="https://github.com/user-attachments/assets/3e1c2551-1665-4144-878e-8c77b98e3c21" />

## Requirements

### General

- UpCloud account with API access
- GitHub account and access to GHCR (GitHub Container Registry or Packages)

### Tools (installed locally)

- `upctl`
- `kubectl`
- `helm`
- `jq`
- `git`
- `make`

> Docker is *not required* to deploy (only needed to build or modify the Dokku image manually, which is not the common case)

## Environment Variables

These must be set before running the deployment:

| Variable             | Required | Description |
|----------------------|----------|-------------|
| `GITHUB_PAT`         | ✅ Yes   | GitHub Personal Access Token with `write:packages` and `read:packages`. Dokku uses this token to push your app’s container images into GitHub Container Registry (GHCR). Every time you `git push dokku`, Dokku builds a Docker image of your app and needs to authenticate to a registry to store that image. Without this token, deployments cannot complete. |
| `GITHUB_USERNAME`    | ✅ Yes   | Your GitHub username |
| `CERT_MANAGER_EMAIL` | Optional | Email for Let's Encrypt (default: ops@example.com) |
| `GLOBAL_DOMAIN`      | Optional | Wildcard domain (e.g. example.com). If unset, script will use the LoadBalancer hostname |
| `SSH_PATH`           | Optional | SSH private key path (default: `~/.ssh/id_rsa`) |
| `SSH_PUB_PATH`       | Optional | SSH public key path (default: `~/.ssh/id_rsa.pub`) |
| `GITHUB_PACKAGE_URL` | Optional | Container registry hostname (default: `ghcr.io`) |
| `NUM_NODES`          | Optional | Number of cluster nodes (default: 1) |

Example:

```bash
export GITHUB_PAT=ghp_abc123...
export GITHUB_USERNAME=myuser
export CERT_MANAGER_EMAIL=me@example.com
```

### Why is the GitHub token needed?

Each time you `git push dokku`, your app is built into a Docker image. That image must be stored somewhere accessible to the Kubernetes cluster so it can be deployed.  
In this setup, the GitHub Container Registry (GHCR) is used as the image registry.  

The `GITHUB_PAT` token allows Dokku to:
- **Push new images** of your apps into GHCR (`write:packages`)
- **Pull images** back into the Kubernetes cluster (`read:packages`)

This token is never used outside the build/deploy process. If you prefer, you can create a dedicated service account or robot user in GitHub just for this purpose.

## Cloning the Code

```bash
git clone git@github.com:UpCloudLtd/paasup.git
Or
git clone https://github.com/UpCloudLtd/paasup.git
```

## Deploying Dokku

```bash
./deploy_dokku.sh deploy <region> <project-name>
Example:
./deploy_dokku.sh deploy es-mad1 builder
```

This will:
Create a Kubernetes cluster
Deploy Ingress, cert-manager, and the Dokku builder pod
Wait for the LoadBalancer hostname
Configure Dokku and set the global domain
Output instructions for app deployment

## Deploying your First App

From the dokku/ folder

```bash
make create-app APP_NAME=demo-app
cd .. (You should cd into a folder where you want to have your apps)
git clone https://github.com/heroku/node-js-sample.git demo-app
cd demo-app
git remote add dokku dokku:demo-app
git push dokku master
```

Then visit:
```bash
https://demo-app.<GLOBAL_DOMAIN>
```
If you don’t have a real DNS name read the next section

## Local Testing (Without Real DNS)

If you don’t have a domain name configured, you can still test your deployed apps locally by mapping the LoadBalancer DNS name (assigned by UpCloud) to its IP address using /etc/hosts.

This DNS name usually looks like:
```bash
lb-0a39e658458348eeb6ea98ff049c6f55-1.upcloudlb.com
```
This is the external DNS name of the Kubernetes LoadBalancer service created by your Ingress controller.

Get the external IP of the LoadBalancer:
```bash
dig +short lb-0a39e658458348eeb6ea98ff049c6f55-1.upcloudlb.com
```

Add a line like this:
```bash
<EXTERNAL-IP> demo-app.lb-0a39e658458348eeb6ea98ff049c6f55-1.upcloudlb.com
```

You will be able to load your app at:
```bash
https://demo-app.lb-0a39e658458348eeb6ea98ff049c6f55-1.upcloudlb.com
```

That was the general explanation, the script will output specific instructions on how to do this with your values when it finishes. You should be able to copy paste it.

## Deploying more Apps

You can deploy more apps in the cluster. They will be available on their own subdomain: https://<APP_NAME>.<GLOBAL_DOMAIN>
```bash
make create-app APP_NAME=another-app
git remote add dokku dokku:another-app
git push dokku master
```

## Contributing

PRs welcome! Feel free to open issues or contribute improvements.

## Questions?

Open an issue or reach out — we’re happy to help you get started.
