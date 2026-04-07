#!/usr/bin/env bash

# Create symbolic links for entry scripts in ./bash.
# Links go in ~/bin without the .sh extension.

set -euo pipefail

# Get the current directory
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Get the home directory
HOME_DIR="$HOME"

# Get the bin directory
BIN_DIR="$HOME_DIR/bin"

# Create the bin directory if it doesn't exist
if [ ! -d "$BIN_DIR" ]; then
  mkdir -p "$BIN_DIR"
fi

# Loop through top-level files in the bash directory
for file in "$DIR"/bash/*; do
  [ -f "$file" ] || continue
  # Get the file name
  file_name=$(basename "$file")
  chmod +x "$file"
  # Define target link path
  link_path="$BIN_DIR/${file_name%.sh}"
  # Refuse to clobber files or links not managed by this repo.
  if [ -L "$link_path" ]; then
    existing_target=$(readlink "$link_path")
    if [ "$existing_target" = "$file" ]; then
      continue
    fi

    echo "Skipping $link_path: points to $existing_target"
    continue
  fi

  if [ -e "$link_path" ]; then
    echo "Skipping $link_path: file already exists"
    continue
  fi
  # Create the symbolic link
  ln -s "$file" "$link_path"
done
