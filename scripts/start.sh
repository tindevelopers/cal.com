#!/bin/sh
set -x
set -e

# Replace the statically built BUILT_NEXT_PUBLIC_WEBAPP_URL with run-time NEXT_PUBLIC_WEBAPP_URL
# NOTE: if these values are the same, this will be skipped.
scripts/replace-placeholder.sh "$BUILT_NEXT_PUBLIC_WEBAPP_URL" "$NEXT_PUBLIC_WEBAPP_URL"

# Wait for database if DATABASE_HOST is set (for non-Cloud Run deployments)
if [ -n "$DATABASE_HOST" ]; then
  scripts/wait-for-it.sh ${DATABASE_HOST} -- echo "database is up"
fi

echo "Running database migrations..."
npx prisma migrate deploy --schema /calcom/packages/prisma/schema.prisma || {
  echo "ERROR: Database migrations failed!"
  exit 1
}
echo "Database migrations completed."

# Seed app store in background (non-blocking) - deprecated but still needed for some apps
# Temporarily disable set -e for background process to avoid script exit on error
set +e
(npx ts-node --transpile-only /calcom/scripts/seed-app-store.ts 2>&1 || echo "Seed script completed with errors") &
SEED_PID=$!
set -e
echo "Seed script started with PID $SEED_PID (non-blocking)"

# Cloud Run sets PORT environment variable, Next.js will use it automatically
# If PORT is not set, default to 3000
export PORT=${PORT:-3000}
echo "=========================================="
echo "Starting server on port $PORT"
echo "Environment: PORT=$PORT, NODE_ENV=$NODE_ENV"
echo "Working directory: $(pwd)"
echo "=========================================="

# Verify yarn is available
if ! command -v yarn >/dev/null 2>&1; then
  echo "ERROR: yarn command not found!"
  exit 1
fi
echo "Yarn version: $(yarn --version)"

# Start the server using workspace command
echo "Executing: yarn workspace @calcom/web start --port $PORT"
exec yarn workspace @calcom/web start --port $PORT
