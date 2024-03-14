#!/bin/bash

# Get the absolute path to the project directory
project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/.."

# Start Neovim with only the plugin loaded and the init.dev.lua file
nvim -u NONE --cmd "set runtimepath+=$project_dir" -c "luafile $project_dir/init.dev.lua" "$@" logs/dev_scratchpad.txt
