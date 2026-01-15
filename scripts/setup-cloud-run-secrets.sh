#!/bin/bash
set -e

# Google Cloud Run Secrets Setup Script for Cal.com
# Usage: ./scripts/setup-cloud-run-secrets.sh

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

echo -e "${GREEN}Setting up Cal.com secrets for Google Cloud Run${NC}"
echo "Project: $PROJECT_ID"
echo ""

# Check if Secret Manager API is enabled
if ! gcloud services list --enabled --project=$PROJECT_ID --filter="name:secretmanager.googleapis.com" --format="value(name)" 2>/dev/null | grep -q secretmanager; then
    echo -e "${YELLOW}Secret Manager API is not enabled. Enabling now...${NC}"
    gcloud services enable secretmanager.googleapis.com --project=$PROJECT_ID
    echo -e "${GREEN}✓ Secret Manager API enabled${NC}"
    echo ""
fi

# Secret names
DATABASE_URL_SECRET_NAME="calcom-database-url"
NEXTAUTH_SECRET_NAME="calcom-nextauth-secret"
CALENDSO_ENCRYPTION_KEY_NAME="calcom-encryption-key"

# Check if secrets already exist
EXISTING_SECRETS=()
if gcloud secrets describe $DATABASE_URL_SECRET_NAME --project=$PROJECT_ID &>/dev/null; then
    EXISTING_SECRETS+=($DATABASE_URL_SECRET_NAME)
fi
if gcloud secrets describe $NEXTAUTH_SECRET_NAME --project=$PROJECT_ID &>/dev/null; then
    EXISTING_SECRETS+=($NEXTAUTH_SECRET_NAME)
fi
if gcloud secrets describe $CALENDSO_ENCRYPTION_KEY_NAME --project=$PROJECT_ID &>/dev/null; then
    EXISTING_SECRETS+=($CALENDSO_ENCRYPTION_KEY_NAME)
fi

