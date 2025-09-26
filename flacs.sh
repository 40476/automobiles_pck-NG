#!/bin/bash

# Recursively find .ogg files and convert them to mono
find . -type f -iname "*.ogg" | while read -r file; do
    # Define backup and temp output file names
    backup="${file}.bak"
    temp="${file%.*}_mono.ogg"

    # Convert to mono using ffmpeg
    ffmpeg -i "$file" -ac 1 "$temp"

    # Move original to .bak
    mv "$file" "$backup"

    # Move mono version to original filename
    mv "$temp" "$file"

    echo "Backed up: $file → $backup"
    echo "Converted to mono: $file"
done