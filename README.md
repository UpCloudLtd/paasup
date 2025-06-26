
# Supabase Deployment on UpCloud Managed Kubernetes

This repository provides a ready-to-use script to deploy a complete [Supabase](https://supabase.com/) backend on [UpCloud Managed Kubernetes](https://upcloud.com/products/kubernetes), offering a secure, persistent, and customizable setup ideal for both development and production use.

## 🚀 What This Deploys

Running the script sets up a fully working Supabase instance that includes:

- **PostgreSQL Database**: Backed by Kubernetes Persistent Volume Claims (PVCs) for data durability.
- **Supabase Studio**: Web-based admin dashboard for managing schema, auth, and file storage.
- **Kong API Gateway**: Public gateway for secure access to Supabase services.
- **Real-time Engine and REST APIs**: Auto-generated for database tables.
- **File Storage**: S3-compatible storage support (optional).
- **Authentication Service**: Integrated support for JWT sessions, social login, and email/password sign-in.

## 🛠 Prerequisites

Before running the script, ensure you have:

- An **UpCloud account** with API access.
- Tools installed:
  - [`upctl`](https://upcloudltd.github.io/upcloud-cli/) (configured with your API credentials)
  - [`helm`](https://helm.sh/docs/intro/install/)
  - [`kubectl`](https://kubernetes.io/docs/tasks/tools/)
  - [`jq`](https://jqlang.org/download/)
  - [`git`](https://git-scm.com/book/en/v2/Getting-Started-Installing-Git)

## 📦 Cloning the Repository

```bash
git clone git@github.com:UpCloudLtd/paasup.git
cd paasup/supabase
```

## ⚙️ Configuration

Customize your deployment using the `deploy_supabase.env` file.

### Example: `deploy_supabase.env`

```env
# Studio Admin
DASHBOARD_USERNAME=supabase
DASHBOARD_PASSWORD=""                               # Will be generated if not set

# PostgreSQL
POSTGRES_PASSWORD=""                                # Will be generated if not set

# S3 Integration
ENABLE_S3=true
S3_KEY_ID=your-access-key
S3_ACCESS_KEY=your-secret-key
S3_BUCKET=supabase-bucket
S3_ENDPOINT=https://your-s3-endpoint
S3_REGION=europe-1

# SMTP Notifications
ENABLE_SMTP=false
SMTP_HOST=smtp.mailgun.org
SMTP_PORT=587
SMTP_USER=postmaster@mg.example.com
SMTP_PASS=your-smtp-password
SMTP_SENDER_NAME="MyApp <noreply@example.com>"
```

Unset values like passwords will be auto-generated during deployment.

## 🚀 Deploying Supabase

Use the following command to deploy your Supabase instance:

```bash
./deploy_supabase.sh <location> <app_name>
```

Example:

```bash
./deploy_supabase.sh fi-hel1 myapp
```

This will:

- Create (if needed) a Kubernetes cluster on UpCloud with 1 node (`2xCPU-4GB`).
- Configure a private network.
- Create a persistent volume for PostgreSQL.
- Deploy all Supabase services and components.
- Set up a LoadBalancer for public access.

## 🔁 Upgrading an Existing Deployment

To apply updates or configuration changes:

```bash
./deploy_supabase.sh --upgrade <location> <app_name>
```

If a `values.custom.yaml` file exists in the `supabase/` directory, it will be used during the upgrade.

## 🔧 Advanced Customization

Create a `values.custom.yaml` file to override Helm chart values:

```yaml
storage:
  environment:
    TENANT_ID: "supabase1"

secret:
  s3:
    accessKey: "your-new-secret"
```

This file allows advanced users to fine-tune settings beyond `deploy_supabase.env`. These values override those in `charts/supabase/values.yaml`.

> **Note:** You should understand Helm chart structures before using advanced overrides.

## 📡 Script Output: How to Connect

When the script completes, it prints useful access details:

```bash
[INFO] Supabase deployed successfully!
[INFO] Public endpoint: http://lb-xxxx.upcloudlb.com:8000
[INFO] Namespace: supabase-myapp-fi-hel1
[INFO] ANON_KEY: eyJhbGciOiJIUzI1...
[INFO] SERVICE_ROLE_KEY: eyJhbGciOiJIUzI1...
[INFO] POSTGRES_PASSWORD: ********
[INFO] DASHBOARD_USERNAME: supabase
[INFO] DASHBOARD_PASSWORD: ********
[INFO] S3 ENABLED: true
[INFO] SMTP ENABLED: false
```

These values help you:

- Connect Supabase SDKs to your backend.
- Log in to Supabase Studio.
- Access your API endpoints and manage your project.

## 🤝 Contributing

Contributions, issues, and suggestions are welcome! Please open an issue or submit a PR.

## 📄 License

MIT License
