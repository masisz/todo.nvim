local uv = vim.uv or vim.loop

local M = {}

--- Read a whole file as a binary string.
---@param path string
---@return string|nil
function M.read(path)
  local file = io.open(path, "rb")
  if not file then
    return nil
  end
  local data = file:read("*a")
  file:close()
  return data
end

--- Write data next to `path` and rename it over `path`, so readers never see a half-written file.
--- NOTE: overwriting an existing file with fs_rename on Windows must be verified on a real machine
--- (tests/fsutil_spec.lua covers it).
---@param path string
---@param data string
---@return boolean ok, string|nil err
function M.write_atomic(path, data)
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  local tmp = path .. ".tmp" .. tostring(uv.hrtime())
  local file, err = io.open(tmp, "wb")
  if not file then
    return false, err
  end
  local ok, write_err = file:write(data)
  file:close()
  if not ok then
    os.remove(tmp)
    return false, write_err
  end
  local renamed, rename_err = uv.fs_rename(tmp, path)
  if not renamed then
    os.remove(tmp)
    return false, rename_err
  end
  return true
end

return M
