#!/bin/bash
set -e

# Script to delete a Cloud Build repository connection
# Usage: ./scripts/delete-cloud-build-repo.sh <CONNECTION_NAME> <REGION> <REPO_NAME>
#
# To find the connection name:
# 1. Go to https://console.cloud.google.com/cloud-build/repositories?project=cal-com-tin
# 2. Click on the repository "tindevelopers/cal.com-version-1"
# 3. Check the connection name in the details or use the browser developer tools

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if gcloud is installed
if ! command -v gcloud &> /dev/null; then
    echo -e "${RED}Error: gcloud CLI is not installed.${NC}"
    exit 1
fi

# Get project ID
PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
if [ -z "$PROJECT_ID" ]; then
    echo -e "${RED}Error: No GCP project configured.${NC}"
    exit 1
fi

CONNECTION_NAME=${1}
REGION=${2:-global}
REPO_NAME=${3:-"tindevelopers/cal.com-version-1"}

if [ -z "$CONNECTION_NAME" ]; then
    echo -e "${YELLOW}Usage: $0 <CONNECTION_NAME> [REGION] [REPO_NAME]${NC}"
    echo ""
    echo "To find the connection name:"
    echo "1. Go to: https://console.cloud.google.com/cloud-build/repositories?project=$PROJECT_ID"
    echo "2. Look at the repository connection details"
    echo "3. The connection name is shown in the 'Connection' column"
    echo ""
    echo "Example:"
    echo "  $0 my-github-connection global tindevelopers/cal.com-version-1"
    exit 1
fi

echo -e "${GREEN}Deleting Cloud Build repository connection${NC}"
echo "Project: $PROJECT_ID"
echo "Connection: $CONNECTION_NAME"
echo "Region: $REGION"
echo "Repository: $REPO_NAME"
echo ""

# Delete the repository
echo -e "${YELLOW}Deleting repository: $REPO_NAME${NC}"
gcloud builds repositories delete "$REPO_NAME" \
    --connection="$CONNECTION_NAME" \
    --region="$REGION" \
    --quiet

echo -e "${GREEN}Repository deleted successfully!${NC}"

# Note about build history
echo ""
echo -e "${YELLOW}Note:${NC} Build history cannot be deleted via gcloud CLI."
echo "Cloud Build automatically manages build history retention."
echo "The build history will be automatically purged over time."

