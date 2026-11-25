#!/usr/bin/env bash
# Deprecated shim: the logic now lives in the `homelab` CLI.
# Kept so existing habits and scripts keep working.
set -euo pipefail
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/homelab" up "$@"
