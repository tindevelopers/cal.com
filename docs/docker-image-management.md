# Docker Image Management Guide

This guide explains how to pull Docker images built by Google Cloud Build and push them to GitHub Container Registry (GHCR).

## Overview

When you deploy using Cloud Build, Docker images are stored in:
- **Google Container Registry (GCR)**: `gcr.io/cal-com-tin/calcom:latest`
- **Artifact Registry**: `europe-west1-docker.pkg.dev/cal-com-tin/...`

You can:
1. ✅ Pull these images to your local machine
2. ✅ Push them to GitHub Container Registry (ghcr.io)
3. ✅ Build locally and push directly to GitHub

## Prerequisites

1. **Google Cloud SDK** installed and authenticated:
   ```bash
   gcloud auth login
   gcloud auth configure-docker gcr.io
   ```

2. **Docker** installed locally

3. **GitHub Personal Access Token** with `write:packages` permission:
   - Create at: https://github.com/settings/tokens
   - Required scopes: `write:packages`, `read:packages`

## Quick Start

### 1. Pull Image from Google Cloud Registry

```bash
# Pull the latest image
./scripts/docker-image-management.sh pull latest

# Pull a specific build
./scripts/docker-image-management.sh pull e5a07d27-0fe1-4936-be88-8cf095ae5577

# List available images
./scripts/docker-image-management.sh list
```

### 2. Push Image to GitHub Container Registry

```bash
# Set your GitHub username
export GITHUB_USER=your-github-username

# Pull from GCR and push to GitHub
./scripts/docker-image-management.sh push-to-github latest

# Push a specific tag
./scripts/docker-image-management.sh push-to-github e5a07d27-0fe1-4936-be88-8cf095ae5577 v1.0.0
```

### 3. Build Locally and Push to GitHub

```bash
export GITHUB_USER=your-github-username
./scripts/docker-image-management.sh build-and-push v1.0.0
```

## Manual Commands

### Pull from GCR

```bash
# Authenticate
gcloud auth configure-docker gcr.io

# Pull image
docker pull gcr.io/cal-com-tin/calcom:latest

# Or pull specific build
docker pull gcr.io/cal-com-tin/calcom:e5a07d27-0fe1-4936-be88-8cf095ae5577
```

### Push to GitHub Container Registry

```bash
# Tag the image
docker tag gcr.io/cal-com-tin/calcom:latest ghcr.io/YOUR_USERNAME/calcom:latest

# Login to GitHub Container Registry
echo $GITHUB_TOKEN | docker login ghcr.io -u YOUR_USERNAME --password-stdin

# Push
docker push ghcr.io/YOUR_USERNAME/calcom:latest
```

### Build Locally

```bash
# Build with same args as Cloud Build
docker build \
  --build-arg NEXT_PUBLIC_WEBAPP_URL=https://your-app.com \
  --build-arg BUILD_STANDALONE=true \
  -t ghcr.io/YOUR_USERNAME/calcom:latest \
  .

# Push
docker push ghcr.io/YOUR_USERNAME/calcom:latest
```

## Image Tags

Cloud Build creates two tags:
- `${BUILD_ID}`: Unique build identifier (e.g., `e5a07d27-0fe1-4936-be88-8cf095ae5577`)
- `latest`: Always points to the most recent build

## GitHub Container Registry

After pushing to GHCR, your image will be available at:
- **URL**: `https://github.com/YOUR_USERNAME/cal.com/pkgs/container/calcom`
- **Pull command**: `docker pull ghcr.io/YOUR_USERNAME/calcom:latest`

### Making Images Public

By default, images are private. To make them public:

1. Go to: https://github.com/YOUR_USERNAME?tab=packages
2. Click on your package
3. Go to "Package settings" → "Change visibility" → "Make public"

Or use GitHub CLI:
```bash
gh api \
  --method POST \
  -H "Accept: application/vnd.github+json" \
  /user/packages/container/calcom/visibility \
  -f visibility=public
```

## Use Cases

### 1. Testing Cloud Build Images Locally

```bash
# Pull the latest build
./scripts/docker-image-management.sh pull latest

# Run locally
docker run -p 3000:3000 \
  -e DATABASE_URL=postgresql://... \
  -e NEXTAUTH_SECRET=... \
  gcr.io/cal-com-tin/calcom:latest
```

### 2. Sharing Images with Team

Push to GitHub Container Registry and share the image URL with your team.

### 3. CI/CD Integration

Use GitHub Container Registry images in GitHub Actions:

```yaml
- name: Run tests
  run: |
    docker pull ghcr.io/YOUR_USERNAME/calcom:latest
    docker run --rm ghcr.io/YOUR_USERNAME/calcom:latest npm test
```

## Troubleshooting

### Authentication Issues

```bash
# Re-authenticate with GCR
gcloud auth configure-docker gcr.io

# Re-authenticate with GitHub
docker logout ghcr.io
echo $GITHUB_TOKEN | docker login ghcr.io -u YOUR_USERNAME --password-stdin
```

### Permission Denied

- Ensure your GitHub token has `write:packages` permission
- Check that you're logged in: `docker login ghcr.io`

### Image Not Found

- Verify the image exists: `gcloud container images list-tags gcr.io/cal-com-tin/calcom`
- Check the build ID is correct

## Notes

- **Source Code**: The source code is already in your local repo. Docker images are built artifacts.
- **Image Size**: Docker images are typically 500MB-2GB. Ensure you have enough disk space.
- **Registry Limits**: 
  - GCR: Free tier includes 0.5GB storage
  - GHCR: Free for public repos, 500MB for private repos

