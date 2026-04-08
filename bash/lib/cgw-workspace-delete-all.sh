#!/usr/bin/env bash
# Deletes all cgw-managed worktrees under .worktrees/ for a repo.
#
# Usage:
#   cgw delete-all [--yes|-y] [repo-root]

set -euo pipefail

ASSUME_YES=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    -y|--yes)
      ASSUME_YES=1
      shift
      ;;
    -h|--help|help)
      cat <<'EOF'
Usage:
  cgw delete-all [--yes|-y] [repo-root]

Options:
  -y, --yes  Skip confirmation prompts and delete local branches
EOF
      exit 0
      ;;
    *)
      break
      ;;
  esac
done

REPO_ROOT="${1:-$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")}"
WORKTREES_DIR="${REPO_ROOT}/.worktrees"
DELETE_SCRIPT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)/cmux-workspace-delete.sh"

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
branches=()
paths=()

collect_worktree() {
  local worktree_path="$1"
  local branch_ref="$2"
  local branch_name

  [[ "$worktree_path" == "$WORKTREES_DIR"/* ]] || return 0
  [[ -n "$branch_ref" ]] || return 0

  branch_name="${branch_ref#refs/heads/}"
  branches+=("$branch_name")
  paths+=("$worktree_path")
}

while IFS= read -r line || [[ -n "$line" ]]; do
  case "$line" in
    worktree\ *)
      if [[ -n "$current_path" ]]; then
        collect_worktree "$current_path" "$current_branch"
      fi
      current_path="${line#worktree }"
      current_branch=""
      ;;
    branch\ *)
      current_branch="${line#branch }"
      ;;
    '')
      if [[ -n "$current_path" ]]; then
        collect_worktree "$current_path" "$current_branch"
        current_path=""
        current_branch=""
      fi
      ;;
  esac
done < <(git -C "$REPO_ROOT" worktree list --porcelain)

if [[ -n "$current_path" ]]; then
  collect_worktree "$current_path" "$current_branch"
fi

if [[ "${#branches[@]}" -eq 0 ]]; then
  echo "No cgw worktrees found under $WORKTREES_DIR"
  exit 0
fi

echo "Delete all cgw worktrees in $REPO_ROOT:"
for i in "${!branches[@]}"; do
  printf '  %s (%s)\n' "${branches[$i]}" "${paths[$i]}"
done
echo ""

if [[ "$ASSUME_YES" -eq 1 ]]; then
  echo "Auto-confirm enabled. Continuing without prompts."
else
  read -r -p "Delete all listed worktrees? [y/N] " CONFIRM
  [[ "$CONFIRM" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }
fi

for branch in "${branches[@]}"; do
  bash "$DELETE_SCRIPT" --yes "$branch" "$REPO_ROOT"
done
