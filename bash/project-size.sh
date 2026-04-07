#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  project-size <extension>

Example:
  project-size sh
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

extension="$1"
count=0
total=0

printf 'Counting the number of .%s files and lines of code in those files\n' "$extension"

while IFS= read -r -d '' file; do
  lines=$(wc -l < "$file")
  total=$((total + lines))
  count=$((count + 1))
done < <(find . -type f -name "*.$extension" -print0)

if [[ "$count" -eq 0 ]]; then
  printf 'No .%s files found\n' "$extension"
  exit 0
fi

printf 'Number of .%s files: %s\n' "$extension" "$count"
printf 'Total number of lines: %s\n' "$total"
