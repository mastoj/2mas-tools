#!/bin/bash

# Create symbolic links for all the files in the ./bash folder
# the links should be in the ~/bin folder and not have the .sh extension
# the links should be named the same as the original file

# Get the current directory
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Get the home directory
HOME_DIR=$HOME

# Get the bin directory
BIN_DIR=$HOME_DIR/bin

# Create the bin directory if it doesn't exist
if [ ! -d $BIN_DIR ]; then
  mkdir $BIN_DIR
fi

# Loop through all the files in the bash directory
for file in $DIR/bash/*; do
  # Get the file name
  file_name=$(basename $file)
  chmod +x $file
  # Define target link path
  link_path="$BIN_DIR/${file_name%.sh}"
  # Remove existing link if it exists
  if [ -e "$link_path" ] || [ -L "$link_path" ]; then
    rm "$link_path"
  fi
  # Create the symbolic link
  ln -s "$file" "$link_path"
done

