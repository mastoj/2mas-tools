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

ensure_jq() {
  if ! command -v jq &>/dev/null; then
    echo "jq is required to read $CONFIG_FILE"
    exit 1
  fi
}

validate_config_root() {
  [[ -f "$CONFIG_FILE" ]] || return 0

  ensure_jq

  jq -e 'if type != "object" then error("config root must be a JSON object") else true end' "$CONFIG_FILE" >/dev/null
}

config_command() {
  local key="$1"
  local default_value="$2"

  if [[ ! -f "$CONFIG_FILE" ]]; then
    printf '%s\n' "$default_value"
    return 0
  fi

  ensure_jq

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

config_has_workspace() {
  [[ -f "$CONFIG_FILE" ]] || return 1

  ensure_jq

  jq -e '
    if type != "object" then
      error("config root must be a JSON object")
    else
      (.workspace // null) | type == "object"
    end
  ' "$CONFIG_FILE" >/dev/null
}

config_query_path() {
  local path_label="$1"
  local filter="$2"
  local path_json
  shift 2

  path_json=$(jq -nc '$ARGS.positional | map(if test("^[0-9]+$") then tonumber else . end)' --args "$@")

  jq -er --arg path_label "$path_label" "
    (getpath(\$path)) as \$node |
    $filter
  " --argjson path "$path_json" "$CONFIG_FILE"
}

workspace_node_kind() {
  local path_label="$1"
  shift

  config_query_path "$path_label" '
    if $node == null then
      error($path_label + " must not be null")
    elif ($node | type) != "object" then
      error($path_label + " must be an object")
    else
      [($node | has("split")), ($node | has("command")), ($node | has("tabs"))] |
      map(select(.)) |
      length as $kind_count |
      if $kind_count == 0 then
        error($path_label + " must contain exactly one of split, command, or tabs")
      elif $kind_count > 1 then
        error($path_label + " cannot mix split, command, and tabs")
      elif $node | has("split") then
        "split"
      elif $node | has("command") then
        "command"
      else
        "tabs"
      end
    end
  ' "$@"
}

workspace_split_direction() {
  local path_label="$1"
  shift

  config_query_path "$path_label" '
    if ($node.split | type) != "string" then
      error($path_label + ".split must be a string")
    elif ($node.split | IN("left", "right", "up", "down")) then
      $node.split
    else
      error($path_label + ".split must be one of left, right, up, or down")
    end
  ' "$@"
}

workspace_children_count() {
  local path_label="$1"
  shift

  config_query_path "$path_label" '
    if ($node.children | type) != "array" then
      error($path_label + ".children must be an array")
    elif ($node.children | length) != 2 then
      error($path_label + ".children must contain exactly 2 items")
    else
      $node.children | length
    end
  ' "$@"
}

workspace_command_value() {
  local path_label="$1"
  shift

  config_query_path "$path_label" '
    if ($node.command | type) != "string" then
      error($path_label + ".command must be a string")
    else
      $node.command
    end
  ' "$@"
}

workspace_tabs_count() {
  local path_label="$1"
  shift

  config_query_path "$path_label" '
    if ($node.tabs | type) != "array" then
      error($path_label + ".tabs must be an array")
    elif ($node.tabs | length) == 0 then
      error($path_label + ".tabs must contain at least 1 item")
    else
      $node.tabs | length
    end
  ' "$@"
}

workspace_tab_command() {
  local path_label="$1"
  local tab_index="$2"
  local path_json
  shift 2

  path_json=$(jq -nc '$ARGS.positional | map(if test("^[0-9]+$") then tonumber else . end)' --args "$@")

  jq -er --arg path_label "$path_label" --argjson tab_index "$tab_index" '
    (getpath($path)) as $node |
    if ($node.tabs[$tab_index] | type) != "object" then
      error($path_label + ".tabs[" + ($tab_index | tostring) + "] must be an object")
    elif ($node.tabs[$tab_index].command | type) != "string" then
      error($path_label + ".tabs[" + ($tab_index | tostring) + "].command must be a string")
    else
      $node.tabs[$tab_index].command
    end
  ' --argjson path "$path_json" "$CONFIG_FILE"
}

list_workspace_panes() {
  cmux --json list-panes --workspace "$WORKSPACE_ID" | jq -r '.panes[].ref'
}

initial_workspace_pane() {
  cmux --json list-panes --workspace "$WORKSPACE_ID" | jq -er '.panes[0].ref'
}

pane_selected_surface() {
  local pane_ref="$1"

  cmux --json list-panes --workspace "$WORKSPACE_ID" \
    | jq -er --arg pane_ref "$pane_ref" '.panes[] | select(.ref == $pane_ref) | .selected_surface_ref'
}

create_surface_in_pane() {
  local pane_ref="$1"
  local surface_ref

  surface_ref=$(cmux new-surface --workspace "$WORKSPACE_ID" --pane "$pane_ref")
  surface_ref=${surface_ref#OK }
  surface_ref=${surface_ref%% *}
  printf '%s\n' "$surface_ref"
}

create_split_pane() {
  local pane_ref="$1"
  local direction="$2"
  local selected_surface
  local before_panes
  local after_panes
  local new_pane_ref=""
  local candidate

  selected_surface=$(pane_selected_surface "$pane_ref")
  before_panes="$(list_workspace_panes)"

  cmux new-split "$direction" --workspace "$WORKSPACE_ID" --surface "$selected_surface" >/dev/null
  sleep 0.3

  after_panes="$(list_workspace_panes)"

  while IFS= read -r candidate; do
    [[ -n "$candidate" ]] || continue
    if ! grep -qxF "$candidate" <<<"$before_panes"; then
      new_pane_ref="$candidate"
      break
    fi
  done <<<"$after_panes"

  if [[ -z "$new_pane_ref" ]]; then
    echo "Failed to resolve new pane after splitting $pane_ref $direction" >&2
    exit 1
  fi

  printf '%s\n' "$new_pane_ref"
}

populate_pane_command() {
  local pane_ref="$1"
  local command="$2"
  local surface_ref

  surface_ref=$(pane_selected_surface "$pane_ref")
  run_surface_command "$surface_ref" "$command"
}

populate_pane_tabs() {
  local pane_ref="$1"
  local path_label="$2"
  shift 2
  local path_args=("$@")
  local tab_count
  local tab_index
  local command
  local surface_ref

  tab_count=$(workspace_tabs_count "$path_label" "${path_args[@]}")

  for ((tab_index = 0; tab_index < tab_count; tab_index++)); do
    command=$(workspace_tab_command "$path_label" "$tab_index" "${path_args[@]}")

    if (( tab_index == 0 )); then
      surface_ref=$(pane_selected_surface "$pane_ref")
    else
      surface_ref=$(create_surface_in_pane "$pane_ref")
      sleep 0.3
    fi

    run_surface_command "$surface_ref" "$command"
  done
}

build_workspace_node() {
  local pane_ref="$1"
  local path_label="$2"
  shift 2
  local path_args=("$@")
  local node_kind
  local direction
  local child_count
  local new_pane_ref
  local first_pane_ref
  local second_pane_ref
  local command

  node_kind=$(workspace_node_kind "$path_label" "${path_args[@]}")

  case "$node_kind" in
    split)
      direction=$(workspace_split_direction "$path_label" "${path_args[@]}")
      child_count=$(workspace_children_count "$path_label" "${path_args[@]}")
      [[ "$child_count" == "2" ]] || exit 1

      new_pane_ref=$(create_split_pane "$pane_ref" "$direction")

      case "$direction" in
        right|down)
          first_pane_ref="$pane_ref"
          second_pane_ref="$new_pane_ref"
          ;;
        left|up)
          first_pane_ref="$new_pane_ref"
          second_pane_ref="$pane_ref"
          ;;
      esac

      build_workspace_node "$first_pane_ref" "$path_label.children[0]" "${path_args[@]}" children 0
      build_workspace_node "$second_pane_ref" "$path_label.children[1]" "${path_args[@]}" children 1
      ;;
    command)
      command=$(workspace_command_value "$path_label" "${path_args[@]}")
      populate_pane_command "$pane_ref" "$command"
      ;;
    tabs)
      populate_pane_tabs "$pane_ref" "$path_label" "${path_args[@]}"
      ;;
  esac
}

