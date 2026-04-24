#!/usr/bin/env bash
# Tears down a cmux workspace + git worktree created by cgw.
#
# Usage:
#   cgw delete [--yes|-y] <branch> [repo-root]

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
  cgw delete [--yes|-y] <branch> [repo-root]

Options:
  -y, --yes  Skip confirmation prompts and delete the local branch
EOF
      exit 0
      ;;
    *)
      break
      ;;
  esac
done

BRANCH="${1:?Usage: cgw delete [--yes|-y] <branch> [repo-root]}"
REPO_ROOT="${2:-$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")}"
REPO_NAME="$(basename "$REPO_ROOT")"

default_worktree_dir_for_branch() {
  local branch="$1"
  branch="${branch#refs/heads/}"
  branch="${branch//\//--}"
  printf '%s\n' "$branch"
}

resolve_worktree_path_for_branch() {
  local branch="$1"
  local worktrees_dir="$2"
  local current_path=""
  local current_branch=""
  local branch_ref="refs/heads/${branch#refs/heads/}"
  local line

  while IFS= read -r line || [[ -n "$line" ]]; do
    case "$line" in
      worktree\ *)
        if [[ "$current_branch" == "$branch_ref" && "$current_path" == "$worktrees_dir"/* ]]; then
          printf '%s\n' "$current_path"
          return 0
        fi
        current_path="${line#worktree }"
        current_branch=""
        ;;
      branch\ *)
        current_branch="${line#branch }"
        ;;
      '')
        if [[ "$current_branch" == "$branch_ref" && "$current_path" == "$worktrees_dir"/* ]]; then
          printf '%s\n' "$current_path"
          return 0
        fi
        current_path=""
        current_branch=""
        ;;
    esac
  done < <(git -C "$REPO_ROOT" worktree list --porcelain)

  if [[ "$current_branch" == "$branch_ref" && "$current_path" == "$worktrees_dir"/* ]]; then
    printf '%s\n' "$current_path"
    return 0
  fi

  return 1
}

WORKTREES_DIR="${REPO_ROOT}/.worktrees"
WORKTREE_DIR_NAME="$(default_worktree_dir_for_branch "$BRANCH")"
WORKSPACE_NAME="$REPO_NAME - $BRANCH"
WORKTREE_PATH="$(resolve_worktree_path_for_branch "$BRANCH" "$WORKTREES_DIR" || true)"
FALLBACK_WORKTREE_PATH="${WORKTREES_DIR}/${WORKTREE_DIR_NAME}"

if ! git -C "$REPO_ROOT" rev-parse --git-dir &>/dev/null; then
  echo "Not a git repository: $REPO_ROOT"
  exit 1
fi

# ── Confirm ───────────────────────────────────────────────────────────────
echo "This will:"
echo "  1. Close the cmux workspace '$WORKSPACE_NAME'"
if [[ -n "$WORKTREE_PATH" ]]; then
  echo "  2. Remove the worktree at $WORKTREE_PATH"
else
  echo "  2. Remove the cgw worktree for branch '$BRANCH' if present under $WORKTREES_DIR"
fi
echo "  3. Optionally delete the local branch '$BRANCH'"
echo ""
if [[ "$ASSUME_YES" -eq 1 ]]; then
  echo "Auto-confirm enabled. Continuing without prompts."
else
  read -r -p "Continue? [y/N] " CONFIRM
  [[ "$CONFIRM" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }
fi

# ── Close the cmux workspace ──────────────────────────────────────────────
if ! command -v cmux &>/dev/null; then
  echo "  (cmux CLI not found — skipping workspace close)"
elif ! command -v jq &>/dev/null; then
  echo "  (jq not found — skipping workspace close)"
else
  WORKSPACE_ID=$(cmux --json list-workspaces 2>/dev/null \
    | jq -r --arg workspace_name "$WORKSPACE_NAME" 'first(.workspaces[]? | select(.title == $workspace_name) | .ref) // empty' \
      2>/dev/null || true)

  if [[ -n "$WORKSPACE_ID" ]]; then
    cmux close-workspace --workspace "$WORKSPACE_ID"
    echo "✓ Closed cmux workspace '$WORKSPACE_NAME' '$WORKSPACE_ID'"
  else
    echo "  (no open cmux workspace named '$WORKSPACE_NAME' — skipping)"
  fi
fi

# ── Remove the worktree ───────────────────────────────────────────────────
if [[ -n "$WORKTREE_PATH" ]]; then
  git -C "$REPO_ROOT" worktree remove --force "$WORKTREE_PATH"
  echo "✓ Removed worktree at $WORKTREE_PATH"
else
  echo "  (no cgw worktree found for '$BRANCH' under $WORKTREES_DIR; expected path was often $FALLBACK_WORKTREE_PATH)"
fi

git -C "$REPO_ROOT" worktree prune

# ── Optionally delete the local branch ───────────────────────────────────
echo ""
DELETE_BRANCH="n"
if [[ "$ASSUME_YES" -eq 1 ]]; then
  DELETE_BRANCH="y"
else
  read -r -p "Also delete local branch '$BRANCH'? [y/N] " DELETE_BRANCH
fi

if [[ "$DELETE_BRANCH" =~ ^[Yy]$ ]]; then
  if git -C "$REPO_ROOT" show-ref --verify --quiet "refs/heads/$BRANCH"; then
    git -C "$REPO_ROOT" branch -d "$BRANCH" 2>/dev/null \
      || git -C "$REPO_ROOT" branch -D "$BRANCH"
    echo "✓ Deleted branch '$BRANCH'"
  else
    echo "  (branch '$BRANCH' not found — skipping)"
  fi
fi

echo ""
echo "✓ Done. Workspace '$WORKSPACE_NAME' fully cleaned up."
