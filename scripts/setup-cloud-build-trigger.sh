#!/bin/bash
set -e

# Setup Cloud Build Trigger for automatic deployments on git push to main
# Usage: ./scripts/setup-cloud-build-trigger.sh

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

echo -e "${GREEN}Setting up Cloud Build Trigger for Cal.com${NC}"
echo "Project: $PROJECT_ID"
echo ""

# Repository information
REPO_OWNER="tindevelopers"
REPO_NAME="cal.com"
BRANCH_PATTERN="^main$"
TRIGGER_NAME="calcom-deploy-main"

# Check if trigger already exists
EXISTING_TRIGGER=$(gcloud builds triggers list --filter="name:$TRIGGER_NAME" --format="value(name)" 2>/dev/null || true)
if [ -n "$EXISTING_TRIGGER" ]; then
    echo -e "${YELLOW}Trigger '$TRIGGER_NAME' already exists.${NC}"
    read -p "Do you want to update it? (y/N): " UPDATE_TRIGGER
    if [[ ! "$UPDATE_TRIGGER" =~ ^[Yy]$ ]]; then
        echo "Exiting. Use 'gcloud builds triggers delete $TRIGGER_NAME' to remove the existing trigger first."
        exit 0
    fi
    echo -e "${YELLOW}Deleting existing trigger...${NC}"
    gcloud builds triggers delete "$TRIGGER_NAME" --quiet 2>/dev/null || true
fi

# Check for GitHub connection
echo -e "${YELLOW}Checking for GitHub connection...${NC}"
CONNECTION_NAME="github-connection"
CONNECTION_REGION="us-central1"
EXISTING_CONNECTION=$(gcloud builds connections list --region=$CONNECTION_REGION --format="value(name)" 2>/dev/null | grep -i github || true)

if [ -z "$EXISTING_CONNECTION" ]; then
    echo -e "${YELLOW}No GitHub connection found.${NC}"
    echo ""
    echo "To create a GitHub connection, you have two options:"
    echo ""
    echo "Option 1: Use GitHub App (Recommended)"
    echo "  1. Install the Google Cloud Build GitHub App:"
    echo "     https://github.com/apps/google-cloud-build"
    echo "  2. Grant access to: ${REPO_OWNER}/${REPO_NAME}"
    echo "  3. Note the App Installation ID from the app settings"
    echo ""
    echo "Option 2: Use OAuth (Interactive)"
    echo "  This will open a browser for authorization"
    echo ""
    read -p "Do you have a GitHub App Installation ID? (y/N): " HAS_APP_ID
    
    if [[ "$HAS_APP_ID" =~ ^[Yy]$ ]]; then
        read -p "Enter GitHub App Installation ID: " APP_INSTALLATION_ID
        if [ -z "$APP_INSTALLATION_ID" ]; then
            echo -e "${RED}App Installation ID is required.${NC}"
            exit 1
        fi
        
        echo -e "${GREEN}Creating GitHub connection with App Installation ID...${NC}"
        gcloud builds connections create github \
            --region=global \
            --connection-name="$CONNECTION_NAME" \
            --app-installation-id="$APP_INSTALLATION_ID" || {
            echo -e "${RED}Failed to create GitHub connection.${NC}"
            echo "Make sure the GitHub App is installed and has access to the repository."
            exit 1
        }
    else
        echo -e "${YELLOW}Creating GitHub connection with OAuth...${NC}"
        echo "This will open a browser for GitHub OAuth authorization."
        read -p "Press Enter to continue or Ctrl+C to cancel..."
        
        # Create GitHub connection with OAuth
        gcloud builds connections create github \
            --region=global \
            --connection-name="$CONNECTION_NAME" || {
            echo -e "${RED}Failed to create GitHub connection.${NC}"
            echo ""
            echo "You may need to:"
            echo "1. Install GitHub App: https://github.com/apps/google-cloud-build"
            echo "2. Or set up OAuth manually"
            echo "See: https://cloud.google.com/build/docs/automate-builds/github/connect-repo-github"
            exit 1
        }
    fi
    
    echo -e "${GREEN}GitHub connection created successfully!${NC}"
    echo ""
    # Wait a moment for the connection to be ready
    echo "Waiting for connection to be ready..."
    sleep 5
    
    # Verify connection
    CONNECTION_STATUS=$(gcloud builds connections describe "$CONNECTION_NAME" --region=$CONNECTION_REGION --format="value(state)" 2>/dev/null || echo "UNKNOWN")
    INSTALLATION_STATE=$(gcloud builds connections describe "$CONNECTION_NAME" --region=$CONNECTION_REGION --format="value(installationState.state)" 2>/dev/null || echo "UNKNOWN")
    
    if [ "$INSTALLATION_STATE" = "PENDING_USER_OAUTH" ]; then
        echo ""
        echo -e "${YELLOW}⚠️  OAuth authorization required!${NC}"
        echo ""
        echo "Please complete the OAuth flow:"
        OAUTH_URL=$(gcloud builds connections describe "$CONNECTION_NAME" --region=$CONNECTION_REGION --format="value(installationState.actionUri)" 2>/dev/null || echo "")
        if [ -n "$OAUTH_URL" ]; then
            echo "  $OAUTH_URL"
        else
            echo "  Visit: https://console.cloud.google.com/cloud-build/connections/github/create?project=$PROJECT_ID"
        fi
        echo ""
        echo "After authorization, the connection will be ready for use."
        echo "You can check status with:"
        echo "  gcloud builds connections describe $CONNECTION_NAME --region=$CONNECTION_REGION"
        echo ""
        read -p "Press Enter after completing OAuth authorization, or Ctrl+C to exit..."
        
        # Re-check status
        INSTALLATION_STATE=$(gcloud builds connections describe "$CONNECTION_NAME" --region=$CONNECTION_REGION --format="value(installationState.state)" 2>/dev/null || echo "UNKNOWN")
        if [ "$INSTALLATION_STATE" != "COMPLETE" ]; then
            echo -e "${YELLOW}Connection is not yet ready. State: $INSTALLATION_STATE${NC}"
            echo "Please complete the OAuth flow and run this script again."
            exit 1
        fi
    fi
    
    if [ "$CONNECTION_STATUS" != "READY" ] && [ "$INSTALLATION_STATE" != "COMPLETE" ]; then
        echo -e "${YELLOW}Warning: Connection status is $CONNECTION_STATUS, installation state: $INSTALLATION_STATE${NC}"
        echo "The connection may need a few minutes to become ready."
    fi
