#!/bin/sh
set -x
set -e

# Function to log with timestamp
log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

# Function to log error and exit
error_exit() {
  log "ERROR: $*"
  exit 1
}

log "=========================================="
log "Starting Cal.com application"
log "=========================================="

# Function to sanitize environment variable (remove newlines, trailing spaces, breaks)
sanitize_env() {
  echo "$1" | tr -d '\n\r' | sed 's/[[:space:]]*$//' | sed 's/^[[:space:]]*//'
}

# Sanitize and validate required environment variables
log "Sanitizing and validating required environment variables..."

# Sanitize DATABASE_URL
if [ -n "$DATABASE_URL" ]; then
  DATABASE_URL=$(sanitize_env "$DATABASE_URL")
  export DATABASE_URL
fi

if [ -z "$DATABASE_URL" ]; then
  error_exit "DATABASE_URL environment variable is not set!"
fi

# Sanitize DATABASE_DIRECT_URL
if [ -n "$DATABASE_DIRECT_URL" ]; then
  DATABASE_DIRECT_URL=$(sanitize_env "$DATABASE_DIRECT_URL")
  export DATABASE_DIRECT_URL
fi

if [ -z "$DATABASE_DIRECT_URL" ]; then
  log "WARNING: DATABASE_DIRECT_URL not set, using DATABASE_URL"
  export DATABASE_DIRECT_URL="$DATABASE_URL"
fi

# Sanitize NEXTAUTH_SECRET
if [ -n "$NEXTAUTH_SECRET" ]; then
  NEXTAUTH_SECRET=$(sanitize_env "$NEXTAUTH_SECRET")
  export NEXTAUTH_SECRET
fi

if [ -z "$NEXTAUTH_SECRET" ]; then
  error_exit "NEXTAUTH_SECRET environment variable is not set!"
fi

# Sanitize CALENDSO_ENCRYPTION_KEY
if [ -n "$CALENDSO_ENCRYPTION_KEY" ]; then
  CALENDSO_ENCRYPTION_KEY=$(sanitize_env "$CALENDSO_ENCRYPTION_KEY")
  export CALENDSO_ENCRYPTION_KEY
fi

if [ -z "$CALENDSO_ENCRYPTION_KEY" ]; then
  error_exit "CALENDSO_ENCRYPTION_KEY environment variable is not set!"
fi

# Sanitize other important env vars
if [ -n "$NEXT_PUBLIC_WEBAPP_URL" ]; then
  NEXT_PUBLIC_WEBAPP_URL=$(sanitize_env "$NEXT_PUBLIC_WEBAPP_URL")
  export NEXT_PUBLIC_WEBAPP_URL
fi

if [ -n "$NEXTAUTH_URL" ]; then
  NEXTAUTH_URL=$(sanitize_env "$NEXTAUTH_URL")
  export NEXTAUTH_URL
fi

log "✓ Required environment variables validated and sanitized"

# Replace the statically built BUILT_NEXT_PUBLIC_WEBAPP_URL with run-time NEXT_PUBLIC_WEBAPP_URL
# NOTE: if these values are the same, this will be skipped.
log "Replacing placeholder URLs..."
scripts/replace-placeholder.sh "$BUILT_NEXT_PUBLIC_WEBAPP_URL" "$NEXT_PUBLIC_WEBAPP_URL" || {
  log "WARNING: URL replacement failed, continuing anyway"
}

# Wait for database if DATABASE_HOST is set (for non-Cloud Run deployments)
if [ -n "$DATABASE_HOST" ]; then
  log "Waiting for database at $DATABASE_HOST..."
  scripts/wait-for-it.sh ${DATABASE_HOST} -- echo "database is up" || {
    error_exit "Database at $DATABASE_HOST is not reachable!"
  }
fi

# Test database connection before migrations
log "Testing database connection..."
npx prisma db execute --stdin --schema /calcom/packages/prisma/schema.prisma <<< "SELECT 1;" > /dev/null 2>&1 || {
  log "WARNING: Database connection test failed, but continuing with migrations..."
}

# Run database migrations with timeout
log "Running database migrations..."
MIGRATION_TIMEOUT=${MIGRATION_TIMEOUT:-300}  # Default 5 minutes
log "Migration timeout set to ${MIGRATION_TIMEOUT} seconds"

if command -v timeout >/dev/null 2>&1; then
  timeout ${MIGRATION_TIMEOUT} npx prisma migrate deploy --schema /calcom/packages/prisma/schema.prisma || {
    MIGRATION_EXIT_CODE=$?
    if [ $MIGRATION_EXIT_CODE -eq 124 ]; then
      error_exit "Database migrations timed out after ${MIGRATION_TIMEOUT} seconds!"
    else
      error_exit "Database migrations failed with exit code $MIGRATION_EXIT_CODE!"
    fi
  }
else
  # Fallback if timeout command is not available
  npx prisma migrate deploy --schema /calcom/packages/prisma/schema.prisma || {
    error_exit "Database migrations failed!"
  }
fi

log "✓ Database migrations completed successfully"

# Seed app store in background (non-blocking) - deprecated but still needed for some apps
log "Starting app store seed script in background..."
set +e
(npx ts-node --transpile-only /calcom/scripts/seed-app-store.ts 2>&1 || log "Seed script completed with errors") &
SEED_PID=$!
set -e
log "Seed script started with PID $SEED_PID (non-blocking)"

# Cloud Run sets PORT environment variable, Next.js will use it automatically
# If PORT is not set, default to 3000
export PORT=${PORT:-3000}
log "=========================================="
log "Starting server on port $PORT"
log "Environment: PORT=$PORT, NODE_ENV=$NODE_ENV"
log "Working directory: $(pwd)"
log "Node version: $(node --version)"
log "=========================================="

# Verify yarn is available
if ! command -v yarn >/dev/null 2>&1; then
  error_exit "yarn command not found!"
fi
log "Yarn version: $(yarn --version)"

# Verify node_modules exists
if [ ! -d "node_modules" ]; then
  error_exit "node_modules directory not found!"
fi

# Verify the web app directory exists
if [ ! -d "apps/web" ]; then
  error_exit "apps/web directory not found!"
fi

# Start the server using workspace command
log "Executing: yarn workspace @calcom/web start --port $PORT"
log "Server startup initiated..."
exec yarn workspace @calcom/web start --port $PORT
