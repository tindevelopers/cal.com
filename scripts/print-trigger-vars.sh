#!/bin/bash
# Print trigger variables in a format easy to copy-paste into Google Cloud Console

PROJECT_ID="cal-com-tin"

echo "=========================================="
echo "Cloud Build Trigger Variables"
echo "=========================================="
echo ""
echo "Copy these values into the Google Cloud Console:"
echo "https://console.cloud.google.com/cloud-build/triggers?project=${PROJECT_ID}"
echo ""
echo "1. Click 'cal-com-push-to-main' trigger"
echo "2. Click 'EDIT'"
echo "3. Scroll to 'Substitution variables' section"
echo "4. Add each variable below:"
echo ""

# Get secrets
DATABASE_URL=$(gcloud secrets versions access latest --secret="calcom-database-url" --project=$PROJECT_ID 2>/dev/null)
NEXTAUTH_SECRET=$(gcloud secrets versions access latest --secret="calcom-nextauth-secret" --project=$PROJECT_ID 2>/dev/null)
CALENDSO_ENCRYPTION_KEY=$(gcloud secrets versions access latest --secret="calcom-encryption-key" --project=$PROJECT_ID 2>/dev/null)
SERVICE_URL="https://calcom-europe-west1-cal-com-tin.a.run.app"
NEXTAUTH_URL="${SERVICE_URL}/api/auth"

echo "Variable Name: _DATABASE_URL"
echo "Variable Value: ${DATABASE_URL}"
echo ""
echo "Variable Name: _NEXTAUTH_SECRET"
echo "Variable Value: ${NEXTAUTH_SECRET}"
echo ""
echo "Variable Name: _CALENDSO_ENCRYPTION_KEY"
echo "Variable Value: ${CALENDSO_ENCRYPTION_KEY}"
echo ""
echo "Variable Name: _NEXT_PUBLIC_WEBAPP_URL"
echo "Variable Value: ${SERVICE_URL}"
echo ""
echo "Variable Name: _NEXTAUTH_URL"
echo "Variable Value: ${NEXTAUTH_URL}"
echo ""
echo "=========================================="
echo ""
echo "After adding all variables, click 'SAVE'"
echo ""
echo "To verify, run:"
echo "  gcloud builds triggers describe cal-com-push-to-main --region=global --format='get(substitutions)' --project=${PROJECT_ID}"

