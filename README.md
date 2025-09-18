# UpCloud Application Stacks

This repository contains UpCloud initiatives and automation tools to help users easily deploy popular open-source platforms on UpCloud infrastructure. Whether you're running on Managed Kubernetes or virtual servers, this repo provides ready-to-use scripts and configurations to get you started quickly.

## Available Stacks

- **Supabase on Managed Kubernetes**  
  Located in [`supabase/`](./supabase)  
  A full-featured Supabase deployment using UpCloud Managed Kubernetes with persistent storage and support for custom S3 and SMTP settings.
  More details at ./supabase/README.md

- **Supabase on Virtual Server (Terraform)**  
  Located in [`supabase-terraform/`](./supabase-terraform)  
  Provision a standalone Supabase instance on an UpCloud virtual server using Terraform. 
  More details at ./supabase-terraform/README.md

- **Dokku Builder on Managed Kubernetes**  
  Located in [`dokku/`](./dokku)  
  Deploy a Dokku builder on UpCloud Managed Kubernetes. Dokku provides a Heroku-like experience, letting you deploy applications via `git push`. The deployment includes ingress, SSL support, and automated configuration of networking and load balancers. 
  For more details go to ./dokku/README.md


## Purpose

The goal of this repository is to offer high-quality, production-ready templates and scripts to reduce the effort required to deploy and manage modern development stacks on UpCloud.

## Coming Soon

- Dokku deployment scripts
- Additional popular stacks for developers

## Contributions

Feel free to open issues or submit pull requests with improvements or new stack ideas!

