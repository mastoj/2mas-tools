#!/usr/bin/env bash

# If an argument is provided it should be used as the input, example if taxi.HEIC is the argument it should run: magick mogrify -format jpg taxi.HEIC
# If no argument is provided it should run: magick mogrify -format jpg *.HEIC

set -euo pipefail

usage() {
    cat <<'EOF'
Usage:
  heic2jpg [file.HEIC]

Without an argument, converts all .HEIC files in the current directory.
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" || "${1:-}" == "help" ]]; then
    usage
    exit 0
fi

if ! command -v magick >/dev/null 2>&1; then
    printf 'magick not found\n' >&2
    exit 1
fi

if [[ $# -eq 0 ]]; then
    shopt -s nullglob
    files=( *.HEIC )
    shopt -u nullglob

    if [[ ${#files[@]} -eq 0 ]]; then
        printf 'No .HEIC files found in the current directory\n' >&2
        exit 1
    fi

    magick mogrify -format jpg "${files[@]}"
else
    if [[ $# -ne 1 ]]; then
        usage >&2
        exit 1
    fi

    magick mogrify -format jpg "$1"
fi
