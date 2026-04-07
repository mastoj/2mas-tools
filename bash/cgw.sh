#!/usr/bin/env bash
# Cmux Git Worktree wrapper.

set -euo pipefail

SOURCE="${BASH_SOURCE[0]}"
while [[ -L "$SOURCE" ]]; do
  SOURCE_DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
  SOURCE="$(readlink "$SOURCE")"
  [[ "$SOURCE" != /* ]] && SOURCE="$SOURCE_DIR/$SOURCE"
done

SCRIPT_DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
CREATE_SCRIPT="$SCRIPT_DIR/lib/cmux-workspace.sh"
DELETE_SCRIPT="$SCRIPT_DIR/lib/cmux-workspace-delete.sh"
LIST_SCRIPT="$SCRIPT_DIR/lib/cgw-workspace-list.sh"

print_help() {
  cat <<'EOF'
Usage:
  cgw <branch> [base-branch] [repo-root]
  cgw delete <branch> [repo-root]
  cgw list [repo-root]
  cgw --help

Commands:
  <none>    Create a cmux workspace and git worktree
  delete    Delete a cmux workspace and git worktree
  list      List cgw worktrees for a repo
  --help    Show this help menu

Notes:
  cgw reads .cgw/config.json from the repo root when present.
  Supported commands are init, gitView, editor, and agent.
  Defaults: init="", gitView="lazygit", editor="hx .", agent="opencode ."
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
  list)
    shift
    exec bash "$LIST_SCRIPT" "$@"
    ;;
  *)
    exec bash "$CREATE_SCRIPT" "$@"
    ;;
esac
