#!/usr/bin/env python3
"""Update Cloud Build trigger substitutions using the REST API."""
import json
import subprocess
import sys

PROJECT_ID = "cal-com-tin"
TRIGGER_ID = "799a3b52-0772-41e1-9799-1649a0b7020a"
REGION = "global"

def get_secret(secret_name):
    """Get secret value from Secret Manager."""
    result = subprocess.run(
        ["gcloud", "secrets", "versions", "access", "latest", 
         f"--secret={secret_name}", f"--project={PROJECT_ID}"],
        capture_output=True,
        text=True
    )
    if result.returncode != 0:
        print(f"Error retrieving {secret_name}: {result.stderr}", file=sys.stderr)
        sys.exit(1)
    return result.stdout.strip()

def get_access_token():
    """Get access token."""
    result = subprocess.run(
        ["gcloud", "auth", "print-access-token"],
        capture_output=True,
        text=True
    )
    if result.returncode != 0:
        print(f"Error getting access token: {result.stderr}", file=sys.stderr)
        sys.exit(1)
    return result.stdout.strip()

def get_trigger():
    """Get current trigger configuration."""
    result = subprocess.run(
        ["gcloud", "builds", "triggers", "describe", "cal-com-push-to-main",
         f"--region={REGION}", f"--project={PROJECT_ID}", "--format=json"],
        capture_output=True,
        text=True
    )
    if result.returncode != 0:
        print(f"Error getting trigger: {result.stderr}", file=sys.stderr)
        sys.exit(1)
    return json.loads(result.stdout)

def update_trigger(trigger, substitutions):
    """Update trigger with new substitutions."""
    import urllib.request
    import urllib.error
    
    # Merge substitutions
    if 'substitutions' not in trigger:
        trigger['substitutions'] = {}
    trigger['substitutions'].update(substitutions)
    
    # Use REST API to update
    access_token = get_access_token()
    url = f"https://cloudbuild.googleapis.com/v1/projects/{PROJECT_ID}/locations/{REGION}/triggers/{TRIGGER_ID}"
    
    # Only send substitutions in the update
    update_data = {
        "substitutions": trigger['substitutions']
    }
    
    req = urllib.request.Request(
        url,
        data=json.dumps(update_data).encode('utf-8'),
        headers={
            'Authorization': f'Bearer {access_token}',
            'Content-Type': 'application/json'
        },
        method='PATCH'
    )
    
    try:
        with urllib.request.urlopen(req) as response:
            return json.loads(response.read())
    except urllib.error.HTTPError as e:
        error_body = e.read().decode('utf-8')
        print(f"Error updating trigger: {e.code} - {error_body}", file=sys.stderr)
        sys.exit(1)

def main():
    print("Retrieving secrets from Secret Manager...")
    database_url = get_secret("calcom-database-url")
    nextauth_secret = get_secret("calcom-nextauth-secret")
    calendso_key = get_secret("calcom-encryption-key")
    
    service_url = "https://calcom-europe-west1-cal-com-tin.a.run.app"
    nextauth_url = f"{service_url}/api/auth"
    
    substitutions = {
        "_DATABASE_URL": database_url,
        "_NEXTAUTH_SECRET": nextauth_secret,
        "_CALENDSO_ENCRYPTION_KEY": calendso_key,
        "_NEXT_PUBLIC_WEBAPP_URL": service_url,
        "_NEXTAUTH_URL": nextauth_url
    }
    
    print("Getting current trigger configuration...")
    trigger = get_trigger()
    
    print("Updating trigger with new substitutions...")
    result = update_trigger(trigger, substitutions)
    
    print("✓ Trigger updated successfully!")
    print(f"\nUpdated substitutions:")
    for key, value in substitutions.items():
        if 'SECRET' in key or 'KEY' in key:
            print(f"  {key}: [hidden]")
        else:
            print(f"  {key}: {value}")

if __name__ == "__main__":
    main()

