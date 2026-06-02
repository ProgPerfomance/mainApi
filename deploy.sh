#!/bin/bash
set -e

SERVICE_NAME="kirill-api"
MONGO_SERVICE_NAME="kirill-mongo"

if [ ! -f .env ]; then
  echo "Missing .env file"
  echo "Create backend/kirill_api/.env before deploy"
  exit 1
fi

echo "=============================="
echo "DEPLOY STARTED"
echo "=============================="

echo "Pulling latest code..."
git pull

echo "Building docker image..."
docker compose build

echo "Restarting API and MongoDB containers..."
docker compose up -d --remove-orphans

echo "🧹 Cleaning old images..."
docker image prune -f

echo "=============================="
echo "DEPLOY COMPLETE"
echo "=============================="

echo "Running containers:"
docker ps | grep -E "$SERVICE_NAME|$MONGO_SERVICE_NAME" || true

echo "Last logs:"
docker logs --tail=20 $SERVICE_NAME || true
docker logs --tail=40 $MONGO_SERVICE_NAME || true
