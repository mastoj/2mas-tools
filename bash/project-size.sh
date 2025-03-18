#/!bin/bash

echo "Counting the number of $1 files and lines of code in the files"

find . -name "*.$1" -exec wc -l {} + | awk '{total += $1; count++} END {print "Number of .cs files:", count, "\nTotal number of lines:", total}'