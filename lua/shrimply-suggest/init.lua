-- lua/shrimply-suggest/init.lua
local core = require("shrimply-suggest.core")

local M = {}

function M.setup(opts)
  -- Plugin setup and configuration
  core.setup(opts)

  -- Set up keymaps
  vim.api.nvim_set_keymap("i", "<M-s>", "", {
    noremap = true,
    silent = true,
    callback = function()
      core.request_suggestion()
    end
  })

  vim.api.nvim_set_keymap("i", "<M-l>", "", {
    noremap = true,
    silent = true,
    callback = function()
      core.accept_suggestion()
    end
  })

  vim.api.nvim_set_keymap("i", "<M-]>", "", {
    noremap = true,
    silent = true,
    callback = function()
      core.move_to_next_suggestion()
    end
  })

  vim.api.nvim_set_keymap("i", "<M-[>", "", {
    noremap = true,
    silent = true,
    callback = function()
      core.move_to_previous_suggestion()
    end
  })

  print("Loaded shrimply")
end

return M
