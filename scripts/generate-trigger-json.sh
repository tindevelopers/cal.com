#!/bin/bash
# Generate JSON payload for updating Cloud Build trigger via REST API

PROJECT_ID="cal-com-tin"
TRIGGER_ID="799a3b52-0772-41e1-9799-1649a0b7020a"

# Get secrets
DATABASE_URL=$(gcloud secrets versions access latest --secret="calcom-database-url" --project=$PROJECT_ID)
NEXTAUTH_SECRET=$(gcloud secrets versions access latest --secret="calcom-nextauth-secret" --project=$PROJECT_ID)
CALENDSO_ENCRYPTION_KEY=$(gcloud secrets versions access latest --secret="calcom-encryption-key" --project=$PROJECT_ID)
SERVICE_URL="https://calcom-europe-west1-cal-com-tin.a.run.app"
NEXTAUTH_URL="${SERVICE_URL}/api/auth"

# Get access token
ACCESS_TOKEN=$(gcloud auth print-access-token)

# Generate JSON payload
cat << EOF
{
  "substitutions": {
    "_DATABASE_URL": "${DATABASE_URL}",
    "_NEXTAUTH_SECRET": "${NEXTAUTH_SECRET}",
    "_CALENDSO_ENCRYPTION_KEY": "${CALENDSO_ENCRYPTION_KEY}",
    "_NEXT_PUBLIC_WEBAPP_URL": "${SERVICE_URL}",
    "_NEXTAUTH_URL": "${NEXTAUTH_URL}"
  }
}

To update via curl, run:
curl -X PATCH \\
  "https://cloudbuild.googleapis.com/v1/projects/${PROJECT_ID}/locations/global/triggers/${TRIGGER_ID}?updateMask=substitutions" \\
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \\
  -H "Content-Type: application/json" \\
  -d '{
    "substitutions": {
      "_DATABASE_URL": "${DATABASE_URL}",
      "_NEXTAUTH_SECRET": "${NEXTAUTH_SECRET}",
      "_CALENDSO_ENCRYPTION_KEY": "${CALENDSO_ENCRYPTION_KEY}",
      "_NEXT_PUBLIC_WEBAPP_URL": "${SERVICE_URL}",
      "_NEXTAUTH_URL": "${NEXTAUTH_URL}"
    }
  }'
EOF

