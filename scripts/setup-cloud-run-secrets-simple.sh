#!/bin/bash
set -e

# Simple Google Cloud Run Secrets Setup Script for Cal.com
# Usage: ./scripts/setup-cloud-run-secrets-simple.sh

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

# Project ID
PROJECT_ID="cal-com-tin"

echo -e "${GREEN}Setting up Cal.com secrets for Google Cloud Run${NC}"
echo "Project: $PROJECT_ID"
echo ""

# Set the project
echo -e "${YELLOW}Setting gcloud project to $PROJECT_ID...${NC}"
gcloud config set project $PROJECT_ID
echo -e "${GREEN}✓ Project set${NC}"
echo ""

# Check if Secret Manager API is enabled
if ! gcloud services list --enabled --project=$PROJECT_ID --filter="name:secretmanager.googleapis.com" --format="value(name)" 2>/dev/null | grep -q secretmanager; then
    echo -e "${YELLOW}Secret Manager API is not enabled. Enabling now...${NC}"
    gcloud services enable secretmanager.googleapis.com --project=$PROJECT_ID
    echo -e "${GREEN}✓ Secret Manager API enabled${NC}"
    echo ""
fi

# Get DATABASE_URL
echo -e "${YELLOW}Database Configuration:${NC}"
if [ -f .env ]; then
    ENV_DATABASE_URL=$(grep "^DATABASE_URL=" .env | cut -d '=' -f2- | tr -d '"' | tr -d "'" | head -1)
    if [ -n "$ENV_DATABASE_URL" ]; then
        echo "Found DATABASE_URL in .env file"
        read -p "Use DATABASE_URL from .env? (Y/n): " USE_ENV_DB
        if [[ ! "$USE_ENV_DB" =~ ^[Nn]$ ]]; then
            DATABASE_URL="$ENV_DATABASE_URL"
        else
            read -p "Enter DATABASE_URL: " DATABASE_URL
        fi
    else
        read -p "Enter DATABASE_URL: " DATABASE_URL
    fi
else
    read -p "Enter DATABASE_URL: " DATABASE_URL
fi

if [ -z "$DATABASE_URL" ]; then
    echo -e "${RED}Error: DATABASE_URL is required${NC}"
    exit 1
fi

echo ""
echo -e "${YELLOW}Creating secrets...${NC}"

# Create DATABASE_URL secret
echo -n "$DATABASE_URL" | gcloud secrets create calcom-database-url \
  --project=$PROJECT_ID \
  --data-file=-
echo -e "${GREEN}✓ Created calcom-database-url${NC}"

# Create NEXTAUTH_SECRET secret (generates random value)
openssl rand -base64 32 | gcloud secrets create calcom-nextauth-secret \
  --project=$PROJECT_ID \
  --data-file=-
echo -e "${GREEN}✓ Created calcom-nextauth-secret${NC}"

# Create CALENDSO_ENCRYPTION_KEY secret (generates random value)
openssl rand -base64 32 | gcloud secrets create calcom-encryption-key \
  --project=$PROJECT_ID \
  --data-file=-
echo -e "${GREEN}✓ Created calcom-encryption-key${NC}"

# Grant Cloud Run service account access to secrets
echo ""
echo -e "${YELLOW}Granting Cloud Run service account access to secrets...${NC}"
PROJECT_NUMBER=$(gcloud projects describe $PROJECT_ID --format="value(projectNumber)")
SERVICE_ACCOUNT="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"

for secret in calcom-database-url calcom-nextauth-secret calcom-encryption-key; do
  gcloud secrets add-iam-policy-binding $secret \
    --project=$PROJECT_ID \
    --member="serviceAccount:${SERVICE_ACCOUNT}" \
    --role="roles/secretmanager.secretAccessor"
  echo -e "${GREEN}✓ Granted access to $secret${NC}"
done

echo ""
echo -e "${GREEN}✓ Secrets setup complete!${NC}"
echo ""
echo "You can now deploy Cal.com using:"
echo "  ./scripts/deploy-cloud-run.sh"

