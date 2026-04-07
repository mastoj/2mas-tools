#!/usr/bin/env bash
# Tears down a cmux workspace + git worktree created by cgw.
#
# Usage:
#   cgw delete <branch> [repo-root]

set -euo pipefail

BRANCH="${1:?Usage: cgw delete <branch> [repo-root]}"
REPO_ROOT="${2:-$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")}"
REPO_NAME="$(basename "$REPO_ROOT")"

branch_to_worktree_dir() {
  local branch="$1"
  branch="${branch#refs/heads/}"
  branch="${branch//\//--}"
  printf '%s\n' "$branch"
}

WORKTREE_DIR_NAME="$(branch_to_worktree_dir "$BRANCH")"
WORKSPACE_NAME="$REPO_NAME - $BRANCH"
WORKTREE_PATH="${REPO_ROOT}/.worktrees/${WORKTREE_DIR_NAME}"

if ! git -C "$REPO_ROOT" rev-parse --git-dir &>/dev/null; then
  echo "Not a git repository: $REPO_ROOT"
  exit 1
fi

# ── Confirm ───────────────────────────────────────────────────────────────
echo "This will:"
echo "  1. Close the cmux workspace '$WORKSPACE_NAME'"
echo "  2. Remove the worktree at $WORKTREE_PATH"
echo "  3. Optionally delete the local branch '$BRANCH'"
echo ""
read -r -p "Continue? [y/N] " CONFIRM
[[ "$CONFIRM" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }

# ── Close the cmux workspace ──────────────────────────────────────────────
if command -v cmux &>/dev/null; then
  WORKSPACE_ID=$(cmux --json list-workspaces 2>/dev/null \
    | WORKSPACE_NAME="$WORKSPACE_NAME" WORKTREE_PATH="$WORKTREE_PATH" python3 -c '
import json
import os
import sys

payload = json.load(sys.stdin)
workspace_name = os.environ["WORKSPACE_NAME"]
worktree_path = os.environ["WORKTREE_PATH"]
workspaces = payload.get('workspaces', [])
match = next(
  (
    w for w in workspaces
    if w.get("title") == workspace_name or w.get("current_directory") == worktree_path
  ),
  None,
)
print(match["ref"] if match else "")
' 2>/dev/null || true)

  if [[ -n "$WORKSPACE_ID" ]]; then
    cmux close-workspace --workspace "$WORKSPACE_ID"
    echo "✓ Closed cmux workspace '$WORKSPACE_NAME'"
  else
    echo "  (no open cmux workspace named '$WORKSPACE_NAME' — skipping)"
  fi
else
  echo "  (cmux CLI not found — skipping workspace close)"
fi

# ── Remove the worktree ───────────────────────────────────────────────────
if git -C "$REPO_ROOT" worktree list --porcelain | grep -Fxq "worktree $WORKTREE_PATH"; then
  git -C "$REPO_ROOT" worktree remove --force "$WORKTREE_PATH"
  echo "✓ Removed worktree at $WORKTREE_PATH"
else
  echo "  (worktree not found at $WORKTREE_PATH — may already be removed)"
fi

git -C "$REPO_ROOT" worktree prune

# ── Optionally delete the local branch ───────────────────────────────────
echo ""
read -r -p "Also delete local branch '$BRANCH'? [y/N] " DELETE_BRANCH
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
