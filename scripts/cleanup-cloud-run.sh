#!/bin/bash
set -e

# Cleanup script for Google Cloud Run and Cloud Build
# This deletes all Cloud Run services and failed Cloud Build builds

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
if [ -z "$PROJECT_ID" ]; then
    echo -e "${RED}Error: No GCP project configured.${NC}"
    exit 1
fi

echo -e "${YELLOW}Cleaning up Cloud Run and Cloud Build resources${NC}"
echo "Project: $PROJECT_ID"
echo ""

# Delete Cloud Run services
echo -e "${YELLOW}Deleting Cloud Run services...${NC}"
SERVICES=$(gcloud run services list --project=$PROJECT_ID --format="value(metadata.name,metadata.labels.'cloud.googleapis.com/location')" 2>/dev/null || echo "")

if [ -z "$SERVICES" ]; then
    echo "  No Cloud Run services found."
else
    echo "$SERVICES" | while IFS=$'\t' read -r name location; do
        if [ -n "$name" ] && [ -n "$location" ]; then
            echo "  Deleting service: $name in $location"
            gcloud run services delete "$name" --region="$location" --project=$PROJECT_ID --quiet 2>&1 || echo "    Failed to delete $name"
        fi
    done
fi

# Note: Cloud Build builds cannot be deleted - they are immutable historical records
# They won't interfere with new deployments, but they remain in the build history
echo ""
echo -e "${YELLOW}Cloud Build builds (historical records - cannot be deleted):${NC}"
FAILED_COUNT=$(gcloud builds list --project=$PROJECT_ID --filter="status=FAILURE OR status=CANCELLED OR status=INTERNAL_ERROR" --format="value(id)" 2>/dev/null | wc -l | tr -d ' ')
if [ "$FAILED_COUNT" -gt 0 ]; then
    echo "  Found $FAILED_COUNT failed/cancelled builds (these are historical records)"
    echo "  Note: Builds cannot be deleted, but they won't affect new deployments"
else
    echo "  No failed builds found."
fi

# List remaining builds
echo ""
echo -e "${YELLOW}Remaining Cloud Build builds:${NC}"
gcloud builds list --project=$PROJECT_ID --limit=10 --format="table(id,status,createTime)" 2>&1 | head -12

# List remaining services
echo ""
echo -e "${YELLOW}Remaining Cloud Run services:${NC}"
gcloud run services list --project=$PROJECT_ID --format="table(metadata.name,status.url)" 2>&1 || echo "  None"

echo ""
echo -e "${GREEN}Cleanup complete!${NC}"

