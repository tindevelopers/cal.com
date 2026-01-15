#!/bin/bash
set -e

# Google Cloud Run Deployment Script for Cal.com (Non-Interactive)
# Usage: ./scripts/deploy-cloud-run-auto.sh [NEXT_PUBLIC_WEBAPP_URL] [SERVICE_NAME] [REGION]

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

# Get parameters from command line or use defaults
NEXT_PUBLIC_WEBAPP_URL=${1:-"https://cal-com-tin-$(openssl rand -hex 4).run.app"}
NEXT_PUBLIC_API_V2_URL=${2:-""}
SERVICE_NAME=${3:-"calcom"}
REGION=${4:-"europe-west1"}
ARTIFACT_REGISTRY_REPO=${5:-"gcr.io"}
MEMORY=${6:-"2Gi"}
CPU=${7:-"2"}

echo -e "${YELLOW}Configuration:${NC}"
echo "  NEXT_PUBLIC_WEBAPP_URL: $NEXT_PUBLIC_WEBAPP_URL"
echo "  SERVICE_NAME: $SERVICE_NAME"
echo "  REGION: $REGION"
echo "  ARTIFACT_REGISTRY_REPO: $ARTIFACT_REGISTRY_REPO"
echo "  MEMORY: $MEMORY"
echo "  CPU: $CPU"
echo ""

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

USE_SECRETS=false
if [ "$SECRET_MANAGER_ENABLED" = true ]; then
    echo -e "${YELLOW}Secret Manager is enabled.${NC}"
    echo "Using environment variables instead (Secret Manager setup can be done manually)."
    USE_SECRETS=false
fi

# Load from .env file
if [ -f .env ]; then
    echo -e "${GREEN}Loading DATABASE_URL from .env file...${NC}"
    DATABASE_URL=$(grep "^DATABASE_URL=" .env | cut -d '=' -f2- | tr -d '"' | tr -d "'" | head -1)
    if [ -n "$DATABASE_URL" ]; then
        echo "  ✓ DATABASE_URL loaded"
    fi
fi

# Generate secrets
if [ -z "$NEXTAUTH_SECRET" ]; then
    echo -e "${GREEN}Generating NEXTAUTH_SECRET...${NC}"
    NEXTAUTH_SECRET=$(openssl rand -base64 32)
fi

if [ -z "$CALENDSO_ENCRYPTION_KEY" ]; then
    echo -e "${GREEN}Generating CALENDSO_ENCRYPTION_KEY...${NC}"
    CALENDSO_ENCRYPTION_KEY=$(openssl rand -base64 32)
fi

if [ -z "$DATABASE_URL" ]; then
    echo -e "${RED}Error: DATABASE_URL not found in .env file${NC}"
    exit 1
fi

# Store environment variables for later use (not in substitutions to avoid Cloud Build parsing issues)
export DEPLOY_DATABASE_URL="$DATABASE_URL"
export DEPLOY_NEXTAUTH_SECRET="$NEXTAUTH_SECRET"
export DEPLOY_CALENDSO_ENCRYPTION_KEY="$CALENDSO_ENCRYPTION_KEY"
ENV_VARS_EXTRA=""

# Build substitutions - only include variables that are actually used in cloudbuild.yaml
# Note: _MEMORY, _CPU, _PORT, etc. have defaults in the template, so we don't need to provide them
SUBSTITUTIONS="_NEXT_PUBLIC_WEBAPP_URL=${NEXT_PUBLIC_WEBAPP_URL}"
SUBSTITUTIONS="${SUBSTITUTIONS},_NEXTAUTH_URL=${NEXTAUTH_URL}"
SUBSTITUTIONS="${SUBSTITUTIONS},_REGION=${REGION}"
SUBSTITUTIONS="${SUBSTITUTIONS},_SERVICE_NAME=${SERVICE_NAME}"
SUBSTITUTIONS="${SUBSTITUTIONS},_USE_SECRETS=false"
SUBSTITUTIONS="${SUBSTITUTIONS},_NEXT_PUBLIC_API_V2_URL=${NEXT_PUBLIC_API_V2_URL:-}"
SUBSTITUTIONS="${SUBSTITUTIONS},_DATABASE_URL_SECRET_NAME="
SUBSTITUTIONS="${SUBSTITUTIONS},_NEXTAUTH_SECRET_NAME="
SUBSTITUTIONS="${SUBSTITUTIONS},_CALENDSO_ENCRYPTION_KEY_NAME="

# Add memory and CPU only if they differ from defaults
if [ "$MEMORY" != "2Gi" ]; then
    SUBSTITUTIONS="${SUBSTITUTIONS},_MEMORY=${MEMORY}"
fi
if [ "$CPU" != "2" ]; then
    SUBSTITUTIONS="${SUBSTITUTIONS},_CPU=${CPU}"
fi

# Determine image tag format based on registry
if [ "$ARTIFACT_REGISTRY_REPO" = "gcr.io" ]; then
    IMAGE_TAG="gcr.io/${PROJECT_ID}/${SERVICE_NAME}"
else
    IMAGE_TAG="${REGION}-docker.pkg.dev/${PROJECT_ID}/${ARTIFACT_REGISTRY_REPO}/${SERVICE_NAME}"
fi
SUBSTITUTIONS="${SUBSTITUTIONS},_IMAGE_TAG=${IMAGE_TAG}"

echo ""
echo -e "${YELLOW}Secrets summary:${NC}"
echo "  DATABASE_URL: ${DATABASE_URL:0:60}..."
echo "  NEXTAUTH_SECRET: ${NEXTAUTH_SECRET:0:20}..."
echo "  CALENDSO_ENCRYPTION_KEY: ${CALENDSO_ENCRYPTION_KEY:0:20}..."
echo ""

# Submit build
echo -e "${GREEN}Submitting build to Cloud Build...${NC}"
gcloud builds submit --config=cloudbuild.yaml \
    --substitutions="${SUBSTITUTIONS}"

echo ""
echo -e "${GREEN}Build complete! Setting environment variables...${NC}"

# Set environment variables after deployment
gcloud run services update $SERVICE_NAME \
    --region=$REGION \
    --update-env-vars DATABASE_URL="$DEPLOY_DATABASE_URL",DATABASE_DIRECT_URL="$DEPLOY_DATABASE_URL",NEXTAUTH_SECRET="$DEPLOY_NEXTAUTH_SECRET",CALENDSO_ENCRYPTION_KEY="$DEPLOY_CALENDSO_ENCRYPTION_KEY" \
    --quiet

echo ""
echo -e "${GREEN}Deployment complete!${NC}"
echo ""
echo "Service URL:"
gcloud run services describe $SERVICE_NAME --region=$REGION --format="value(status.url)" 2>/dev/null || echo "Service may still be deploying..."

