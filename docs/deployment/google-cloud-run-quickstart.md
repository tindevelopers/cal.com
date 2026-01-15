# Google Cloud Run Quick Start

Quick reference for deploying Cal.com to Google Cloud Run.

## Prerequisites

```bash
# Install gcloud CLI if not already installed
# https://cloud.google.com/sdk/docs/install

# Login and set project
gcloud auth login
gcloud config set project YOUR_PROJECT_ID

# Enable required APIs
gcloud services enable \
  artifactregistry.googleapis.com \
  run.googleapis.com \
  cloudbuild.googleapis.com \
  secretmanager.googleapis.com
```

## One-Time Setup

### 1. Create Artifact Registry Repository

```bash
gcloud artifacts repositories create calcom-images \
  --repository-format=docker \
  --location=us-central1
```

### 2. Create Secrets

```bash
# Database URL
echo -n "postgresql://user:password@host:5432/database" | \
  gcloud secrets create calcom-database-url --data-file=-

# NextAuth Secret (generate random)
openssl rand -base64 32 | \
  gcloud secrets create calcom-nextauth-secret --data-file=-

# Encryption Key (generate random)
openssl rand -base64 32 | \
  gcloud secrets create calcom-encryption-key --data-file=-
```

### 3. Grant Secret Access

```bash
PROJECT_NUMBER=$(gcloud projects describe $(gcloud config get-value project) --format="value(projectNumber)")
SERVICE_ACCOUNT="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"

for secret in calcom-database-url calcom-nextauth-secret calcom-encryption-key; do
  gcloud secrets add-iam-policy-binding $secret \
    --member="serviceAccount:${SERVICE_ACCOUNT}" \
    --role="roles/secretmanager.secretAccessor"
done
```

## Deploy

### Option 1: Using the Deployment Script

```bash
./scripts/deploy-cloud-run.sh
```

### Option 2: Using Cloud Build Directly

```bash
gcloud builds submit --config=cloudbuild.yaml \
  --substitutions=_NEXT_PUBLIC_WEBAPP_URL=https://your-domain.com,\
_NEXTAUTH_URL=https://your-domain.com/api/auth,\
_DATABASE_URL_SECRET_NAME=calcom-database-url,\
_NEXTAUTH_SECRET_NAME=calcom-nextauth-secret,\
_CALENDSO_ENCRYPTION_KEY_NAME=calcom-encryption-key
```

### Option 3: Manual Docker Build & Deploy

```bash
# Build
docker build \
  --build-arg NEXT_PUBLIC_WEBAPP_URL=https://your-domain.com \
  --build-arg DATABASE_URL="$(gcloud secrets versions access latest --secret=calcom-database-url)" \
  --build-arg NEXTAUTH_SECRET="$(gcloud secrets versions access latest --secret=calcom-nextauth-secret)" \
  --build-arg CALENDSO_ENCRYPTION_KEY="$(gcloud secrets versions access latest --secret=calcom-encryption-key)" \
  -t us-central1-docker.pkg.dev/$(gcloud config get-value project)/calcom-images/calcom:latest .

# Push
docker push us-central1-docker.pkg.dev/$(gcloud config get-value project)/calcom-images/calcom:latest

# Deploy
gcloud run deploy calcom \
  --image us-central1-docker.pkg.dev/$(gcloud config get-value project)/calcom-images/calcom:latest \
  --region us-central1 \
  --platform managed \
  --allow-unauthenticated \
  --port 3000 \
  --memory 2Gi \
  --cpu 2 \
  --set-env-vars NODE_ENV=production,NEXT_PUBLIC_WEBAPP_URL=https://your-domain.com \
  --set-secrets DATABASE_URL=calcom-database-url:latest,DATABASE_DIRECT_URL=calcom-database-url:latest,NEXTAUTH_SECRET=calcom-nextauth-secret:latest,CALENDSO_ENCRYPTION_KEY=calcom-encryption-key:latest
```

## Required Environment Variables

| Variable | Description | Source |
|----------|-------------|--------|
| `NEXT_PUBLIC_WEBAPP_URL` | Your Cal.com web app URL | Environment variable |
| `NEXTAUTH_URL` | Auth callback URL | Environment variable (usually `${NEXT_PUBLIC_WEBAPP_URL}/api/auth`) |
| `DATABASE_URL` | PostgreSQL connection string | Secret Manager |
| `DATABASE_DIRECT_URL` | Direct DB connection (usually same as DATABASE_URL) | Secret Manager |
| `NEXTAUTH_SECRET` | NextAuth secret | Secret Manager |
| `CALENDSO_ENCRYPTION_KEY` | Encryption key | Secret Manager |

## Get Service URL

```bash
gcloud run services describe calcom --region=us-central1 --format="value(status.url)"
```

## View Logs

```bash
gcloud run services logs read calcom --region=us-central1 --limit=50
```

## Update Deployment

Simply re-run the deployment command. Cloud Run will perform a rolling update.

## Troubleshooting

- **Container fails to start**: Check logs with `gcloud run services logs read`
- **Database connection issues**: Verify secrets and network connectivity
- **Build failures**: Check Cloud Build logs in the GCP Console

For detailed information, see [google-cloud-run.md](./google-cloud-run.md).

