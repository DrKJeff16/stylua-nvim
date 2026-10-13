---@class StyluaNvim
local M = {}

M.config = {} ---@type StyluaNvimOpts

---@class StyluaNvim.State
---@field had_format_err boolean
local state = { had_format_err = false }

---@class StyluaNvimOpts
---@field error_display_strategy? 'loclist'
---@field config_file? string
local defaults = { error_display_strategy = 'loclist' }

---@param bufnr integer
---@return string text
local function buf_get_full_text(bufnr)
  return table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, true), '\n')
    .. (vim.api.nvim_get_option_value('eol', { buf = bufnr }) and '\n' or '')
end

---@return string flags
local function create_flags()
  return M.config.config_file and ('--config-path %s'):format(M.config.config_file) or '--search-parent-directories'
end

---@param output string
---@param input string
local function no_errors(output, input)
  if output ~= input then
    vim.api.nvim_buf_set_lines(
      vim.api.nvim_get_current_buf(),
      0,
      -1,
      false,
      vim.split(output, '\n', { trimempty = false })
    )
  end

  if M.config.error_display_strategy == 'loclist' and state.had_format_err then
    -- We try a little bit to make sure we aren't closing a loclist that we didn't create.
    -- This isn't perfect in the case of long sessions, but probably better than nothing.
    vim.fn.setloclist(0, {})
    vim.cmd.lclose()
  end
end

---@param error_file string
---@param bufnr integer
local function handle_errors(error_file, bufnr)
  local errors = table.concat(vim.fn.readfile(error_file), ' ')

  -- Error messages from stylua have been observed in two general formats:
  --
  -- Parsing error:
  --    error: failed to format from stdin: error parsing: unexpected token `{`. (starting from line 4, character 11 and ending on line 4, character 12)
  --
  -- Execution error:
  --    error: Found argument '--config-path/Users/jsimpson/dotfiles/nvim/language/stylua.toml' which wasn't expected, or isn't valid in this context

  -- The following approach is sufficient for the observed error messages, but a little fragile as
  -- it assumes that the first two numerical values in the error message are the row and column of
  -- the error. Generally, parsing related errors will contain the following substring in the error
  -- message:
  --    (starting from line 32, character 2 and ending on line 32, character 5)
  -- So we assume that:
  --	- locations[1] = start line
  --	- locations[2] = start col
  --	- locations[3] = end line
  --	- locations[4] = end col
  local locations = {} ---@type { [1]?: integer, [2]?: integer, [3]?: integer, [4]?: integer }
  for num in errors:gmatch('%d+') do
    table.insert(locations, num)
  end

  if M.config.error_display_strategy == 'loclist' then
    -- Error messages where location information could not be parsed will be given (0, 0) as a
    -- location.
    vim.fn.setloclist(0, { { bufnr = bufnr, lnum = locations[1] or 0, col = locations[2] or 0, text = errors } })
    vim.cmd.lopen()
  end
  state.had_format_err = true
end

---@param user_config? StyluaNvimOpts
---@param extra_flags? string
function M.format_file(user_config, extra_flags)
  user_config = user_config or {}
  M.config.error_display_strategy = user_config.error_display_strategy or M.config.error_display_strategy

  local error_file = vim.fn.tempname()
  local stylua_command = ('stylua %s %s - 2> %s'):format(create_flags(), extra_flags or '', error_file)
  local bufnr = vim.api.nvim_get_current_buf()
  local input = buf_get_full_text(bufnr)
  local output = vim.fn.system(stylua_command, input)
  if vim.fn.empty(output) == 0 then
    no_errors(output, input)
  else
    handle_errors(error_file, bufnr)
  end

  vim.fn.delete(error_file)
end

---@param start integer
---@param stop integer
---@param user_config? StyluaNvimOpts
function M.format_range(start, stop, user_config)
  local extra_flags = ('--range-start %d'):format(vim.fn.line2byte(start) - 1)
  M.format_file(
    user_config,
    stop == vim.api.nvim_buf_line_count(vim.api.nvim_get_current_buf()) and extra_flags
      or ('%s --range-end %d'):format(extra_flags, vim.fn.line2byte(stop + 1) - 1)
  )
end

---@param opts? StyluaNvimOpts
function M.setup(opts)
  M.config = vim.tbl_deep_extend('keep', opts or {}, defaults)

  vim.api.nvim_create_user_command('Stylua', function()
    M.format_file(M.config)
  end, {})
end

return M
-- vim: set ts=2 sts=2 sw=2 et ai si sta:
