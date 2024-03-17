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

The `command` is expected to output a `json` string in the form:
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
-- 3 main keymappings that should be defined
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

## Example Generator Functions

### Remote Ollama Starcoder2
```lua
-- using lazy.nvim for plugin management
require("lazy").setup({
  "https://github.com/heyfixit/shrimply-suggest.nvim",
  config = function()
    local shrimply_suggest = require("shrimply-suggest")

    -- Initialize model configuration
    local model = {
      name = "starcoder2:7b",
      prompt_format = "<repo_name>%s\n<fim_sep>%s\n<fim_prefix>\n%s%s\n<fim_suffix>\n%s\n<fim_middle>",
      stop_sequences = { "<fim_sep>", "<|endoftext|>", "<fim_prefix>", "<fim_suffix>", "<fim_middle>", "<repo_name>" },
    }

    shrimply_suggest.setup({
      command_generator_fn = function()
        -- Get the current buffer and cursor position
        local bufnr = vim.api.nvim_get_current_buf()
        local cursor_pos = vim.api.nvim_win_get_cursor(0)
        local current_line = cursor_pos[1] - 1

        -- Get the project root directory
        local repo_name = vim.fn.fnamemodify(vim.fn.getcwd(), ":t") or ""

        -- Get the relative path to the current file
        local file_path = vim.fn.expand("%:.") or ""

        -- Get the lines above and below the current line
        local lines_above = vim.api.nvim_buf_get_lines(bufnr, math.max(0, current_line - 30), current_line, false)
        local lines_below = vim.api.nvim_buf_get_lines(
          bufnr,
          current_line + 1,
          math.min(current_line + 51, vim.api.nvim_buf_line_count(bufnr)),
          false
        )

        -- Get the text on the current line up to the cursor position
        local current_line_text = vim.api.nvim_get_current_line():sub(1, cursor_pos[2])

        -- Construct the prompt message based on the model's prompt format
        local prompt = string.format(
          model.prompt_format,
          repo_name,
          file_path,
          table.concat(lines_above or {}, "\n"),
          current_line_text,
          table.concat(lines_below or {}, "\n")
        )

        -- API request parameters
        local url = "http://YOUR_OLLAMA_URL/api/generate"
        local data = {
          model = model.name,
          prompt = prompt,
          stream = false,
          options = {
            num_predict = 100,
            top_k = 20,
            top_p = 0.5,
            temperature = 0.2,
            repeat_penalty = 1.1,
            stop = model.stop_sequences,
            num_gpu = 1,
          },
        }

        -- Build the curl command string
        local curl_cmd = string.format("curl -s '%s' -d '%s'", url, vim.fn.json_encode(data))

        -- Return the command string
        return curl_cmd
      end,
    })

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
  end,
})
```


### Automatic Model Swapping and Stats tracking
Let's say you weren't sure which model you'd prefer. This example will switch models every 20 suggestions either accepted or skipped.
It will write statistics to a json file on how many you accept vs how many you skip for each model.