else
    CONNECTION_NAME=$(echo "$EXISTING_CONNECTION" | head -1)
    echo -e "${GREEN}Using existing GitHub connection: $CONNECTION_NAME${NC}"
    
    # Check if it needs OAuth
    INSTALLATION_STATE=$(gcloud builds connections describe "$CONNECTION_NAME" --region=$CONNECTION_REGION --format="value(installationState.state)" 2>/dev/null || echo "UNKNOWN")
    if [ "$INSTALLATION_STATE" = "PENDING_USER_OAUTH" ]; then
        echo -e "${YELLOW}⚠️  This connection requires OAuth authorization!${NC}"
        OAUTH_URL=$(gcloud builds connections describe "$CONNECTION_NAME" --region=$CONNECTION_REGION --format="value(installationState.actionUri)" 2>/dev/null || echo "")
        if [ -n "$OAUTH_URL" ]; then
            echo "Complete OAuth at: $OAUTH_URL"
        fi
        read -p "Press Enter after completing OAuth, or Ctrl+C to exit..."
    fi
fi

# Get current service configuration for substitutions
echo ""
echo -e "${YELLOW}Gathering configuration from existing Cloud Run service...${NC}"
REGION="europe-west1"
SERVICE_NAME="calcom"

# Get service URL
SERVICE_URL=$(gcloud run services describe $SERVICE_NAME --region=$REGION --format="value(status.url)" 2>/dev/null || echo "")
if [ -z "$SERVICE_URL" ]; then
    echo -e "${YELLOW}Could not get service URL. Using default.${NC}"
    SERVICE_URL="https://calcom-${REGION}-${PROJECT_ID}.a.run.app"
fi

NEXTAUTH_URL="${SERVICE_URL}/api/auth"

# Get environment variables from current service
ENV_VARS=$(gcloud run services describe $SERVICE_NAME --region=$REGION --format="get(spec.template.spec.containers[0].env)" 2>/dev/null || echo "")

# Extract DATABASE_URL, NEXTAUTH_SECRET, CALENDSO_ENCRYPTION_KEY if available
DATABASE_URL=$(echo "$ENV_VARS" | grep -oP "DATABASE_URL.*?value': '\K[^']*" || echo "")
NEXTAUTH_SECRET=$(echo "$ENV_VARS" | grep -oP "NEXTAUTH_SECRET.*?value': '\K[^']*" || echo "")
CALENDSO_ENCRYPTION_KEY=$(echo "$ENV_VARS" | grep -oP "CALENDSO_ENCRYPTION_KEY.*?value': '\K[^']*" || echo "")

