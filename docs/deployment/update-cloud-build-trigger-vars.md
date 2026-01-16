# Updating Cloud Build Trigger Variables

This guide explains how to add required environment variables to the Cloud Build trigger.

## Quick Update via Console

1. **Open the trigger in Google Cloud Console:**
   ```
   https://console.cloud.google.com/cloud-build/triggers/edit/799a3b52-0772-41e1-9799-1649a0b7020a?project=cal-com-tin
   ```

2. **Scroll to "Substitution variables" section**

3. **Add/Update the following variables:**

   | Variable | Value Source | Description |
   |----------|-------------|-------------|
   | `_DATABASE_URL` | Secret: `calcom-database-url` | PostgreSQL connection string |
   | `_NEXTAUTH_SECRET` | Secret: `calcom-nextauth-secret` | NextAuth.js secret |
   | `_CALENDSO_ENCRYPTION_KEY` | Secret: `calcom-encryption-key` | Encryption key |
   | `_NEXT_PUBLIC_WEBAPP_URL` | `https://calcom-europe-west1-cal-com-tin.a.run.app` | Public web app URL |
   | `_NEXTAUTH_URL` | `https://calcom-europe-west1-cal-com-tin.a.run.app/api/auth` | NextAuth URL |

4. **Click "Save"**

## Automated Script

Run the script to retrieve values and get instructions:

```bash
./scripts/update-cloud-build-trigger-vars.sh
```

This script will:
- Retrieve secret values from Secret Manager
- Get the service URL
- Display the exact values to add manually

## Getting Secret Values

To retrieve secret values manually:

```bash
# Database URL
gcloud secrets versions access latest --secret="calcom-database-url" --project=cal-com-tin

# NextAuth Secret
gcloud secrets versions access latest --secret="calcom-nextauth-secret" --project=cal-com-tin

# Encryption Key
gcloud secrets versions access latest --secret="calcom-encryption-key" --project=cal-com-tin
```

## Verification

After updating, verify the substitutions are set:

```bash
gcloud builds triggers describe cal-com-push-to-main \
  --region=global \
  --format="get(substitutions)" \
  --project=cal-com-tin
```

## Troubleshooting

If the trigger update fails via CLI (due to autodetect configuration), use the Console method above. The trigger uses `autodetect: true` which requires manual configuration through the web UI.

