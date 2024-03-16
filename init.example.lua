-- this file is loaded by scripts/dev.sh as the sole config file
-- be sure to copy it to `init.dev.lua` (which is gitignored)

local shrimply_suggest = require("shrimply-suggest")

shrimply_suggest.setup()

-- Define custom keymappings
vim.api.nvim_set_keymap("i", "<M-s>", "", {
  noremap = true,
  silent = true,
  callback = shrimply_suggest.request_suggestion,
})

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
