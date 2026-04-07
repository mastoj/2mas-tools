#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  url-decode <encoded-string>
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" || "${1:-}" == "help" ]]; then
  usage
  exit 0
fi

if [[ $# -ne 1 ]]; then
  usage >&2
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  printf 'python3 not found\n' >&2
  exit 1
fi

printf '%s\n' "$1" | python3 -c 'import sys, urllib.parse; print(urllib.parse.unquote(sys.stdin.read().rstrip("\n")))'
