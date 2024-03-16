# shrimply-suggest.nvim

Neovim plugin that mimics base functionality of LLM-style code-completion plugins.
Created to experiment with "Fill In The Middle" LLMs like starcoder2 and deepseek-coder.

## Installation
Should work with any plugin manager.

Packer.nvim
```lua
use 'heyfixit/shrimply-suggest.nvim'
```

vim-plug
```lua
Plug 'heyfixit/shrimply-suggest.nvim'
```

## Configuration

```lua
local shrimply_suggest = require("shrimply-suggest")

shrimply_suggest.setup({
  enabled = true,
  debounce_time = 500, -- Debounce time in milliseconds
  command_generator_fn = nil, -- User-defined function to generate the command string
  code_filetypes = { "lua", "python", "javascript" }, -- Default code-related filetypes
})
```

The `command_generator_fn` is a function that generates an external command that will be executed
after the debounce period passes. Only the most recent instance of this command will be run to completion.
If any instances of this command is in flight and another is triggered, the prior one is killed.

The `command` is expected to return a `json` string in the form:
```json
{
  "response": "This should be a string representing the completion suggestion",
  "error": "If this field is present, the command is assumed to have failed"
}
```

A lot is left to user configuration here, it is up to you to produce the proper command string, whether it's `curl`,
`ollama`, or something else.

## Keymappings

```lua
-- Define custom keymappings
vim.api.nvim_set_keymap("i", "<M-l>", "", {
  noremap = true,
  silent = true,
  callback = shrimply_suggest.accept_suggestion,
})

vim.api.nvim_set_keymap("i", "<M-]>", "", {
  noremap = true,
  silent = true,
  callback = shrimply_suggest.move_to_next_suggestion,
})

vim.api.nvim_set_keymap("i", "<M-[>", "", {
  noremap = true,
  silent = true,
  callback = shrimply_suggest.move_to_previous_suggestion,
})
```
