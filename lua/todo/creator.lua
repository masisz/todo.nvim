local config = require("todo.config")

local M = {}

--- Generate next todo file path unused in both the todo and done directories
---@param directory string
---@param date_format string
---@param extension string
---@return string
local function get_next_path(directory, date_format, extension)
  local date = os.date(date_format)
  local seq = 1
  local path
  local done_path
  repeat
    local name = string.format("%s-%02d.%s", date, seq, extension)
    path = vim.fs.joinpath(directory, name)
    done_path = vim.fs.joinpath(directory, "done", name)
    seq = seq + 1
  until not vim.uv.fs_stat(path) and vim.fn.bufnr(path) == -1
    and not vim.uv.fs_stat(done_path) and vim.fn.bufnr(done_path) == -1
  return path
end

--- Resolve template lines (executing functions if any)
---@param template (string|fun():string)[]
---@return string[]
local function resolve_template(template)
  local lines = {}
  for _, line in ipairs(template) do
    if type(line) == "function" then
      lines[#lines + 1] = tostring(line())
    else
      lines[#lines + 1] = tostring(line)
    end
  end
  return lines
end

--- Create and open a new todo file
---@param opts? table
---@return string Filepath of the newly created todo
function M.create_task(opts)
  local opts_merged = vim.tbl_deep_extend("force", config.options, opts or {})

  local directory = vim.fn.fnamemodify(vim.fn.expand(opts_merged.directory), ":p")
  vim.fn.mkdir(directory, "p")

  local path = get_next_path(directory, opts_merged.date_format, opts_merged.extension)

  vim.cmd.edit(vim.fn.fnameescape(path))

  local lines = resolve_template(opts_merged.template)
  vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)

  vim.bo.filetype = opts_merged.extension

  if opts_merged.cursor_pos then
    pcall(vim.api.nvim_win_set_cursor, 0, opts_merged.cursor_pos)
  end

  if opts_merged.start_insert then
    vim.cmd("startinsert!")
    vim.schedule(function()
      vim.cmd("startinsert!")
    end)
    vim.defer_fn(function()
      local target_buf = vim.fn.bufnr(path)
      if target_buf ~= -1 and vim.api.nvim_get_current_buf() == target_buf then
        vim.cmd("startinsert!")
      end
    end, 20)
  end

  return path
end

return M
