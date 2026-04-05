#!/usr/bin/env bash
# Creates a git worktree + cmux workspace in one shot.
#
# Usage:
#   dev-workspace.sh <branch> [base-branch] [repo-root]
#
# Examples:
#   dev-workspace.sh feature/my-thing            # branch off current HEAD
#   dev-workspace.sh feature/my-thing main        # branch off main
#   dev-workspace.sh feature/my-thing main ~/code/myrepo

set -euo pipefail

BRANCH="${1:?Usage: dev-workspace.sh <branch> [base-branch] [repo-root]}"
BASE_BRANCH="${2:-HEAD}"
REPO_ROOT="${3:-$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")}"
REPO_NAME="$(basename "$REPO_ROOT")"

BRANCH_NAME="${BRANCH##*/}"  # strip leading path, e.g. feature/foo → foo
WORKSPACE_NAME="$REPO_NAME - $BRANCH"
WORKTREE_PATH="${REPO_ROOT}/.worktrees/${BRANCH_NAME}"

# ── Sanity checks ─────────────────────────────────────────────────────────
if ! command -v cmux &>/dev/null; then
  echo "cmux CLI not found. Set it up with:"
  echo "  sudo ln -sf \"/Applications/cmux.app/Contents/Resources/bin/cmux\" /usr/local/bin/cmux"
  exit 1
fi

if ! git -C "$REPO_ROOT" rev-parse --git-dir &>/dev/null; then
  echo "Not a git repository: $REPO_ROOT"
  exit 1
fi

# ── Ensure .worktrees/ is gitignored ─────────────────────────────────────
GITIGNORE="${REPO_ROOT}/.gitignore"
if ! grep -qxF '.worktrees/' "$GITIGNORE" 2>/dev/null; then
  echo '.worktrees/' >> "$GITIGNORE"
  echo "Added .worktrees/ to .gitignore"
fi

# ── Create the worktree ───────────────────────────────────────────────────
echo "Creating worktree at $WORKTREE_PATH (branch: $BRANCH from $BASE_BRANCH)..."

if git -C "$REPO_ROOT" show-ref --verify --quiet "refs/heads/$BRANCH"; then
  git -C "$REPO_ROOT" worktree add "$WORKTREE_PATH" "$BRANCH"
else
  git -C "$REPO_ROOT" worktree add -b "$BRANCH" "$WORKTREE_PATH" "$BASE_BRANCH"
fi

echo "Worktree ready."

# ── Create and name the cmux workspace ───────────────────────────────────
WORKSPACE_ID=$(cmux new-workspace --cwd "$WORKTREE_PATH")
WORKSPACE_ID=${WORKSPACE_ID#OK }
sleep 0.5
cmux rename-workspace --workspace "$WORKSPACE_ID" -- "$WORKSPACE_NAME"

# ── Left pane: open OpenCode ───────────────────────────────────────────────
cmux send --workspace "$WORKSPACE_ID" "opencode ." 
cmux send-key --workspace "$WORKSPACE_ID" Return

# ── Split right → lazygit ─────────────────────────────────────────────────
RIGHT_ID=$(cmux new-split right --workspace "$WORKSPACE_ID" --cwd "$WORKTREE_PATH")
RIGHT_ID=${RIGHT_ID#OK }
RIGHT_ID=${RIGHT_ID%% *}
sleep 0.3
cmux send --workspace "$WORKSPACE_ID" --surface "$RIGHT_ID" "lazygit"
cmux send-key --workspace "$WORKSPACE_ID" --surface "$RIGHT_ID" Return

# ── Split right pane down → spare shell ──────────────────────────────────
BOTTOM_ID=$(cmux new-split down --workspace "$WORKSPACE_ID" --surface "$RIGHT_ID" --cwd "$WORKTREE_PATH")
BOTTOM_ID=${BOTTOM_ID#OK }
BOTTOM_ID=${BOTTOM_ID%% *}
# Uncomment to auto-start something in the bottom pane:
# cmux send --workspace "$WORKSPACE_ID" --surface "$BOTTOM_ID" "npm run dev"
# cmux send-key --workspace "$WORKSPACE_ID" --surface "$BOTTOM_ID" Return
sleep 0.3
cmux send --workspace "$WORKSPACE_ID" --surface "$BOTTOM_ID" "hx ."
cmux send-key --workspace "$WORKSPACE_ID" --surface "$BOTTOM_ID" Return

# New surface in initial pane
TERMINAL_ID=$(cmux new-surface --workspace "$WORKSPACE_ID" --cwd "$WORKTREE_PATH")
TERMINAL_ID=${TERMINAL_ID#OK }
TERMINAL_ID=${TERMINAL_ID%% *}
sleep 0.3
# Run .cgw/init.sh if it exists, for per-workspace setup
INIT_SCRIPT="$WORKTREE_PATH/.cgw/init.sh"
echo "Checking for workspace init script at $INIT_SCRIPT..."
if [[ -f "$INIT_SCRIPT" ]]; then
  echo "Running workspace init script..."
  cmux send --workspace "$WORKSPACE_ID" --surface "$TERMINAL_ID" "bash -c './.cgw/init.sh'"
  cmux send-key --workspace "$WORKSPACE_ID" --surface "$TERMINAL_ID" Return
fi

# ── Focus the left (editor) pane ─────────────────────────────────────────
# cmux send-key --workspace "$WORKSPACE_ID" --surface "$WORKSPACE_ID" Return 2>/dev/null || true

# -- select workspace -- "
cmux select-workspace --workspace "$WORKSPACE_ID"

echo ""
echo "✓ Workspace '$WORKSPACE_NAME' open at $WORKTREE_PATH"
echo "  To tear everything down: dev-workspace-delete.sh $BRANCH $REPO_ROOT"