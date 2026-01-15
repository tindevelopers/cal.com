#!/bin/bash
set -e

# Google Cloud Run Deployment Script for Cal.com
# Usage: ./scripts/deploy-cloud-run.sh

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if gcloud is installed
if ! command -v gcloud &> /dev/null; then
    echo -e "${RED}Error: gcloud CLI is not installed.${NC}"
    echo "Install it from: https://cloud.google.com/sdk/docs/install"
    exit 1
fi

# Get project ID
PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
if [ -z "$PROJECT_ID" ]; then
    echo -e "${RED}Error: No GCP project configured.${NC}"
    echo "Run: gcloud config set project YOUR_PROJECT_ID"
    exit 1
fi

echo -e "${GREEN}Deploying Cal.com to Google Cloud Run${NC}"
echo "Project: $PROJECT_ID"
echo ""

# List existing services
echo -e "${YELLOW}Existing Cloud Run services:${NC}"
gcloud run services list --project=$PROJECT_ID --format="table(metadata.name,status.url)" 2>/dev/null | head -10 || echo "  (Unable to list services)"
echo ""

# Prompt for required variables (prefer values from .env if available)
ENV_WEBAPP_URL=""
ENV_API_V2_URL=""
if [ -f .env ]; then
    ENV_WEBAPP_URL=$(grep "^NEXT_PUBLIC_WEBAPP_URL=" .env | cut -d '=' -f2- | tr -d '"' | tr -d "'" | head -1 || true)
    ENV_API_V2_URL=$(grep "^NEXT_PUBLIC_API_V2_URL=" .env | cut -d '=' -f2- | tr -d '"' | tr -d "'" | head -1 || true)
fi

if [ -n "$ENV_WEBAPP_URL" ]; then
    read -p "Enter NEXT_PUBLIC_WEBAPP_URL [${ENV_WEBAPP_URL}]: " NEXT_PUBLIC_WEBAPP_URL
    NEXT_PUBLIC_WEBAPP_URL=${NEXT_PUBLIC_WEBAPP_URL:-$ENV_WEBAPP_URL}
else
    read -p "Enter NEXT_PUBLIC_WEBAPP_URL (e.g., https://app.example.com): " NEXT_PUBLIC_WEBAPP_URL
fi

if [ -n "$ENV_API_V2_URL" ]; then
    read -p "Enter NEXT_PUBLIC_API_V2_URL (optional) [${ENV_API_V2_URL}]: " NEXT_PUBLIC_API_V2_URL
    NEXT_PUBLIC_API_V2_URL=${NEXT_PUBLIC_API_V2_URL:-$ENV_API_V2_URL}
else
    read -p "Enter NEXT_PUBLIC_API_V2_URL (optional, press Enter to skip): " NEXT_PUBLIC_API_V2_URL
fi

# Check available artifact registries
echo ""
echo -e "${YELLOW}Available Artifact Registries:${NC}"
gcloud artifacts repositories list --project=$PROJECT_ID --format="table(name,location)" 2>/dev/null | head -5 || echo "  (Unable to list repositories)"
read -p "Enter Artifact Registry repository name [gcr.io]: " ARTIFACT_REGISTRY_REPO
ARTIFACT_REGISTRY_REPO=${ARTIFACT_REGISTRY_REPO:-gcr.io}

read -p "Enter Cloud Run service name [calcom]: " SERVICE_NAME
SERVICE_NAME=${SERVICE_NAME:-calcom}

read -p "Enter region [europe-west1]: " REGION
REGION=${REGION:-europe-west1}

read -p "Enter memory allocation [2Gi]: " MEMORY
MEMORY=${MEMORY:-2Gi}

read -p "Enter CPU allocation [2]: " CPU
CPU=${CPU:-2}

# Set NEXTAUTH_URL
NEXTAUTH_URL="${NEXT_PUBLIC_WEBAPP_URL}/api/auth"

# Check if Secret Manager is enabled
SECRET_MANAGER_ENABLED=false
if gcloud services list --enabled --project=$PROJECT_ID --filter="name:secretmanager.googleapis.com" --format="value(name)" 2>/dev/null | grep -q secretmanager; then
    SECRET_MANAGER_ENABLED=true
fi

# Secret names (defaults)
DATABASE_URL_SECRET_NAME="calcom-database-url"
NEXTAUTH_SECRET_NAME="calcom-nextauth-secret"
CALENDSO_ENCRYPTION_KEY_NAME="calcom-encryption-key"

if [ "$SECRET_MANAGER_ENABLED" = true ]; then
    echo ""
    echo -e "${YELLOW}Using Secret Manager secrets:${NC}"
    echo "  DATABASE_URL: $DATABASE_URL_SECRET_NAME"
    echo "  NEXTAUTH_SECRET: $NEXTAUTH_SECRET_NAME"
    echo "  CALENDSO_ENCRYPTION_KEY: $CALENDSO_ENCRYPTION_KEY_NAME"
    echo ""
    read -p "Use environment variables instead? (y/N): " USE_ENV_VARS
    if [[ "$USE_ENV_VARS" =~ ^[Yy]$ ]]; then
        USE_SECRETS=false
        echo ""
        echo -e "${YELLOW}You'll need to provide these values as environment variables:${NC}"
        echo "  DATABASE_URL"
        echo "  NEXTAUTH_SECRET"
        echo "  CALENDSO_ENCRYPTION_KEY"
    else
        USE_SECRETS=true
    fi
else
    USE_SECRETS=false
    echo ""
    echo -e "${YELLOW}Secret Manager API is not enabled.${NC}"
    echo "Using environment variables instead."
    echo ""
    
    # Try to load from .env file if it exists
    if [ -f .env ]; then
        echo -e "${GREEN}Found .env file. Loading DATABASE_URL...${NC}"
        DATABASE_URL=$(grep "^DATABASE_URL=" .env | cut -d '=' -f2- | tr -d '"' | tr -d "'" | head -1 || true)
        if [ -n "$DATABASE_URL" ]; then
            echo "  ✓ DATABASE_URL loaded from .env"
        fi
    fi
    
    # Generate secrets if not already set
    if [ -z "$NEXTAUTH_SECRET" ]; then
        echo -e "${GREEN}Generating NEXTAUTH_SECRET...${NC}"
        NEXTAUTH_SECRET=$(openssl rand -base64 32)
        echo "  ✓ Generated: $NEXTAUTH_SECRET"
    fi
    
    if [ -z "$CALENDSO_ENCRYPTION_KEY" ]; then
        echo -e "${GREEN}Generating CALENDSO_ENCRYPTION_KEY...${NC}"
        CALENDSO_ENCRYPTION_KEY=$(openssl rand -base64 32)
        echo "  ✓ Generated: $CALENDSO_ENCRYPTION_KEY"
    fi
    
    # Prompt if values are missing
    if [ -z "$DATABASE_URL" ]; then
        read -p "Enter DATABASE_URL: " DATABASE_URL
    else
        echo ""
        read -p "Use DATABASE_URL from .env? (Y/n): " USE_ENV_DB
        if [[ "$USE_ENV_DB" =~ ^[Nn]$ ]]; then
            read -p "Enter DATABASE_URL: " DATABASE_URL
        fi
    fi
    
    if [ -z "$NEXTAUTH_SECRET" ]; then
        read -p "Enter NEXTAUTH_SECRET: " NEXTAUTH_SECRET
    fi
    
    if [ -z "$CALENDSO_ENCRYPTION_KEY" ]; then
        read -p "Enter CALENDSO_ENCRYPTION_KEY: " CALENDSO_ENCRYPTION_KEY
    fi
    
    ENV_VARS_EXTRA=",DATABASE_URL=${DATABASE_URL},DATABASE_DIRECT_URL=${DATABASE_URL},NEXTAUTH_SECRET=${NEXTAUTH_SECRET},CALENDSO_ENCRYPTION_KEY=${CALENDSO_ENCRYPTION_KEY}"
    SUBSTITUTIONS="${SUBSTITUTIONS},_ENV_VARS_EXTRA=${ENV_VARS_EXTRA}"
    
    echo ""
    echo -e "${YELLOW}Secrets summary:${NC}"
    echo "  DATABASE_URL: ${DATABASE_URL:0:50}..."
    echo "  NEXTAUTH_SECRET: ${NEXTAUTH_SECRET:0:20}..."
    echo "  CALENDSO_ENCRYPTION_KEY: ${CALENDSO_ENCRYPTION_KEY:0:20}..."
fi

echo ""
read -p "Press Enter to continue or Ctrl+C to cancel..."

# Build substitutions
SUBSTITUTIONS="_NEXT_PUBLIC_WEBAPP_URL=${NEXT_PUBLIC_WEBAPP_URL}"
SUBSTITUTIONS="${SUBSTITUTIONS},_NEXTAUTH_URL=${NEXTAUTH_URL}"
SUBSTITUTIONS="${SUBSTITUTIONS},_REGION=${REGION}"
SUBSTITUTIONS="${SUBSTITUTIONS},_SERVICE_NAME=${SERVICE_NAME}"
SUBSTITUTIONS="${SUBSTITUTIONS},_ARTIFACT_REGISTRY_REPO=${ARTIFACT_REGISTRY_REPO}"
SUBSTITUTIONS="${SUBSTITUTIONS},_MEMORY=${MEMORY}"
SUBSTITUTIONS="${SUBSTITUTIONS},_CPU=${CPU}"
if [ "$USE_SECRETS" = true ]; then
    SUBSTITUTIONS="${SUBSTITUTIONS},_DATABASE_URL_SECRET_NAME=${DATABASE_URL_SECRET_NAME}"
    SUBSTITUTIONS="${SUBSTITUTIONS},_NEXTAUTH_SECRET_NAME=${NEXTAUTH_SECRET_NAME}"
    SUBSTITUTIONS="${SUBSTITUTIONS},_CALENDSO_ENCRYPTION_KEY_NAME=${CALENDSO_ENCRYPTION_KEY_NAME}"
    SUBSTITUTIONS="${SUBSTITUTIONS},_USE_SECRETS=true"
else
    SUBSTITUTIONS="${SUBSTITUTIONS},_USE_SECRETS=false"
    # Pass env vars as build substitutions when not using secrets
    if [ -n "$DATABASE_URL" ]; then
        SUBSTITUTIONS="${SUBSTITUTIONS},_DATABASE_URL=${DATABASE_URL}"
    fi
    if [ -n "$NEXTAUTH_SECRET" ]; then
        SUBSTITUTIONS="${SUBSTITUTIONS},_NEXTAUTH_SECRET=${NEXTAUTH_SECRET}"
    fi
    if [ -n "$CALENDSO_ENCRYPTION_KEY" ]; then
        SUBSTITUTIONS="${SUBSTITUTIONS},_CALENDSO_ENCRYPTION_KEY=${CALENDSO_ENCRYPTION_KEY}"
    fi
fi

if [ -n "$NEXT_PUBLIC_API_V2_URL" ]; then
    SUBSTITUTIONS="${SUBSTITUTIONS},_NEXT_PUBLIC_API_V2_URL=${NEXT_PUBLIC_API_V2_URL}"
fi

