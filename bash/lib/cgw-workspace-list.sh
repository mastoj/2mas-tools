#!/usr/bin/env bash
# Lists cgw-managed worktrees under .worktrees/ for a repo.
#
# Usage:
#   cgw-workspace-list.sh [--interactive|-i] [repo-root]

set -euo pipefail

INTERACTIVE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    -i|--interactive)
      INTERACTIVE=1
      shift
      ;;
    -h|--help|help)
  cat <<'EOF'
Usage:
  cgw-workspace-list [--interactive|-i] [repo-root]

Lists git worktrees under [repo-root]/.worktrees and shows how to delete each one.

Options:
  -i, --interactive  Select worktrees in fzf and delete marked entries
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
found_any=0
worktree_lines=()

branch_to_worktree_dir() {
  local branch="$1"
  branch="${branch#refs/heads/}"
  branch="${branch//\//--}"
  printf '%s\n' "$branch"
}

print_worktree() {
  local worktree_path="$1"
  local branch_ref="$2"
  local branch_name

  [[ "$worktree_path" == "$WORKTREES_DIR"/* ]] || return 0

  found_any=1
  branch_name="${branch_ref#refs/heads/}"

  if [[ "$INTERACTIVE" -eq 1 ]]; then
    worktree_lines+=("${branch_name}"$'\t'"${worktree_path}")
    return 0
  fi

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
  exit 0
fi

if [[ "$INTERACTIVE" -eq 1 ]]; then
  if ! command -v fzf &>/dev/null; then
    echo "fzf is required for --interactive"
    exit 1
  fi

  selections="$({ printf '%s\n' "${worktree_lines[@]}"; } | fzf \
    --multi \
    --prompt='Select worktrees > ' \
    --header='tab/shift-tab move, space toggle, enter continue' \
    --bind='space:toggle' \
    --with-nth=1,2 \
    --delimiter=$'\t' \
    --preview='printf "Branch: %s\nPath:   %s\nDir:    %s\n" {1} {2} "$(basename \"{2}\")"' \
    --preview-window=down:3:wrap)"

  [[ -n "$selections" ]] || exit 0

  delete_confirmed=0
  while IFS=$'\t' read -r branch_name _; do
    [[ -n "$branch_name" ]] || continue

    if [[ "$delete_confirmed" -eq 0 ]]; then
      echo "Selected for deletion:"
      printf '%s\n' "$selections" | while IFS=$'\t' read -r selected_branch selected_path; do
        [[ -n "$selected_branch" ]] || continue
        printf '  %s (%s)\n' "$selected_branch" "$selected_path"
      done
      echo ""
      read -r -p "Delete selected worktrees? [y/N] " confirm_delete < /dev/tty
      [[ "$confirm_delete" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }
      delete_confirmed=1
    fi

    bash "$DELETE_SCRIPT" --yes "$branch_name" "$REPO_ROOT"
  done <<< "$selections"
fi
