# Google Cloud Run Deployment Guide

This guide covers deploying Cal.com to Google Cloud Run using Docker containers.

## Prerequisites

1. Google Cloud Platform account with billing enabled
2. `gcloud` CLI installed and configured
3. Docker installed (for local testing)
4. Artifact Registry API enabled
5. Cloud Run API enabled
6. Cloud Build API enabled

## Setup

### 1. Enable Required APIs

```bash
gcloud services enable \
  artifactregistry.googleapis.com \
  run.googleapis.com \
  cloudbuild.googleapis.com
```

### 2. Create Artifact Registry Repository

```bash
gcloud artifacts repositories create calcom-images \
  --repository-format=docker \
  --location=us-central1 \
  --description="Cal.com Docker images"
```

### 3. Configure Cloud Build Substitutions

Create a `cloudbuild-substitutions.yaml` file or set substitution variables:

```bash
# Required substitutions
gcloud builds submit --config=cloudbuild.yaml \
  --substitutions=_NEXT_PUBLIC_WEBAPP_URL=https://your-domain.com,\
_NEXT_PUBLIC_API_V2_URL=https://api.your-domain.com,\
_NEXTAUTH_URL=https://your-domain.com/api/auth,\
_DATABASE_URL_SECRET_NAME=calcom-database-url,\
_NEXTAUTH_SECRET_NAME=calcom-nextauth-secret,\
_CALENDSO_ENCRYPTION_KEY_NAME=calcom-encryption-key
```

### 4. Create Secrets in Secret Manager

Store sensitive values in Google Secret Manager:

```bash
# Database URL
echo -n "postgresql://user:password@host:5432/database" | \
  gcloud secrets create calcom-database-url --data-file=-

# NextAuth Secret (generate a random string)
openssl rand -base64 32 | \
  gcloud secrets create calcom-nextauth-secret --data-file=-

# Encryption Key (generate a random string)
openssl rand -base64 32 | \
  gcloud secrets create calcom-encryption-key --data-file=-
```

Grant Cloud Run service account access to secrets:

```bash
PROJECT_NUMBER=$(gcloud projects describe $(gcloud config get-value project) --format="value(projectNumber)")
SERVICE_ACCOUNT="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"

gcloud secrets add-iam-policy-binding calcom-database-url \
  --member="serviceAccount:${SERVICE_ACCOUNT}" \
  --role="roles/secretmanager.secretAccessor"

gcloud secrets add-iam-policy-binding calcom-nextauth-secret \
  --member="serviceAccount:${SERVICE_ACCOUNT}" \
  --role="roles/secretmanager.secretAccessor"

gcloud secrets add-iam-policy-binding calcom-encryption-key \
  --member="serviceAccount:${SERVICE_ACCOUNT}" \
  --role="roles/secretmanager.secretAccessor"
```

## Deployment

### Option 1: Using Cloud Build (Recommended)

```bash
gcloud builds submit --config=cloudbuild.yaml \
  --substitutions=_NEXT_PUBLIC_WEBAPP_URL=https://your-domain.com,\
_NEXT_PUBLIC_API_V2_URL=https://api.your-domain.com,\
_NEXTAUTH_URL=https://your-domain.com/api/auth,\
_DATABASE_URL_SECRET_NAME=calcom-database-url,\
_NEXTAUTH_SECRET_NAME=calcom-nextauth-secret,\
_CALENDSO_ENCRYPTION_KEY_NAME=calcom-encryption-key,\
_REGION=us-central1,\
_SERVICE_NAME=calcom
```

### Option 2: Manual Build and Deploy

1. Build the Docker image:

```bash
docker build \
  --build-arg NEXT_PUBLIC_WEBAPP_URL=https://your-domain.com \
  --build-arg NEXT_PUBLIC_API_V2_URL=https://api.your-domain.com \
  --build-arg DATABASE_URL="postgresql://..." \
  --build-arg NEXTAUTH_SECRET="your-secret" \
  --build-arg CALENDSO_ENCRYPTION_KEY="your-key" \
  -t gcr.io/PROJECT_ID/calcom:latest .
```

2. Push to Artifact Registry:

```bash
docker tag gcr.io/PROJECT_ID/calcom:latest \
  us-central1-docker.pkg.dev/PROJECT_ID/calcom-images/calcom:latest

docker push us-central1-docker.pkg.dev/PROJECT_ID/calcom-images/calcom:latest
```

3. Deploy to Cloud Run:

