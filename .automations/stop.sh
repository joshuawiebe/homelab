#!/bin/bash

set -e

echo ">>> Stopping all services..."

find ./services -name "docker-compose.yml" | while read compose; do
  dir=$(dirname "$compose")
  echo ">>> Stopping service in $dir"
  (cd "$dir" && docker compose down)
done

echo ">>> All services stopped"