create_default_workspace_layout() {
  local root_pane_ref="$1"
  local right_pane_ref
  local bottom_pane_ref
  local terminal_surface_ref

  populate_pane_command "$root_pane_ref" "$AGENT_COMMAND"

  right_pane_ref=$(create_split_pane "$root_pane_ref" right)
  sleep 0.3
  populate_pane_command "$right_pane_ref" "$GIT_VIEW_COMMAND"

  bottom_pane_ref=$(create_split_pane "$right_pane_ref" down)
  sleep 0.3
  populate_pane_command "$bottom_pane_ref" "$EDITOR_COMMAND"

  terminal_surface_ref=$(create_surface_in_pane "$root_pane_ref")
  sleep 0.3

  if [[ -n "$INIT_COMMAND" ]]; then
    echo "Running workspace init command..."
    run_surface_command "$terminal_surface_ref" "$INIT_COMMAND"
  fi
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

validate_config_root

AGENT_COMMAND="$(config_command agent "$DEFAULT_AGENT_COMMAND")"
GIT_VIEW_COMMAND="$(config_command gitView "$DEFAULT_GIT_VIEW_COMMAND")"
EDITOR_COMMAND="$(config_command editor "$DEFAULT_EDITOR_COMMAND")"
INIT_COMMAND="$(config_command init "$DEFAULT_INIT_COMMAND")"

# ── Create and name the cmux workspace ───────────────────────────────────
WORKSPACE_ID=$(cmux new-workspace --cwd "$WORKTREE_PATH")
WORKSPACE_ID=${WORKSPACE_ID#OK }
sleep 0.5
cmux rename-workspace --workspace "$WORKSPACE_ID" -- "$WORKSPACE_NAME"

ROOT_PANE_REF=$(initial_workspace_pane)

if config_has_workspace; then
  echo "Building workspace from .workspace config"
  build_workspace_node "$ROOT_PANE_REF" ".workspace" workspace
else
  create_default_workspace_layout "$ROOT_PANE_REF"
fi

# -- select workspace --
cmux select-workspace --workspace "$WORKSPACE_ID"

echo ""
echo "✓ Workspace '$WORKSPACE_NAME' open at $WORKTREE_PATH"
echo "  To tear everything down: cgw delete --yes $BRANCH $REPO_ROOT"
