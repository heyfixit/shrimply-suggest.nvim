-- lua/shrimply-suggest/init.lua

local core = require("shrimply-suggest.core")

local M = {}

function M.setup(opts)
  -- Plugin setup and configuration
  core.setup(opts)
end

-- Expose the core functions as part of the public API
M.request_suggestion = core.request_suggestion
M.accept_suggestion = core.accept_suggestion
M.move_to_next_suggestion = core.move_to_next_suggestion
M.move_to_previous_suggestion = core.move_to_previous_suggestion

return M
