#!/usr/bin/env bash
# Tears down a cmux workspace + git worktree created by dev-workspace.sh
#
# Usage:
#   dev-workspace-delete.sh <branch> [repo-root]

set -euo pipefail

BRANCH="${1:?Usage: dev-workspace-delete.sh <branch> [repo-root]}"
REPO_ROOT="${2:-$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")}"
REPO_NAME="$(basename "$REPO_ROOT")"

BRANCH_NAME="${BRANCH##*/}"
WORKSPACE_NAME="$REPO_NAME - $BRANCH"
WORKTREE_PATH="${REPO_ROOT}/.worktrees/${BRANCH_NAME}"

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
    | python3 -c "
import sys, json
payload = json.load(sys.stdin)
workspaces = payload.get('workspaces', [])
match = next(
  (
    w for w in workspaces
    if w.get('title') == '$WORKSPACE_NAME' or w.get('current_directory') == '$WORKTREE_PATH'
  ),
  None,
)
print(match['ref'] if match else '')
" 2>/dev/null || true)

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