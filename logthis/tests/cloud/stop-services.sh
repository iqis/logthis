#!/usr/bin/env bash
set -e

# Script to stop LocalStack and Azurite
# Usage: ./stop-services.sh [--clean]
#   --clean: Remove data volumes

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "Stopping cloud services..."
docker-compose down

if [[ "$1" == "--clean" ]]; then
  echo "Removing data volumes..."
  rm -rf localstack-data azurite-data
  echo "✓ Services stopped and data cleaned"
else
  echo "✓ Services stopped (data preserved)"
  echo "  To remove data: ./stop-services.sh --clean"
fi
