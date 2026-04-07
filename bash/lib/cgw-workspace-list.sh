#!/usr/bin/env bash
# Lists cgw-managed worktrees under .worktrees/ for a repo.
#
# Usage:
#   cgw-workspace-list.sh [repo-root]

set -euo pipefail

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" || "${1:-}" == "help" ]]; then
  cat <<'EOF'
Usage:
  cgw-workspace-list [repo-root]

Lists git worktrees under [repo-root]/.worktrees and shows how to delete each one.
EOF
  exit 0
fi

REPO_ROOT="${1:-$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")}"
WORKTREES_DIR="${REPO_ROOT}/.worktrees"

if ! git -C "$REPO_ROOT" rev-parse --git-dir &>/dev/null; then
  echo "Not a git repository: $REPO_ROOT"
  exit 1
fi

if [[ ! -d "$WORKTREES_DIR" ]]; then
  echo "No .worktrees directory found in $REPO_ROOT"
  exit 0
fi

current_path=""
current_branch=""
found_any=0

print_worktree() {
  local worktree_path="$1"
  local branch_ref="$2"
  local branch_name

  [[ "$worktree_path" == "$WORKTREES_DIR"/* ]] || return 0

  found_any=1
  branch_name="${branch_ref#refs/heads/}"

  echo "Worktree: $worktree_path"
  echo "Branch:   $branch_name"
  echo "Delete:   cgw delete --yes $branch_name \"$REPO_ROOT\""
  echo ""
}

while IFS= read -r line || [[ -n "$line" ]]; do
  case "$line" in
    worktree\ *)
      if [[ -n "$current_path" ]]; then
        print_worktree "$current_path" "$current_branch"
      fi
      current_path="${line#worktree }"
      current_branch=""
      ;;
    branch\ *)
      current_branch="${line#branch }"
      ;;
    '')
      if [[ -n "$current_path" ]]; then
        print_worktree "$current_path" "$current_branch"
        current_path=""
        current_branch=""
      fi
      ;;
  esac
done < <(git -C "$REPO_ROOT" worktree list --porcelain)

if [[ -n "$current_path" ]]; then
  print_worktree "$current_path" "$current_branch"
fi

if [[ "$found_any" -eq 0 ]]; then
  echo "No cgw worktrees found under $WORKTREES_DIR"
fi
