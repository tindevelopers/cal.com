# Cloud Build Trigger Setup Guide

This guide explains how to set up automatic Cloud Run deployments on git push to main.

## Prerequisites

- Google Cloud Project with Cloud Build API enabled
- GitHub repository access
- `gcloud` CLI installed and authenticated

## Quick Setup

Run the setup script:

```bash
./scripts/setup-cloud-build-trigger.sh
```

## Manual Setup Steps

### Step 1: Create GitHub Connection

You have two options:

#### Option A: GitHub App (Recommended)

1. Install the Google Cloud Build GitHub App:
   - Visit: https://github.com/apps/google-cloud-build
   - Click "Install"
   - Select the repository: `tindevelopers/cal.com`
   - Note the **App Installation ID** (found in app settings)

2. Create the connection:
```bash
gcloud builds connections create github \
  --region=global \
  --connection-name="github-connection" \
  --app-installation-id="YOUR_APP_INSTALLATION_ID"
```

#### Option B: OAuth (Interactive)

```bash
gcloud builds connections create github \
  --region=global \
  --connection-name="github-connection"
```

This will open a browser for GitHub OAuth authorization.

### Step 2: Create the Trigger

```bash
gcloud builds triggers create github \
  --name="calcom-deploy-main" \
  --repo-name="cal.com" \
  --repo-owner="tindevelopers" \
  --branch-pattern="^main$" \
  --build-config="cloudbuild.yaml" \
  --region=global \
  --connection="github-connection" \
  --substitutions="_NEXT_PUBLIC_WEBAPP_URL=https://calcom-europe-west1-cal-com-tin.a.run.app,_NEXTAUTH_URL=https://calcom-europe-west1-cal-com-tin.a.run.app/api/auth,_REGION=europe-west1,_SERVICE_NAME=calcom,_ARTIFACT_REGISTRY_REPO=gcr.io,_IMAGE_TAG=gcr.io/cal-com-tin/calcom,_MEMORY=4Gi,_CPU=2,_USE_SECRETS=false,_DATABASE_URL=YOUR_DATABASE_URL,_NEXTAUTH_SECRET=YOUR_SECRET,_CALENDSO_ENCRYPTION_KEY=YOUR_KEY"
```

**Important:** Replace the placeholder values:
- `YOUR_DATABASE_URL` - Your PostgreSQL connection string
- `YOUR_SECRET` - Your NextAuth secret
- `YOUR_KEY` - Your Cal.com encryption key

### Step 3: Verify the Trigger

```bash
# List triggers
gcloud builds triggers list

# Describe trigger
gcloud builds triggers describe calcom-deploy-main

# Test trigger manually
gcloud builds triggers run calcom-deploy-main --branch=main
```

## Using Secret Manager (Optional)

For better security, you can use Secret Manager instead of build substitutions:

1. Store secrets in Secret Manager:
```bash
echo -n "your-database-url" | gcloud secrets create calcom-database-url --data-file=-
echo -n "your-nextauth-secret" | gcloud secrets create calcom-nextauth-secret --data-file=-
echo -n "your-encryption-key" | gcloud secrets create calcom-encryption-key --data-file=-
```

2. Grant Cloud Build access:
```bash
gcloud secrets add-iam-policy-binding calcom-database-url \
  --member="serviceAccount:PROJECT_NUMBER@cloudbuild.gserviceaccount.com" \
  --role="roles/secretmanager.secretAccessor"
```

3. Update the trigger to use `_USE_SECRETS=true` and secret names.

## Troubleshooting

### Connection Issues

- Verify GitHub App is installed and has repository access
- Check connection status: `gcloud builds connections describe github-connection --region=global`
- Connection must be in `READY` state before creating triggers

### Build Failures

- Check build logs: `gcloud builds list --limit=5`
- View specific build: `gcloud builds describe BUILD_ID`
- Ensure all substitutions are provided correctly

### Permission Issues

- Cloud Build service account needs Cloud Run Admin role
- Cloud Build service account needs Secret Manager Secret Accessor (if using secrets)
- Grant permissions:
```bash
PROJECT_NUMBER=$(gcloud projects describe cal-com-tin --format="value(projectNumber)")
gcloud projects add-iam-policy-binding cal-com-tin \
  --member="serviceAccount:${PROJECT_NUMBER}@cloudbuild.gserviceaccount.com" \
  --role="roles/run.admin"
```

## Monitoring

- View recent builds: `gcloud builds list --limit=10`
- View build logs: `gcloud builds log BUILD_ID`
- Monitor in Console: https://console.cloud.google.com/cloud-build/builds

## Disabling the Trigger

To temporarily disable:
```bash
gcloud builds triggers update calcom-deploy-main --disabled
```

To delete:
```bash
gcloud builds triggers delete calcom-deploy-main
```

