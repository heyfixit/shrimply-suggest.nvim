-- lua/shrimply-suggest/core.lua
local M = {}

-- Plugin configuration
local config = {
  enabled = true,
  debounce_time = 500, -- Debounce time in milliseconds
  command_generator_fn = nil, -- User-defined function to generate the command string
  code_filetypes = { "lua", "python", "javascript" }, -- Default code-related filetypes
}

-- Suggestion state
local suggestions = {}
local current_suggestion_index = 1
local timer = nil
local last_suggestion_time = 0
local was_on_last_line = false
local is_showing_suggestion = false
local current_job = nil
local stopped_jobs = {}

function M.setup(opts)
  -- Merge user-provided options with default configuration
  config = vim.tbl_deep_extend("force", config, opts or {})
end

function M.toggle_suggestions()
  config.enabled = not config.enabled
  if not config.enabled then
    M.clear_suggestion()
  else
    M.request_suggestion(true)
  end
end

function M.get_mock_suggestion()
  local num_lines = math.random(1, 3)
  local suggestion = ""
  for i = 1, num_lines do
    local random_string = ""
    for j = 1, 10 do
      local random_char = string.char(math.random(97, 122)) -- Generate a random lowercase letter
      random_string = random_string .. random_char
    end
    suggestion = suggestion
      .. "This is a mock suggestion you should define your own command_generator_fn"
      .. (#suggestions + 1)
      .. " (line "
      .. i
      .. "): "
      .. random_string
    if i < num_lines then
      suggestion = suggestion .. "\n"
    end
  end
  return suggestion
end

function M.request_suggestion(reset_suggestions)
  -- If suggestions are disabled, return early
  if not config.enabled then
    M.clear_suggestion()
    return
  end

  -- Cancel any existing timer
  if timer then
    timer:stop()
    timer:close()
    timer = nil
  end

  -- Reset the suggestion list and index if reset_suggestions is true
  if reset_suggestions then
    suggestions = {}
    current_suggestion_index = 1
  end

  -- Start a new timer to debounce the request
  timer = vim.loop.new_timer()
  timer:start(
    config.debounce_time,
    0,
    vim.schedule_wrap(function()
      if not timer then
        return
      end

      timer:stop()
      timer:close()
      timer = nil

      -- Clear the displayed suggestion
      M.clear_suggestion()

      -- Get the suggestion
      local new_suggestion
      if config.command_generator_fn then
        -- Generate the command string using the user-defined function
        local command = config.command_generator_fn()

        -- Cancel the current job if it exists
        if current_job then
          vim.fn.jobstop(current_job)
          table.insert(stopped_jobs, current_job)
        end

        -- Start a new job to execute the command
        current_job = vim.fn.jobstart(command, {
          stdout_buffered = true,
          on_stdout = function(_, data)
            -- The 'data' is now a single-element table containing the entire output
            local output = data[1]
            local result = vim.fn.json_decode(output)

            if result.error then
              print("Error in command output: " .. result.error)
            else
              new_suggestion = result.response
            end

            current_job = nil
          end,
          on_stderr = function(job_id, data)
            if not vim.tbl_contains(stopped_jobs, job_id) then
              local error_message = data[1] or ""
              if error_message ~= "" then
                print("Command error: " .. error_message)
              end
            end
          end,
          on_exit = function(job_id)
            if vim.tbl_contains(stopped_jobs, job_id) then
              -- Remove the job ID from the list of stopped jobs
              for i, v in ipairs(stopped_jobs) do
                if v == job_id then
                  table.remove(stopped_jobs, i)
                  break
                end
              end
            else
              current_job = nil
              table.insert(suggestions, new_suggestion)
              current_suggestion_index = #suggestions
              M.show_suggestion()
            end
          end,
        })
      else
        new_suggestion = M.get_mock_suggestion()

        -- Insert the suggestion into the suggestions array
        table.insert(suggestions, new_suggestion)

        current_suggestion_index = #suggestions
        M.show_suggestion()
      end
    end)
  )
end

function M.show_suggestion()
  if not config.enabled then
    return
  end

  if is_showing_suggestion then
    return
  end

  is_showing_suggestion = true
  if vim.api.nvim_get_mode().mode == "i" and #suggestions > 0 then
    local suggestion = suggestions[current_suggestion_index]
    if not suggestion then
      return
    end

    -- Clear previous suggestions to avoid overlap
    M.clear_suggestion()

    local suggestion_lines = vim.split(suggestion, "\n")
    local cursor_pos = vim.api.nvim_win_get_cursor(0)
    local line_num = cursor_pos[1] - 1 -- Adjust for Lua index

    -- Add the "(current index / total)" text to the end of the first line if there are multiple suggestions
    if #suggestions > 1 then
      local index_text = string.format("(%d/%d)", current_suggestion_index, #suggestions)
      suggestion_lines[1] = suggestion_lines[1] .. " " .. index_text
    end

    -- Display the first line as virtual text right after the current cursor position
    vim.api.nvim_buf_set_extmark(0, vim.g.shrimply_suggest_ns, line_num, cursor_pos[2], {
      virt_text = { { suggestion_lines[1], "Comment" } },
      virt_text_pos = "eol", -- Display at the end of the line to mimic inline suggestions
    })

    -- Set virtual lines for multiline suggestions
    if #suggestion_lines > 1 then
      local virt_lines = {}
      for i = 2, #suggestion_lines do
        table.insert(virt_lines, { { suggestion_lines[i], "Comment" } })
      end
      vim.api.nvim_buf_set_extmark(0, vim.g.shrimply_suggest_ns, line_num, cursor_pos[2], {
        virt_lines = virt_lines,
        virt_lines_above = false,
        hl_mode = "replace",
      })
    end
  end
  is_showing_suggestion = false
  last_suggestion_time = vim.loop.hrtime()
end

function M.clear_suggestion()
  -- Check if the namespace ID exists before clearing it
  if vim.g.shrimply_suggest_ns and type(vim.g.shrimply_suggest_ns) == "number" then
    vim.api.nvim_buf_clear_namespace(0, vim.g.shrimply_suggest_ns, 0, -1)
  end

  -- Remove the extra empty line if it was added at the last line
  if was_on_last_line then
    local last_line_num = vim.api.nvim_buf_line_count(0)
    vim.api.nvim_buf_set_lines(0, last_line_num - 1, last_line_num, false, {})
    was_on_last_line = false
  end
end

function M.accept_suggestion()
  if vim.api.nvim_get_mode().mode == "i" then
    local suggestion = suggestions[current_suggestion_index]
    if suggestion then
      -- Insert the accepted suggestion at the current position
      local cursor_pos = vim.api.nvim_win_get_cursor(0)
      local current_line = vim.api.nvim_get_current_line()
      local updated_lines = vim.split(suggestion, "\n")
      if #updated_lines == 1 then
        -- Single-line suggestion
        local updated_line = current_line:sub(1, cursor_pos[2]) .. updated_lines[1]
        vim.api.nvim_set_current_line(updated_line)
        vim.api.nvim_win_set_cursor(0, { cursor_pos[1], cursor_pos[2] + #updated_lines[1] })
      else
        -- Multi-line suggestion
        vim.api.nvim_set_current_line(current_line:sub(1, cursor_pos[2]) .. updated_lines[1])
        for i = 2, #updated_lines do
          vim.api.nvim_buf_set_lines(0, cursor_pos[1] + i - 2, cursor_pos[1] + i - 2, false, { updated_lines[i] })
        end
        vim.api.nvim_win_set_cursor(0, { cursor_pos[1] + #updated_lines - 1, #updated_lines[#updated_lines] })
      end
    end
    M.clear_suggestion()
    suggestions = {}
    current_suggestion_index = 1
  end
end

function M.move_to_next_suggestion()
  if vim.api.nvim_get_mode().mode == "i" then
    if current_suggestion_index < #suggestions then
      current_suggestion_index = current_suggestion_index + 1
      M.show_suggestion()
    else
      -- Request a new suggestion without resetting the suggestion list
      M.request_suggestion(false)
    end
  end
end

function M.move_to_previous_suggestion()
  if vim.api.nvim_get_mode().mode == "i" then
    if current_suggestion_index > 1 then
      current_suggestion_index = current_suggestion_index - 1
      M.show_suggestion()
    else
      -- Cycle to the last suggestion if at the first suggestion
      current_suggestion_index = #suggestions
      M.show_suggestion()
    end
  end
end

-- Clear existing autocommands before setting up new ones
vim.api.nvim_clear_autocmds({ group = vim.g.shrimply_suggest_ns })

-- Set up autocommands
vim.api.nvim_create_autocmd({ "InsertEnter" }, {
  callback = function()
    local filetype = vim.bo.filetype
    if vim.tbl_contains(config.code_filetypes, filetype) then
      vim.g.shrimply_suggest_ns = vim.api.nvim_create_namespace("ShrimplySuggest")
      M.request_suggestion()
    end
  end,
})

vim.api.nvim_create_autocmd({ "InsertLeave" }, {
  callback = function()
    local filetype = vim.bo.filetype
    if vim.tbl_contains(config.code_filetypes, filetype) then
      M.clear_suggestion()
      if timer then
        timer:stop()
        timer = nil
      end
    end
  end,
})

vim.api.nvim_create_autocmd({ "TextChangedI", "TextChangedP" }, {
  callback = function()
    local filetype = vim.bo.filetype
    if vim.tbl_contains(config.code_filetypes, filetype) then
      if
        not config.enabled
        or is_showing_suggestion
        or vim.loop.hrtime() - last_suggestion_time < config.debounce_time * 1e6
      then
        return
      end
      M.clear_suggestion() -- Clear the displayed suggestion
      M.request_suggestion(true) -- Reset suggestions when the user starts typing
    end
  end,
})

return M