# Prompt for Sentry configuration (optional)
echo ""
echo -e "${YELLOW}Sentry Monitoring Configuration (optional):${NC}"
read -p "Enter NEXT_PUBLIC_SENTRY_DSN (for web app, press Enter to skip): " NEXT_PUBLIC_SENTRY_DSN
if [ -n "$NEXT_PUBLIC_SENTRY_DSN" ]; then
    SUBSTITUTIONS="${SUBSTITUTIONS},_NEXT_PUBLIC_SENTRY_DSN=${NEXT_PUBLIC_SENTRY_DSN}"
    
    read -p "Enter NEXT_PUBLIC_SENTRY_DSN_CLIENT (optional, press Enter to use same as above): " NEXT_PUBLIC_SENTRY_DSN_CLIENT
    if [ -n "$NEXT_PUBLIC_SENTRY_DSN_CLIENT" ]; then
        SUBSTITUTIONS="${SUBSTITUTIONS},_NEXT_PUBLIC_SENTRY_DSN_CLIENT=${NEXT_PUBLIC_SENTRY_DSN_CLIENT}"
    fi
    
    read -p "Enter SENTRY_DSN (for API v2, press Enter to skip): " SENTRY_DSN
    if [ -n "$SENTRY_DSN" ]; then
        SUBSTITUTIONS="${SUBSTITUTIONS},_SENTRY_DSN=${SENTRY_DSN}"
    fi
    
    read -p "Enter SENTRY_TRACES_SAMPLE_RATE (0.0-1.0, default 0.1): " SENTRY_TRACES_SAMPLE_RATE
    SENTRY_TRACES_SAMPLE_RATE=${SENTRY_TRACES_SAMPLE_RATE:-0.1}
    SUBSTITUTIONS="${SUBSTITUTIONS},_SENTRY_TRACES_SAMPLE_RATE=${SENTRY_TRACES_SAMPLE_RATE}"
    
    read -p "Enter SENTRY_SAMPLE_RATE (0.0-1.0, default 1.0): " SENTRY_SAMPLE_RATE
    SENTRY_SAMPLE_RATE=${SENTRY_SAMPLE_RATE:-1.0}
    SUBSTITUTIONS="${SUBSTITUTIONS},_SENTRY_SAMPLE_RATE=${SENTRY_SAMPLE_RATE}"
    
    read -p "Enter SENTRY_PROFILES_SAMPLE_RATE (0.0-1.0, default 0.1, for API v2): " SENTRY_PROFILES_SAMPLE_RATE
    if [ -n "$SENTRY_PROFILES_SAMPLE_RATE" ]; then
        SUBSTITUTIONS="${SUBSTITUTIONS},_SENTRY_PROFILES_SAMPLE_RATE=${SENTRY_PROFILES_SAMPLE_RATE}"
    fi
    
    read -p "Enable SENTRY_DEBUG? (y/N): " ENABLE_SENTRY_DEBUG
    if [[ "$ENABLE_SENTRY_DEBUG" =~ ^[Yy]$ ]]; then
        SUBSTITUTIONS="${SUBSTITUTIONS},_SENTRY_DEBUG=true"
    fi
    
    echo ""
    echo -e "${GREEN}Sentry configuration added:${NC}"
    echo "  NEXT_PUBLIC_SENTRY_DSN: ${NEXT_PUBLIC_SENTRY_DSN:0:30}..."
    echo "  SENTRY_TRACES_SAMPLE_RATE: ${SENTRY_TRACES_SAMPLE_RATE}"
    echo "  SENTRY_SAMPLE_RATE: ${SENTRY_SAMPLE_RATE}"
fi

# Determine image tag format based on registry
if [ "$ARTIFACT_REGISTRY_REPO" = "gcr.io" ]; then
    IMAGE_TAG="gcr.io/${PROJECT_ID}/${SERVICE_NAME}"
else
    IMAGE_TAG="${REGION}-docker.pkg.dev/${PROJECT_ID}/${ARTIFACT_REGISTRY_REPO}/${SERVICE_NAME}"
fi
SUBSTITUTIONS="${SUBSTITUTIONS},_IMAGE_TAG=${IMAGE_TAG}"

# Submit build
echo ""
echo -e "${GREEN}Submitting build to Cloud Build...${NC}"
gcloud builds submit --config=cloudbuild.yaml \
    --substitutions="${SUBSTITUTIONS}"

echo ""
echo -e "${GREEN}Deployment complete!${NC}"
echo ""
echo "Service URL:"
gcloud run services describe $SERVICE_NAME --region=$REGION --format="value(status.url)"

