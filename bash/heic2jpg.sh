#!/bin/bash

# If an argument is provided it should be used as the input, example if taxi.HEIC is the argument it should run: magick mogrify -format jpg taxi.HEIC
# If no argument is provided it should run: magick mogrify -format jpg *.HEIC

if [ -z "$1" ]; then
    magick mogrify -format jpg *.HEIC
else
    magick mogrify -format jpg $1
fi