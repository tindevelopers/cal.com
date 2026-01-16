#!/bin/bash
set -e

# Update Cloud Build Trigger with required environment variables
# This script retrieves values from Cloud Secrets Manager and Cloud Run service
# Usage: ./scripts/update-cloud-build-trigger-vars.sh

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Get project ID
PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
if [ -z "$PROJECT_ID" ]; then
    echo -e "${RED}Error: No GCP project configured.${NC}"
    echo "Run: gcloud config set project YOUR_PROJECT_ID"
    exit 1
fi

echo -e "${GREEN}Updating Cloud Build Trigger with environment variables${NC}"
echo "Project: $PROJECT_ID"
echo ""

TRIGGER_NAME="cal-com-push-to-main"
REGION="europe-west1"
SERVICE_NAME="calcom"

# Get service URL
SERVICE_URL=$(gcloud run services describe $SERVICE_NAME --region=$REGION --format="value(status.url)" --project=$PROJECT_ID 2>/dev/null || echo "")
if [ -z "$SERVICE_URL" ]; then
    echo -e "${YELLOW}Could not get service URL. Using default.${NC}"
    SERVICE_URL="https://${SERVICE_NAME}-${REGION}-${PROJECT_ID}.a.run.app"
fi

NEXTAUTH_URL="${SERVICE_URL}/api/auth"

echo -e "${GREEN}Service URL: ${SERVICE_URL}${NC}"
echo -e "${GREEN}NEXTAUTH_URL: ${NEXTAUTH_URL}${NC}"
echo ""

# Retrieve secrets from Secret Manager
echo -e "${YELLOW}Retrieving secrets from Secret Manager...${NC}"

DATABASE_URL=$(gcloud secrets versions access latest --secret="calcom-database-url" --project=$PROJECT_ID 2>/dev/null || echo "")
if [ -z "$DATABASE_URL" ]; then
    echo -e "${RED}Error: Could not retrieve DATABASE_URL from Secret Manager${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Retrieved DATABASE_URL${NC}"

NEXTAUTH_SECRET=$(gcloud secrets versions access latest --secret="calcom-nextauth-secret" --project=$PROJECT_ID 2>/dev/null || echo "")
if [ -z "$NEXTAUTH_SECRET" ]; then
    echo -e "${RED}Error: Could not retrieve NEXTAUTH_SECRET from Secret Manager${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Retrieved NEXTAUTH_SECRET${NC}"

CALENDSO_ENCRYPTION_KEY=$(gcloud secrets versions access latest --secret="calcom-encryption-key" --project=$PROJECT_ID 2>/dev/null || echo "")
if [ -z "$CALENDSO_ENCRYPTION_KEY" ]; then
    echo -e "${RED}Error: Could not retrieve CALENDSO_ENCRYPTION_KEY from Secret Manager${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Retrieved CALENDSO_ENCRYPTION_KEY${NC}"

echo ""
echo -e "${YELLOW}Updating Cloud Build trigger: ${TRIGGER_NAME}${NC}"

# Build substitutions string
SUBSTITUTIONS="_DATABASE_URL=${DATABASE_URL}"
SUBSTITUTIONS="${SUBSTITUTIONS},_NEXTAUTH_SECRET=${NEXTAUTH_SECRET}"
SUBSTITUTIONS="${SUBSTITUTIONS},_CALENDSO_ENCRYPTION_KEY=${CALENDSO_ENCRYPTION_KEY}"
SUBSTITUTIONS="${SUBSTITUTIONS},_NEXT_PUBLIC_WEBAPP_URL=${SERVICE_URL}"
SUBSTITUTIONS="${SUBSTITUTIONS},_NEXTAUTH_URL=${NEXTAUTH_URL}"

# Update the trigger - try multiple approaches
echo "Attempting to update trigger..."

# First, try with build-config
if gcloud builds triggers update github "$TRIGGER_NAME" \
    --region=global \
    --repo-name="cal.com" \
    --repo-owner="tindevelopers" \
    --branch-pattern="^main$" \
    --build-config="cloudbuild.yaml" \
    --update-substitutions="$SUBSTITUTIONS" \
    --project=$PROJECT_ID 2>&1; then
    echo -e "${GREEN}✓ Trigger updated successfully${NC}"
else
    echo -e "${YELLOW}First method failed, trying alternative approach...${NC}"
    
    # Alternative: Use gcloud builds triggers patch (if available)
    # Or use REST API
    SUBSTITUTIONS_JSON=$(echo "$SUBSTITUTIONS" | awk -F',' '{for(i=1;i<=NF;i++){split($i,a,"=");printf "\"%s\":\"%s\"",a[1],a[2];if(i<NF)printf ","}}')
    
    # Try using the REST API via gcloud
    gcloud builds triggers update "$TRIGGER_NAME" \
        --region=global \
        --update-substitutions="$SUBSTITUTIONS" \
        --project=$PROJECT_ID 2>&1 || {
        echo -e "${RED}Failed to update trigger via CLI.${NC}"
        echo ""
        echo "Please update manually via Console or use the following substitutions:"
        echo ""
        echo "$SUBSTITUTIONS"
        echo ""
        echo "Console URL:"
        echo "https://console.cloud.google.com/cloud-build/triggers/edit/799a3b52-0772-41e1-9799-1649a0b7020a?project=${PROJECT_ID}"
        echo ""
        echo "Or run this command manually:"
        echo "gcloud builds triggers update github $TRIGGER_NAME --region=global --update-substitutions=\"$SUBSTITUTIONS\""
        exit 1
    }
fi

echo ""
echo -e "${YELLOW}Note: CLI update failed due to trigger configuration.${NC}"
echo ""
echo -e "${GREEN}Please update the trigger manually via the Console:${NC}"
echo ""
echo "1. Go to: https://console.cloud.google.com/cloud-build/triggers/edit/799a3b52-0772-41e1-9799-1649a0b7020a?project=${PROJECT_ID}"
echo ""
echo "2. Scroll to 'Substitution variables' section"
echo ""
echo "3. Add/Update the following variables:"
echo ""
echo "   _DATABASE_URL = [retrieved from Secret Manager - value hidden]"
echo "   _NEXTAUTH_SECRET = [retrieved from Secret Manager - value hidden]"
echo "   _CALENDSO_ENCRYPTION_KEY = [retrieved from Secret Manager - value hidden]"
echo "   _NEXT_PUBLIC_WEBAPP_URL = ${SERVICE_URL}"
echo "   _NEXTAUTH_URL = ${NEXTAUTH_URL}"
echo ""
echo "4. Click 'Save'"
echo ""
echo -e "${YELLOW}Alternative: Use the setup script to recreate the trigger:${NC}"
echo "  ./scripts/setup-cloud-build-trigger.sh"
echo ""
echo "The values have been retrieved and are ready to be added manually."

