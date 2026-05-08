# 2mas-tools

Small personal CLI tools.

The main one is `cgw`: it creates a git worktree and opens a matching `cmux` workspace in one command.

## Install

The repo includes `install.sh`, which symlinks every top-level script in `./bash` into `~/bin` and removes the `.sh` suffix from the command name.

```bash
./install.sh
```

Recommended: make sure that folder is in your `PATH`, so you can run commands directly:

```bash
export PATH="$HOME/bin:$PATH"
```

After that, commands become available as:

```bash
cgw
project-size
url-decode
heic2jpg
```

If you prefer another location, symlink the scripts in `./bash` into any directory already in your `PATH`.

## Commands

### `cgw`

Create a git worktree and open a `cmux` workspace for it.

Basic usage:

```bash
cgw <branch> [base-branch] [repo-root]
```

Examples:

```bash
cgw feature/my-thing
cgw feature/my-thing main
cgw feature/my-thing main ~/code/myrepo
```

What it does:

1. Creates a worktree under `<repo-root>/.worktrees/`.
2. Creates the branch if needed.
3. Copies `.cgw/config.json` from the repo root into the new worktree if present.
4. Opens a `cmux` workspace rooted at that worktree.
5. Builds either the default layout or a custom layout from config.

Branch names containing `/` are stored under `.worktrees/` with `/` replaced by `--`.

Example:

```text
feature/my-thing -> .worktrees/feature--my-thing
```

#### Default layout

Without a custom `.workspace` config, `cgw` uses these commands:

```text
init    = ""
gitView = "lazygit"
editor  = "hx ."
agent   = "opencode ."
```

And builds this workspace:

1. Left pane: agent command.
2. Right pane: git UI.
3. Bottom-right pane: editor.
4. Extra surface in the left pane for a shell/init command.

If `init` is non-empty, it runs in that extra surface.

#### Requirements

Required:

```text
git
cmux
```

Also used by some features:

```text
jq   - reading `.cgw/config.json`, closing cmux workspaces on delete
fzf  - `cgw list --interactive`
```

The default commands also assume these are installed unless you override them:

```text
lazygit
hx
opencode
```

#### Config

`cgw` looks for a repo-level config at:

```text
<repo-root>/.cgw/config.json
```

If present, it is copied into the created worktree at:

```text
<worktree>/.cgw/config.json
```

Minimal template:

```json
{
  "commands": {
    "init": "",
    "gitView": "lazygit",
    "editor": "hx .",
    "agent": "opencode ."
  },
  "workspace": null
}
```

`commands` values must be strings.

#### Custom workspace layout

If `.workspace` is an object, it overrides the default layout entirely.

Each node must be exactly one of:

1. `command`
2. `tabs`
3. `split`

`split` nodes must include:

1. `split`: one of `left`, `right`, `up`, `down`
2. `children`: exactly 2 child nodes

`command` nodes must include:

1. `command`: string

`tabs` nodes must include:

1. `tabs`: non-empty array of objects with `command`

Example:

```json
{
  "commands": {
    "init": "pnpm install",
    "gitView": "lazygit",
    "editor": "hx .",
    "agent": "opencode ."
  },
  "workspace": {
    "split": "right",
    "children": [
      {
        "tabs": [
          { "command": "opencode ." },
          { "command": "bash" }
        ]
      },
      {
        "split": "down",
        "children": [
          { "command": "lazygit" },
          { "command": "hx ." }
        ]
      }
    ]
  }
}
```

#### Listing worktrees

```bash
cgw list [--interactive|-i] [repo-root]
```

Without `--interactive`, it prints each `cgw`-managed worktree plus a matching delete command.

With `--interactive`, it uses `fzf` to select one or more worktrees and then deletes them.

#### Deleting one workspace

```bash
cgw delete [--yes|-y] <branch> [repo-root]
```

This will:

1. Close the matching `cmux` workspace if found.
2. Remove the git worktree under `.worktrees/`.
3. Optionally delete the local branch.

`--yes` skips prompts and also deletes the local branch.

#### Deleting all worktrees

```bash
cgw delete-all [--yes|-y] [repo-root]
```

Deletes every `cgw` worktree under `<repo-root>/.worktrees/`.

`--yes` skips prompts and deletes the matching local branches too.

#### Notes

`cgw` automatically appends `.worktrees/` to the repo's `.gitignore` if it is not already there.

### `project-size`

Count files and total lines for a file extension.

```bash
project-size <extension>
```

Example:

```bash
project-size sh
```

### `url-decode`

Decode a URL-encoded string.

```bash
url-decode <encoded-string>
```

Example:

```bash
url-decode 'hello%20world%2Ftest'
```

Requires `python3`.

### `heic2jpg`

Convert HEIC images to JPG with ImageMagick.

```bash
heic2jpg [file.HEIC]
```

Without an argument, it converts all `*.HEIC` files in the current directory.

Requires `magick`.