```bash
gcloud run deploy calcom \
  --image us-central1-docker.pkg.dev/PROJECT_ID/calcom-images/calcom:latest \
  --region us-central1 \
  --platform managed \
  --allow-unauthenticated \
  --port 3000 \
  --memory 2Gi \
  --cpu 2 \
  --min-instances 0 \
  --max-instances 10 \
  --timeout 300 \
  --concurrency 80 \
  --set-env-vars NODE_ENV=production,NEXT_PUBLIC_WEBAPP_URL=https://your-domain.com \
  --set-secrets DATABASE_URL=calcom-database-url:latest,DATABASE_DIRECT_URL=calcom-database-url:latest,NEXTAUTH_SECRET=calcom-nextauth-secret:latest,CALENDSO_ENCRYPTION_KEY=calcom-encryption-key:latest
```

## Configuration

### Environment Variables

Required environment variables (set via Cloud Run):

- `NEXT_PUBLIC_WEBAPP_URL` - Your Cal.com web app URL
- `NEXT_PUBLIC_API_V2_URL` - Your API v2 URL (if using separate API service)
- `NEXTAUTH_URL` - NextAuth callback URL (usually `${NEXT_PUBLIC_WEBAPP_URL}/api/auth`)
- `DATABASE_URL` - PostgreSQL connection string (stored in Secret Manager)
- `DATABASE_DIRECT_URL` - Direct database connection (usually same as DATABASE_URL)
- `NEXTAUTH_SECRET` - Secret for NextAuth (stored in Secret Manager)
- `CALENDSO_ENCRYPTION_KEY` - Encryption key for sensitive data (stored in Secret Manager)

Optional environment variables:

- `NEXT_PUBLIC_SINGLE_ORG_SLUG` - Single organization mode
- `ORGANIZATIONS_ENABLED` - Enable organizations (set to "1" or "true")
- `CALCOM_TELEMETRY_DISABLED` - Disable telemetry (set to "1")
- `CSP_POLICY` - Content Security Policy setting

### Resource Configuration

Adjust these in `cloudbuild.yaml` or via `gcloud run deploy`:

- `--memory`: Memory allocation (default: 2Gi, recommended: 2-4Gi)
- `--cpu`: CPU allocation (default: 2, recommended: 2-4)
- `--min-instances`: Minimum instances to keep warm (default: 0)
- `--max-instances`: Maximum instances (default: 10)
- `--timeout`: Request timeout in seconds (default: 300)
- `--concurrency`: Concurrent requests per instance (default: 80)

### Database Setup

Cal.com requires a PostgreSQL database. Options:

1. **Cloud SQL**: Managed PostgreSQL on GCP
2. **AlloyDB**: High-performance PostgreSQL on GCP
3. **External Database**: Any PostgreSQL instance accessible from Cloud Run

Ensure your Cloud Run service can connect to the database (VPC connector may be needed for private IPs).

## Custom Domain

1. Map a custom domain in Cloud Run:

```bash
gcloud run domain-mappings create \
  --service calcom \
  --domain your-domain.com \
  --region us-central1
```

2. Update your DNS records as instructed by the command output.

## Monitoring and Logging

- **Logs**: View in Cloud Console → Cloud Run → Logs
- **Metrics**: Available in Cloud Console → Cloud Run → Metrics
- **Alerts**: Set up in Cloud Monitoring

## Troubleshooting

### Container fails to start

- Check logs: `gcloud run services logs read calcom --region us-central1`
- Verify secrets are accessible
- Ensure database is reachable
- Check environment variables are set correctly

### Database connection issues

- Verify DATABASE_URL format
- Check VPC connector if using private IP
- Ensure database allows connections from Cloud Run IPs
- Test connection: `gcloud run services execute calcom --region us-central1 --command="npx prisma db pull"`

### Build failures

- Check Cloud Build logs
- Verify all build arguments are provided
- Ensure sufficient build resources (machine type in cloudbuild.yaml)

## CI/CD Integration

You can trigger Cloud Build on git push by connecting your repository:

```bash
gcloud builds triggers create github \
  --name="calcom-deploy" \
  --repo-name="calcom" \
  --repo-owner="your-org" \
  --branch-pattern="^main$" \
  --build-config="cloudbuild.yaml" \
  --substitutions=_NEXT_PUBLIC_WEBAPP_URL=https://your-domain.com
```

## Cost Optimization

- Set `--min-instances=0` to scale to zero when idle
- Use appropriate memory/CPU for your traffic
- Monitor usage and adjust `--max-instances` accordingly
- Consider Cloud SQL Proxy for database connections to reduce costs

## Security Best Practices

1. Use Secret Manager for all sensitive values
2. Enable VPC connector for private database access
3. Use IAM for service authentication
4. Enable Cloud Armor for DDoS protection
5. Regularly update base images and dependencies
6. Use least-privilege IAM roles

