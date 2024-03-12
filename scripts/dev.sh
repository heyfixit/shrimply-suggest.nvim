#!/bin/bash

# Get the absolute path to the project directory
project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/.."

# Start Neovim with only the plugin loaded and call the setup function
nvim -u NONE --cmd "set runtimepath+=$project_dir" -c "lua require('shrimply-suggest').setup()" "$@" logs/dev_scratchpad.txt