if [ ${#EXISTING_SECRETS[@]} -gt 0 ]; then
    echo -e "${YELLOW}Warning: The following secrets already exist:${NC}"
    for secret in "${EXISTING_SECRETS[@]}"; do
        echo "  - $secret"
    done
    echo ""
    read -p "Do you want to update existing secrets? (y/N): " UPDATE_EXISTING
    if [[ ! "$UPDATE_EXISTING" =~ ^[Yy]$ ]]; then
        echo "Exiting. No secrets were modified."
        exit 0
    fi
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

# Generate secrets if not updating existing ones
if [[ ! " ${EXISTING_SECRETS[@]} " =~ " ${NEXTAUTH_SECRET_NAME} " ]] || [[ "$UPDATE_EXISTING" =~ ^[Yy]$ ]]; then
    echo ""
    echo -e "${GREEN}Generating NEXTAUTH_SECRET...${NC}"
    NEXTAUTH_SECRET=$(openssl rand -base64 32)
    echo "  ✓ Generated random secret"
else
    echo ""
    echo -e "${YELLOW}NEXTAUTH_SECRET already exists. Skipping generation.${NC}"
    read -p "Do you want to generate a new NEXTAUTH_SECRET? (y/N): " REGEN_NEXTAUTH
    if [[ "$REGEN_NEXTAUTH" =~ ^[Yy]$ ]]; then
        NEXTAUTH_SECRET=$(openssl rand -base64 32)
        echo "  ✓ Generated new random secret"
    else
        NEXTAUTH_SECRET=""
    fi
fi

if [[ ! " ${EXISTING_SECRETS[@]} " =~ " ${CALENDSO_ENCRYPTION_KEY_NAME} " ]] || [[ "$UPDATE_EXISTING" =~ ^[Yy]$ ]]; then
    echo ""
    echo -e "${GREEN}Generating CALENDSO_ENCRYPTION_KEY...${NC}"
    CALENDSO_ENCRYPTION_KEY=$(openssl rand -base64 32)
    echo "  ✓ Generated random key"
else
    echo ""
    echo -e "${YELLOW}CALENDSO_ENCRYPTION_KEY already exists. Skipping generation.${NC}"
    read -p "Do you want to generate a new CALENDSO_ENCRYPTION_KEY? (y/N): " REGEN_ENCRYPTION
    if [[ "$REGEN_ENCRYPTION" =~ ^[Yy]$ ]]; then
        CALENDSO_ENCRYPTION_KEY=$(openssl rand -base64 32)
        echo "  ✓ Generated new random key"
    else
        CALENDSO_ENCRYPTION_KEY=""
    fi
fi

echo ""
echo -e "${YELLOW}Summary:${NC}"
echo "  DATABASE_URL: ${DATABASE_URL:0:50}..."
if [ -n "$NEXTAUTH_SECRET" ]; then
    echo "  NEXTAUTH_SECRET: ${NEXTAUTH_SECRET:0:20}... (new)"
else
    echo "  NEXTAUTH_SECRET: (keeping existing)"
fi
if [ -n "$CALENDSO_ENCRYPTION_KEY" ]; then
    echo "  CALENDSO_ENCRYPTION_KEY: ${CALENDSO_ENCRYPTION_KEY:0:20}... (new)"
else
    echo "  CALENDSO_ENCRYPTION_KEY: (keeping existing)"
fi
echo ""
read -p "Press Enter to create/update secrets or Ctrl+C to cancel..."

# Create or update secrets
echo ""
echo -e "${GREEN}Creating/updating secrets...${NC}"

# DATABASE_URL
if [[ " ${EXISTING_SECRETS[@]} " =~ " ${DATABASE_URL_SECRET_NAME} " ]]; then
    echo -n "$DATABASE_URL" | gcloud secrets versions add $DATABASE_URL_SECRET_NAME \
        --project=$PROJECT_ID \
        --data-file=-
    echo "  ✓ Updated $DATABASE_URL_SECRET_NAME"
else
    echo -n "$DATABASE_URL" | gcloud secrets create $DATABASE_URL_SECRET_NAME \
        --project=$PROJECT_ID \
        --data-file=-
    echo "  ✓ Created $DATABASE_URL_SECRET_NAME"
fi

# NEXTAUTH_SECRET
if [ -n "$NEXTAUTH_SECRET" ]; then
    if [[ " ${EXISTING_SECRETS[@]} " =~ " ${NEXTAUTH_SECRET_NAME} " ]]; then
        echo -n "$NEXTAUTH_SECRET" | gcloud secrets versions add $NEXTAUTH_SECRET_NAME \
            --project=$PROJECT_ID \
            --data-file=-
        echo "  ✓ Updated $NEXTAUTH_SECRET_NAME"
    else
        echo -n "$NEXTAUTH_SECRET" | gcloud secrets create $NEXTAUTH_SECRET_NAME \
            --project=$PROJECT_ID \
            --data-file=-
        echo "  ✓ Created $NEXTAUTH_SECRET_NAME"
    fi
fi

# CALENDSO_ENCRYPTION_KEY
if [ -n "$CALENDSO_ENCRYPTION_KEY" ]; then
    if [[ " ${EXISTING_SECRETS[@]} " =~ " ${CALENDSO_ENCRYPTION_KEY_NAME} " ]]; then
        echo -n "$CALENDSO_ENCRYPTION_KEY" | gcloud secrets versions add $CALENDSO_ENCRYPTION_KEY_NAME \
            --project=$PROJECT_ID \
            --data-file=-
        echo "  ✓ Updated $CALENDSO_ENCRYPTION_KEY_NAME"
    else
        echo -n "$CALENDSO_ENCRYPTION_KEY" | gcloud secrets create $CALENDSO_ENCRYPTION_KEY_NAME \
            --project=$PROJECT_ID \
            --data-file=-
        echo "  ✓ Created $CALENDSO_ENCRYPTION_KEY_NAME"
    fi
fi

# Grant Cloud Run service account access to secrets
echo ""
echo -e "${GREEN}Granting Cloud Run service account access to secrets...${NC}"
PROJECT_NUMBER=$(gcloud projects describe $PROJECT_ID --format="value(projectNumber)")
SERVICE_ACCOUNT="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"

for secret in $DATABASE_URL_SECRET_NAME $NEXTAUTH_SECRET_NAME $CALENDSO_ENCRYPTION_KEY_NAME; do
    # Check if binding already exists
    if gcloud secrets get-iam-policy $secret --project=$PROJECT_ID 2>/dev/null | grep -q "$SERVICE_ACCOUNT"; then
        echo "  ✓ $secret: Service account already has access"
    else
        gcloud secrets add-iam-policy-binding $secret \
            --project=$PROJECT_ID \
            --member="serviceAccount:${SERVICE_ACCOUNT}" \
            --role="roles/secretmanager.secretAccessor" \
            --quiet
        echo "  ✓ $secret: Granted access to service account"
    fi
done

echo ""
echo -e "${GREEN}✓ Secrets setup complete!${NC}"
echo ""
echo "You can now deploy Cal.com using:"
echo "  ./scripts/deploy-cloud-run.sh"
echo ""
echo "Or verify secrets with:"
echo "  gcloud secrets list --project=$PROJECT_ID"

