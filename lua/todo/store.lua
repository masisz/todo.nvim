local config = require("todo.config")

local M = {}

--- Lines of a todo, preferring a loaded buffer so unsaved edits are visible.
---@param path string
---@return string[]|nil
function M.read_lines(path)
  local buf = vim.fn.bufnr(path)
  if buf ~= -1 and vim.api.nvim_buf_is_loaded(buf) then
    return vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  end
  local ok, lines = pcall(vim.fn.readfile, path)
  return ok and lines or nil
end

--- Identifier used to link daily todos to a roadmap milestone: the file name without extension.
---@param name string
---@return string
function M.id(name)
  return (name:gsub("%.[^.]*$", ""))
end

--- List todos of a kind ("daily" or "roadmap") in its directory (or its done/ subdirectory).
---@param kind "daily"|"roadmap"
---@param done? boolean
---@return { path: string, name: string, id: string, label: string, meta: table<string, string>, done: boolean }[]
function M.scan(kind, done)
  local directory = config.dir(kind)
  if done then
    directory = vim.fs.joinpath(directory, "done")
  end
  local ext = "." .. config.options.extension
  local todos = {}
  if vim.fn.isdirectory(directory) == 1 then
    for name, type in vim.fs.dir(directory) do
      if type == "file" and vim.endswith(name, ext) then
        local path = vim.fs.joinpath(directory, name)
        local lines = M.read_lines(path)
        local meta = lines and require("todo").parse(lines).meta or {}
        local title = meta.Title
        todos[#todos + 1] = {
          path = path,
          name = name,
          id = M.id(name),
          label = title and title ~= "" and title or name,
          meta = meta,
          done = done or false,
        }
      end
    end
  end
  table.sort(todos, function(a, b) return a.name < b.name end)
  return todos
end

--- Return lines with the value of `[key]` set, adding the section at the end if missing.
---@param lines string[]
---@param key string
---@param value string
---@return string[]
function M.set_field(lines, key, value)
  local result = vim.deepcopy(lines)
  for i, line in ipairs(result) do
    if line:match("^%s*%[" .. vim.pesc(key) .. "%]%s*$") then
      local next_line = result[i + 1]
      if next_line ~= nil and not next_line:match("^%s*%[.-%]%s*$") then
        result[i + 1] = value
      else
        table.insert(result, i + 1, value)
      end
      return result
    end
  end
  result[#result + 1] = "[" .. key .. "]"
  result[#result + 1] = value
  return result
end

--- Write `[key]` = value into a todo file (and its loaded buffer, if any).
---@param path string
---@param key string
---@param value string
---@return boolean ok, string|nil err
function M.write_field(path, key, value)
  local buf = vim.fn.bufnr(path)
  local loaded = buf ~= -1 and vim.api.nvim_buf_is_loaded(buf)
  if loaded and vim.bo[buf].modified then
    return false, "Save todo first: " .. vim.fn.fnamemodify(path, ":t")
  end
  local lines = M.read_lines(path)
  if not lines then
    return false, "Cannot read " .. path
  end
  lines = M.set_field(lines, key, value)
  local ok, err = pcall(vim.fn.writefile, lines, path)
  if not ok or err ~= 0 then
    return false, "Cannot write " .. path
  end
  if loaded then
    -- The buffer had no unsaved changes, so reloading it from disk loses nothing.
    vim.api.nvim_buf_call(buf, function() vim.cmd("silent! edit!") end)
  end
  return true
end

return M
