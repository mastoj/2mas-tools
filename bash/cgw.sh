#!/usr/bin/env bash
# Cmux Git Worktree wrapper.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CREATE_SCRIPT="$SCRIPT_DIR/lib/cmux-workspace.sh"
DELETE_SCRIPT="$SCRIPT_DIR/lib/cmux-workspace-delete.sh"

print_help() {
  cat <<'EOF'
Usage:
  cgw <branch> [base-branch] [repo-root]
  cgw delete <branch> [repo-root]
  cgw --help

Commands:
  <none>    Create a cmux workspace and git worktree
  delete    Delete a cmux workspace and git worktree
  --help    Show this help menu
EOF
}

case "${1:-}" in
  -h|--help|help)
    print_help
    ;;
  delete)
    shift
    exec bash "$DELETE_SCRIPT" "$@"
    ;;
  *)
    exec bash "$CREATE_SCRIPT" "$@"
    ;;
esac
