-- lua/shrimply-suggest/core.lua
local M = {}

-- Plugin configuration
local config = {
  debounce_time = 200,    -- Debounce time in milliseconds
  get_suggestion_fn = nil -- User-defined function to get suggestions
}

-- Suggestion state
local suggestions = {}
local current_suggestion_index = 1
local timer = nil

function M.setup(opts)
  -- Merge user-provided options with default configuration
  config = vim.tbl_deep_extend("force", config, opts or {})
end

-- Update the M.get_mock_suggestions function to generate a single suggestion
function M.get_mock_suggestion()
  local random_string = ""
  for j = 1, 10 do
    local random_char = string.char(math.random(97, 122)) -- Generate a random lowercase letter
    random_string = random_string .. random_char
  end
  return "Suggestion " .. (#suggestions + 1) .. ": " .. random_string
end

function M.request_suggestion()
  -- Cancel any existing timer
  if timer then
    timer:stop()
    timer = nil
  end

  -- Start a new timer to debounce the request
  timer = vim.loop.new_timer()
  timer:start(config.debounce_time, 0, vim.schedule_wrap(function()
    -- Get the text before and after the current position
    local current_line = vim.api.nvim_get_current_line()
    local cursor_pos = vim.api.nvim_win_get_cursor(0)[2]
    local text_before_cursor = current_line:sub(1, cursor_pos)
    local text_after_cursor = current_line:sub(cursor_pos + 1)

    -- Check if there is text after the cursor
    if text_after_cursor:len() > 0 then
      -- Clear the current suggestion list and displayed suggestion
      suggestions = {}
      current_suggestion_index = 1
      M.clear_suggestion()
      return
    end

    -- Get the suggestion
    local new_suggestion
    if config.get_suggestion_fn then
      -- Use pcall to handle any errors in the user-defined function
      local success, result = pcall(config.get_suggestion_fn, text_before_cursor, text_after_cursor)
      if success then
        new_suggestion = result
      else
        -- If an error occurs, print an error message and return
        print("Error in get_suggestion_fn: " .. result)
        return
      end
    else
      new_suggestion = M.get_mock_suggestion()
    end

    -- Insert the suggestion into the suggestions array
    table.insert(suggestions, new_suggestion)

    current_suggestion_index = #suggestions
    M.show_suggestion()
  end))
end

function M.get_mock_suggestions(text_before_cursor, text_after_cursor)
  for i = 1, 3 do
    local random_string = ""
    for j = 1, 10 do
      local random_char = string.char(math.random(97, 122)) -- Generate a random lowercase letter
      random_string = random_string .. random_char
    end
    suggestions[i] = "Suggestion " .. i .. ": " .. random_string
  end
  return suggestions
end

function M.show_suggestion()
  if vim.api.nvim_get_mode().mode == "i" then
    local suggestion = suggestions[current_suggestion_index]
    print("show_suggestion #" .. current_suggestion_index .. ": " .. suggestion)

    -- Clear the previous suggestion
    M.clear_suggestion()

    if suggestion then
      -- Display the suggestion using virtual text at the end of the current line
      local current_line = vim.api.nvim_get_current_line()
      vim.api.nvim_buf_set_extmark(0, vim.g.shrimply_suggest_ns, vim.api.nvim_win_get_cursor(0)[1] - 1, #current_line, {
        virt_text = { { suggestion .. " (" .. current_suggestion_index .. "/" .. #suggestions .. ")", "Comment" } },
        virt_text_pos = "overlay"
      })
    end
  else
    M.clear_suggestion()
  end
end

function M.clear_suggestion()
  vim.api.nvim_buf_clear_namespace(0, vim.g.shrimply_suggest_ns, 0, -1)
end

function M.accept_suggestion()
  if vim.api.nvim_get_mode().mode == "i" then
    local suggestion = suggestions[current_suggestion_index]
    if suggestion then
      -- Insert the accepted suggestion at the current position
      local cursor_pos = vim.api.nvim_win_get_cursor(0)
      local current_line = vim.api.nvim_get_current_line()
      local updated_line = current_line:sub(1, cursor_pos[2]) .. suggestion .. current_line:sub(cursor_pos[2] + 1)
      vim.api.nvim_set_current_line(updated_line)
      vim.api.nvim_win_set_cursor(0, { cursor_pos[1], cursor_pos[2] + #suggestion })
    end
    M.clear_suggestion()
    suggestions = {}
    current_suggestion_index = 1
  end
end

function M.move_to_next_suggestion()
  print("going to next suggestion")
  if vim.api.nvim_get_mode().mode == "i" then
    if current_suggestion_index < #suggestions then
      current_suggestion_index = current_suggestion_index + 1
      print("Showing suggestion #" .. current_suggestion_index)
      M.show_suggestion()
    else
      -- Request a new suggestion if at the last suggestion
      M.request_suggestion()
    end
  end
end

function M.move_to_previous_suggestion()
  print("going to previous suggestion")
  if vim.api.nvim_get_mode().mode == "i" then
    if current_suggestion_index > 1 then
      current_suggestion_index = current_suggestion_index - 1
      print("Showing suggestion #" .. current_suggestion_index)
      M.show_suggestion()
    else
      -- Cycle to the last suggestion if at the first suggestion
      current_suggestion_index = #suggestions
      M.show_suggestion()
    end
  end
end

-- Set up autocommands
vim.api.nvim_create_autocmd({ "InsertEnter" }, {
  callback = function()
    vim.g.shrimply_suggest_ns = vim.api.nvim_create_namespace("ShrimplySuggest")
    M.request_suggestion()
  end
})

vim.api.nvim_create_autocmd({ "InsertLeave" }, {
  callback = function()
    M.clear_suggestion()
    if timer then
      timer:stop()
      timer = nil
    end
  end
})

vim.api.nvim_create_autocmd({ "TextChangedI" }, {
  callback = function()
    -- Clear the current suggestion list
    suggestions = {}
    current_suggestion_index = 1

    M.clear_suggestion()
    M.request_suggestion()
  end
})

return M