```lua
-- mimic something like python's named placeholder formatting
local function format(str, params)
  return (str:gsub("({([^}]+)})", function(whole, key)
    return tostring(params[key] or whole)
  end))
end

local shrimply_suggest = require("shrimply-suggest")

-- Initialize model configurations
-- each model ends up having unique FIM prompt formats
-- sometimes you find these in the model's release paper, other times maybe in a README
local models = {
  {
    name = "starcoder2:7b",
    prompt_format = "<repo_name>{repo_name}\n<fim_sep>{file_path}\n<fim_prefix>\n{lines_before}{current_line}\n<fim_suffix>\n{lines_after}\n<fim_middle>",
    stop_sequences = { "<fim_sep>", "<|endoftext|>", "<fim_prefix>", "<fim_suffix>", "<fim_middle>", "<repo_name>" },
  },
  {
    name = "deepseek-coder:6.7b",
    prompt_format = "<｜fim▁begin｜>{lines_before}{current_line}<｜fim▁hole｜>\n{lines_after}<｜fim▁end｜>",
    stop_sequences = { "<｜fim▁begin｜>", "<｜fim▁hole｜>", "<｜fim▁end｜>" },
  },
}
-- Initialize suggestion statistics
local stats = {}
for _, model in ipairs(models) do
  stats[model.name] = {
    total_suggestions = 0,
    accepted_suggestions = 0,
  }
end
-- Load statistics from file if it exists
local stats_file = vim.fn.stdpath("data") .. "/shrimply_suggest_stats.json"
if vim.fn.filereadable(stats_file) == 1 then
  local data = vim.fn.readfile(stats_file)
  if data and data[1] then
    stats = vim.fn.json_decode(data[1])
  end
end

-- Initialize current model index
local current_model_index = 1
shrimply_suggest.setup({
  command_generator_fn = function()
    -- Get the current model
    local model = models[current_model_index]
    -- Get the current buffer and cursor position
    local bufnr = vim.api.nvim_get_current_buf()
    local cursor_pos = vim.api.nvim_win_get_cursor(0)
    local current_line = cursor_pos[1] - 1

    -- Get the project root directory
    local repo_name = vim.fn.fnamemodify(vim.fn.getcwd(), ":t") or ""

    -- Get the relative path to the current file
    local file_path = vim.fn.expand("%:.") or ""

    -- Get the lines above and below the current line
    local lines_above = vim.api.nvim_buf_get_lines(bufnr, math.max(0, current_line - 30), current_line, false)
    local lines_below = vim.api.nvim_buf_get_lines(
      bufnr,
      current_line + 1,
      math.min(current_line + 51, vim.api.nvim_buf_line_count(bufnr)),
      false
    )

    -- Get the text on the current line up to the cursor position
    local current_line_text = vim.api.nvim_get_current_line():sub(1, cursor_pos[2])

    -- Construct the prompt message based on the model's prompt format
    local prompt_values = {
      repo_name = repo_name or "",
      file_path = file_path or "",
      lines_before = table.concat(lines_above or {}, "\n"),
      current_line = current_line_text or "",
      lines_after = table.concat(lines_below or {}, "\n"),
    }

    local prompt = format(model.prompt_format, prompt_values)

    -- API request parameters
    local url = "http://YOUR_OLLAMA_URL/api/generate"
    local data = {
      model = "starcoder2:7b",
      prompt = prompt,
      stream = false,
      options = {
        num_predict = 100,
        top_k = 20,
        top_p = 0.5,
        temperature = 0.2,
        repeat_penalty = 1.1,
        stop = model.stop_sequences,
        num_gpu = 1,
      },
    }

    -- Build the curl command string
    -- We're fortunate that we know the ollama api returns JSON in our desired format of:
    -- { "response": "some response", "error": "some error reason" }
    -- So we don't need to complicate the command to do any reformatting of the output
    local curl_cmd = string.format("curl -s '%s' -d '%s'", url, vim.fn.json_encode(data))

    -- Return the command string
    return curl_cmd
  end,
})

vim.api.nvim_set_keymap("i", "<M-l>", "", {
  noremap = true,
  silent = true,
  callback = function()
    -- Increment accepted suggestions for the current model
    stats[models[current_model_index].name].accepted_suggestions = stats[models[current_model_index].name].accepted_suggestions
      + 1

    -- Increment total suggestions for the current model
    stats[models[current_model_index].name].total_suggestions = stats[models[current_model_index].name].total_suggestions
      + 1

    -- Switch to the next model every 20 suggestions
    if stats[models[current_model_index].name].total_suggestions % 20 == 0 then
      current_model_index = (current_model_index % #models) + 1
    end

    shrimply_suggest.accept_suggestion()
  end,
})

vim.api.nvim_set_keymap("i", "<M-]>", "", {
  noremap = true,
  silent = true,
  callback = function()
    -- Increment total suggestions for the current model
    stats[models[current_model_index].name].total_suggestions = stats[models[current_model_index].name].total_suggestions
      + 1

    -- Switch to the next model every 20 suggestions
    if stats[models[current_model_index].name].total_suggestions % 20 == 0 then
      current_model_index = (current_model_index % #models) + 1
    end

    shrimply_suggest.move_to_next_suggestion()
  end,
})

vim.api.nvim_set_keymap("i", "<M-[>", "", {
  noremap = true,
  silent = true,
  callback = shrimply_suggest.move_to_previous_suggestion,
})
```
