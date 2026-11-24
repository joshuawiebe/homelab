#!/usr/bin/env bash
# Install the homelab CLI: symlink into PATH, bash completion, optional snapshot timer.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREFIX="/usr/local/bin"
WITH_TIMER=0

usage() {
  cat <<'EOF'
Usage: ./install.sh [options]

  --prefix DIR     where to put the `homelab` symlink (default: /usr/local/bin)
  --with-timer     also install the nightly snapshot systemd timer
  -h, --help       show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --prefix) PREFIX="${2:?--prefix needs a value}"; shift 2 ;;
    --with-timer) WITH_TIMER=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown option: $1" >&2; usage >&2; exit 1 ;;
  esac
done

python3 -c 'import sys; sys.exit(0 if sys.version_info >= (3, 11) else 1)' || {
  echo "error: python 3.11 or newer is required (found $(python3 -V 2>&1))" >&2
  exit 1
}

mkdir -p "$PREFIX"
ln -sfn "$ROOT/bin/homelab" "$PREFIX/homelab"
echo "linked $PREFIX/homelab -> $ROOT/bin/homelab"

COMPLETION_DIR="/etc/bash_completion.d"
if [[ -f "$ROOT/completions/homelab.bash" && -d "$COMPLETION_DIR" ]]; then
  if install -m 644 "$ROOT/completions/homelab.bash" "$COMPLETION_DIR/homelab" 2>/dev/null; then
    echo "installed completion $COMPLETION_DIR/homelab"
  else
    echo "skipped completion (need root for $COMPLETION_DIR)"
  fi
fi

if [[ "$WITH_TIMER" -eq 1 ]]; then
  "$PREFIX/homelab" --root "$ROOT" snapshot install
fi

cat <<EOF

Next steps:
  homelab config          # create services/*/.env (secrets, domains)
  homelab doctor          # preflight checks
  homelab up              # start the stack
  homelab status          # health + URLs

Run the test suite with: python3 -m unittest discover -s tests
EOF
