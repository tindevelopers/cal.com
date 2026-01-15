#!/bin/bash

# Docker Image Management Script
# Pull images from Google Cloud Registry and push to GitHub Container Registry

set -e

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
PROJECT_ID="${PROJECT_ID:-cal-com-tin}"
SERVICE_NAME="${SERVICE_NAME:-calcom}"
GCR_IMAGE="gcr.io/${PROJECT_ID}/${SERVICE_NAME}"
GITHUB_USER="${GITHUB_USER:-}"
GITHUB_REPO="${GITHUB_REPO:-cal.com}"  # Change to your GitHub org/repo

echo -e "${BLUE}=== Docker Image Management ===${NC}"
echo ""

# Function to pull image from GCR
pull_from_gcr() {
    local TAG="${1:-latest}"
    echo -e "${GREEN}Pulling image from Google Container Registry...${NC}"
    echo "Image: ${GCR_IMAGE}:${TAG}"
    
    # Authenticate with GCR
    gcloud auth configure-docker gcr.io --quiet
    
    # Pull the image
    docker pull "${GCR_IMAGE}:${TAG}"
    
    echo -e "${GREEN}✓ Successfully pulled ${GCR_IMAGE}:${TAG}${NC}"
    echo ""
}

# Function to push image to GitHub Container Registry
push_to_github() {
    local TAG="${1:-latest}"
    local GITHUB_TAG="${2:-${TAG}}"
    
    if [ -z "$GITHUB_USER" ]; then
        echo -e "${YELLOW}⚠ GITHUB_USER not set. Please set it:${NC}"
        echo "  export GITHUB_USER=your-github-username"
        echo "  or run: GITHUB_USER=your-username $0 push-to-github"
        exit 1
    fi
    
    local GHCR_IMAGE="ghcr.io/${GITHUB_USER}/${SERVICE_NAME}"
    
    echo -e "${GREEN}Pushing image to GitHub Container Registry...${NC}"
    echo "Source: ${GCR_IMAGE}:${TAG}"
    echo "Target: ${GHCR_IMAGE}:${GITHUB_TAG}"
    echo ""
    
    # Check if image exists locally
    if ! docker images "${GCR_IMAGE}:${TAG}" | grep -q "${SERVICE_NAME}"; then
        echo -e "${YELLOW}Image not found locally. Pulling first...${NC}"
        pull_from_gcr "$TAG"
    fi
    
    # Tag the image for GitHub
    docker tag "${GCR_IMAGE}:${TAG}" "${GHCR_IMAGE}:${GITHUB_TAG}"
    
    # Login to GitHub Container Registry
    echo "Please enter your GitHub Personal Access Token (with 'write:packages' permission):"
    echo "You can create one at: https://github.com/settings/tokens"
    echo -n "Token: "
    read -s GITHUB_TOKEN
    echo ""
    
    echo "${GITHUB_TOKEN}" | docker login ghcr.io -u "${GITHUB_USER}" --password-stdin
    
    # Push to GitHub
    docker push "${GHCR_IMAGE}:${GITHUB_TAG}"
    
    # Optionally push latest tag
    if [ "$TAG" != "latest" ] && [ "$GITHUB_TAG" != "latest" ]; then
        docker tag "${GCR_IMAGE}:${TAG}" "${GHCR_IMAGE}:latest"
        docker push "${GHCR_IMAGE}:latest"
    fi
    
    echo -e "${GREEN}✓ Successfully pushed to ${GHCR_IMAGE}:${GITHUB_TAG}${NC}"
    echo ""
    echo "Image available at: https://github.com/${GITHUB_USER}/${GITHUB_REPO}/pkgs/container/${SERVICE_NAME}"
}

# Function to list available images
list_images() {
    echo -e "${BLUE}Available images in GCR:${NC}"
    gcloud container images list-tags "${GCR_IMAGE}" --limit=10 --format="table(digest,tags,timestamp.date())"
    echo ""
}

# Function to build locally and push to GitHub
build_and_push_to_github() {
    local TAG="${1:-latest}"
    
    if [ -z "$GITHUB_USER" ]; then
        echo -e "${YELLOW}⚠ GITHUB_USER not set${NC}"
        exit 1
    fi
    
    local GHCR_IMAGE="ghcr.io/${GITHUB_USER}/${SERVICE_NAME}"
    
    echo -e "${GREEN}Building Docker image locally...${NC}"
    
    # Build the image
    docker build \
        --build-arg NEXT_PUBLIC_WEBAPP_URL="${NEXT_PUBLIC_WEBAPP_URL:-http://localhost:3000}" \
        --build-arg BUILD_STANDALONE=true \
        -t "${GHCR_IMAGE}:${TAG}" \
        -t "${GHCR_IMAGE}:latest" \
        .
    
    # Login to GitHub
    echo "Please enter your GitHub Personal Access Token:"
    echo -n "Token: "
    read -s GITHUB_TOKEN
    echo ""
    echo "${GITHUB_TOKEN}" | docker login ghcr.io -u "${GITHUB_USER}" --password-stdin
    
    # Push
    docker push "${GHCR_IMAGE}:${TAG}"
    docker push "${GHCR_IMAGE}:latest"
    
    echo -e "${GREEN}✓ Successfully built and pushed to GitHub${NC}"
}

# Main menu
case "${1:-help}" in
    pull)
        pull_from_gcr "${2:-latest}"
        ;;
    push-to-github)
        push_to_github "${2:-latest}" "${3:-}"
        ;;
    list)
        list_images
        ;;
    build-and-push)
        build_and_push_to_github "${2:-latest}"
        ;;
    *)
        echo "Usage: $0 [command] [options]"
        echo ""
        echo "Commands:"
        echo "  pull [tag]              Pull image from GCR (default: latest)"
        echo "  push-to-github [tag]    Pull from GCR and push to GitHub Container Registry"
        echo "  list                    List available images in GCR"
        echo "  build-and-push [tag]    Build locally and push to GitHub"
        echo ""
        echo "Examples:"
        echo "  $0 pull latest"
        echo "  $0 pull e5a07d27-0fe1-4936-be88-8cf095ae5577"
        echo "  GITHUB_USER=your-username $0 push-to-github latest"
        echo "  GITHUB_USER=your-username $0 build-and-push v1.0.0"
        echo ""
        echo "Environment variables:"
        echo "  PROJECT_ID      Google Cloud project ID (default: cal-com-tin)"
        echo "  SERVICE_NAME    Service name (default: calcom)"
        echo "  GITHUB_USER     Your GitHub username (required for push operations)"
        ;;
esac

