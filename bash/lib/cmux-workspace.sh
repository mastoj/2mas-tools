#!/usr/bin/env bash
# Creates a git worktree + cmux workspace in one shot.
#
# Usage:
#   cgw <branch> [base-branch] [repo-root]
#
# Examples:
#   cgw feature/my-thing             # branch off current HEAD
#   cgw feature/my-thing main        # branch off main
#   cgw feature/my-thing main ~/code/myrepo

set -euo pipefail

BRANCH="${1:?Usage: cgw <branch> [base-branch] [repo-root]}"
BASE_BRANCH="${2:-HEAD}"
REPO_ROOT="${3:-$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")}"
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
REPO_CONFIG_FILE="$REPO_ROOT/.cgw/config.json"
CONFIG_FILE="$WORKTREE_PATH/.cgw/config.json"

DEFAULT_INIT_COMMAND=""
DEFAULT_GIT_VIEW_COMMAND="lazygit"
DEFAULT_EDITOR_COMMAND="hx ."
DEFAULT_AGENT_COMMAND="opencode ."

config_command() {
  local key="$1"
  local default_value="$2"

  if [[ ! -f "$CONFIG_FILE" ]]; then
    printf '%s\n' "$default_value"
    return 0
  fi

  if ! command -v jq &>/dev/null; then
    echo "jq is required to read $CONFIG_FILE"
    exit 1
  fi

  jq -er --arg key "$key" --arg default_value "$default_value" '
    if type != "object" then
      error("config root must be a JSON object")
    else
      .commands // {} |
      if type != "object" then
        error(".commands must be a JSON object")
      else
        .[$key] // $default_value |
        if type != "string" then
          error(".commands.\($key) must be a string")
        else
          .
        end
      end
    end
  ' "$CONFIG_FILE"
}

run_surface_command() {
  local surface_id="$1"
  local command="$2"
  local quoted_command
  local cmux_args=(--workspace "$WORKSPACE_ID")

  [[ -n "$command" ]] || return 0

  if [[ -n "$surface_id" ]]; then
    cmux_args+=(--surface "$surface_id")
  fi

  quoted_command=$(printf '%q' "$command")
  cmux send "${cmux_args[@]}" "bash -lc $quoted_command"
  cmux send-key "${cmux_args[@]}" Return
}

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

if [[ -f "$REPO_CONFIG_FILE" && ! -f "$CONFIG_FILE" ]]; then
  mkdir -p "$(dirname "$CONFIG_FILE")"
  cp "$REPO_CONFIG_FILE" "$CONFIG_FILE"
  echo "Copied workspace config to $CONFIG_FILE"
fi

if [[ -f "$CONFIG_FILE" ]]; then
  echo "Using workspace config: $CONFIG_FILE"
else
  echo "No workspace config found. Using defaults. Checked: $CONFIG_FILE"
fi

AGENT_COMMAND="$(config_command agent "$DEFAULT_AGENT_COMMAND")"
GIT_VIEW_COMMAND="$(config_command gitView "$DEFAULT_GIT_VIEW_COMMAND")"
EDITOR_COMMAND="$(config_command editor "$DEFAULT_EDITOR_COMMAND")"
INIT_COMMAND="$(config_command init "$DEFAULT_INIT_COMMAND")"

# ── Create and name the cmux workspace ───────────────────────────────────
WORKSPACE_ID=$(cmux new-workspace --cwd "$WORKTREE_PATH")
WORKSPACE_ID=${WORKSPACE_ID#OK }
sleep 0.5
cmux rename-workspace --workspace "$WORKSPACE_ID" -- "$WORKSPACE_NAME"

# ── Left pane: open OpenCode ───────────────────────────────────────────────
run_surface_command "" "$AGENT_COMMAND"

# ── Split right → lazygit ─────────────────────────────────────────────────
RIGHT_ID=$(cmux new-split right --workspace "$WORKSPACE_ID" --cwd "$WORKTREE_PATH")
RIGHT_ID=${RIGHT_ID#OK }
RIGHT_ID=${RIGHT_ID%% *}
sleep 0.3
run_surface_command "$RIGHT_ID" "$GIT_VIEW_COMMAND"

# ── Split right pane down → spare shell ──────────────────────────────────
BOTTOM_ID=$(cmux new-split down --workspace "$WORKSPACE_ID" --surface "$RIGHT_ID" --cwd "$WORKTREE_PATH")
BOTTOM_ID=${BOTTOM_ID#OK }
BOTTOM_ID=${BOTTOM_ID%% *}
# Uncomment to auto-start something in the bottom pane:
# cmux send --workspace "$WORKSPACE_ID" --surface "$BOTTOM_ID" "npm run dev"
# cmux send-key --workspace "$WORKSPACE_ID" --surface "$BOTTOM_ID" Return
sleep 0.3
run_surface_command "$BOTTOM_ID" "$EDITOR_COMMAND"

# New surface in initial pane
TERMINAL_ID=$(cmux new-surface --workspace "$WORKSPACE_ID" --cwd "$WORKTREE_PATH")
TERMINAL_ID=${TERMINAL_ID#OK }
TERMINAL_ID=${TERMINAL_ID%% *}
sleep 0.3

if [[ -n "$INIT_COMMAND" ]]; then
  echo "Running workspace init command..."
  run_surface_command "$TERMINAL_ID" "$INIT_COMMAND"
fi

# -- select workspace --
cmux select-workspace --workspace "$WORKSPACE_ID"

echo ""
echo "✓ Workspace '$WORKSPACE_NAME' open at $WORKTREE_PATH"
echo "  To tear everything down: cgw delete --yes $BRANCH $REPO_ROOT"
