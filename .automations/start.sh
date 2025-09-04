#!/bin/bash

set -e

echo ">>> Starting all services..."

find ./services -name "docker-compose.yml" | while read compose; do
  dir=$(dirname "$compose")
  echo ">>> Starting service in $dir"
  (cd "$dir" && docker compose up -d)
done

echo ">>> All services started"