# Determine image tag
IMAGE_TAG="gcr.io/${PROJECT_ID}/${SERVICE_NAME}"

# Build substitutions
SUBSTITUTIONS="_NEXT_PUBLIC_WEBAPP_URL=${SERVICE_URL}"
SUBSTITUTIONS="${SUBSTITUTIONS},_NEXTAUTH_URL=${NEXTAUTH_URL}"
SUBSTITUTIONS="${SUBSTITUTIONS},_REGION=${REGION}"
SUBSTITUTIONS="${SUBSTITUTIONS},_SERVICE_NAME=${SERVICE_NAME}"
SUBSTITUTIONS="${SUBSTITUTIONS},_ARTIFACT_REGISTRY_REPO=gcr.io"
SUBSTITUTIONS="${SUBSTITUTIONS},_IMAGE_TAG=${IMAGE_TAG}"
SUBSTITUTIONS="${SUBSTITUTIONS},_MEMORY=4Gi"
SUBSTITUTIONS="${SUBSTITUTIONS},_CPU=2"
SUBSTITUTIONS="${SUBSTITUTIONS},_USE_SECRETS=false"

# Add secrets if available
if [ -n "$DATABASE_URL" ]; then
    SUBSTITUTIONS="${SUBSTITUTIONS},_DATABASE_URL=${DATABASE_URL}"
    echo -e "${GREEN}✓ Found DATABASE_URL${NC}"
else
    echo -e "${YELLOW}⚠ DATABASE_URL not found. You'll need to set it manually.${NC}"
fi

if [ -n "$NEXTAUTH_SECRET" ]; then
    SUBSTITUTIONS="${SUBSTITUTIONS},_NEXTAUTH_SECRET=${NEXTAUTH_SECRET}"
    echo -e "${GREEN}✓ Found NEXTAUTH_SECRET${NC}"
else
    echo -e "${YELLOW}⚠ NEXTAUTH_SECRET not found. You'll need to set it manually.${NC}"
fi

if [ -n "$CALENDSO_ENCRYPTION_KEY" ]; then
    SUBSTITUTIONS="${SUBSTITUTIONS},_CALENDSO_ENCRYPTION_KEY=${CALENDSO_ENCRYPTION_KEY}"
    echo -e "${GREEN}✓ Found CALENDSO_ENCRYPTION_KEY${NC}"
else
    echo -e "${YELLOW}⚠ CALENDSO_ENCRYPTION_KEY not found. You'll need to set it manually.${NC}"
fi

echo ""
echo -e "${YELLOW}Configuration:${NC}"
echo "  Repository: ${REPO_OWNER}/${REPO_NAME}"
echo "  Branch: ${BRANCH_PATTERN}"
echo "  Service URL: ${SERVICE_URL}"
echo "  Image Tag: ${IMAGE_TAG}"
echo ""

read -p "Press Enter to create the trigger or Ctrl+C to cancel..."

# Create the trigger
echo ""
echo -e "${GREEN}Creating Cloud Build trigger...${NC}"

gcloud builds triggers create github \
    --name="$TRIGGER_NAME" \
    --repo-name="$REPO_NAME" \
    --repo-owner="$REPO_OWNER" \
    --branch-pattern="$BRANCH_PATTERN" \
    --build-config="cloudbuild.yaml" \
    --region="$CONNECTION_REGION" \
    --connection="$CONNECTION_NAME" \
    --substitutions="$SUBSTITUTIONS" \
    --description="Automatically deploy Cal.com to Cloud Run on push to main branch" || {
    echo -e "${RED}Failed to create trigger.${NC}"
    echo ""
    echo "Common issues:"
    echo "1. GitHub connection not properly authorized"
    echo "2. Repository not accessible"
    echo "3. Missing required permissions"
    exit 1
}

echo ""
echo -e "${GREEN}✓ Cloud Build trigger created successfully!${NC}"
echo ""
echo "Trigger details:"
gcloud builds triggers describe "$TRIGGER_NAME" --format="table(name,github.owner,github.name,github.branch,filename)"
echo ""
echo -e "${GREEN}Next steps:${NC}"
echo "1. Push a commit to the main branch to test the trigger"
echo "2. Monitor builds: gcloud builds list --limit=5"
echo "3. View trigger: gcloud builds triggers describe $TRIGGER_NAME"
echo ""
echo "To manually trigger a build:"
echo "  gcloud builds triggers run $TRIGGER_NAME --branch=main"

