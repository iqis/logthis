#!/usr/bin/env bash
set -e

# Script to start LocalStack and Azurite for testing cloud backends
# Usage: ./start-services.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "Starting LocalStack and Azurite..."
docker-compose up -d

echo "Waiting for LocalStack to be healthy..."
timeout 60 bash -c 'until docker-compose exec -T localstack curl -sf http://localhost:4566/_localstack/health > /dev/null; do sleep 2; done'

echo "Waiting for Azurite to be healthy..."
timeout 60 bash -c 'until nc -z localhost 10000; do sleep 2; done'

echo ""
echo "Services started successfully!"
echo ""

# Create S3 bucket in LocalStack
echo "Creating S3 bucket 'logthis-test'..."
AWS_ACCESS_KEY_ID=test \
AWS_SECRET_ACCESS_KEY=test \
aws --endpoint-url=http://localhost:4566 \
    s3 mb s3://logthis-test \
    --region us-east-1 || echo "Bucket may already exist"

# Create Azure container in Azurite
echo "Creating Azure container 'logthis-test'..."
# Using curl to create container via REST API
curl -X PUT \
  -H "x-ms-version: 2019-12-12" \
  "http://127.0.0.1:10000/devstoreaccount1/logthis-test?restype=container" \
  2>/dev/null || echo "Container may already exist"

echo ""
echo "✓ Cloud infrastructure ready for testing"
echo ""
echo "  LocalStack S3:    http://localhost:4566"
echo "  Azurite Blob:     http://localhost:10000"
echo ""
echo "To stop services: ./stop-services.sh"
