local M = { cases = {}, current_file = "" }

function M.test(name, fn)
  M.cases[#M.cases + 1] = { name = M.current_file .. ": " .. name, fn = fn }
end

function M.eq(expected, actual, msg)
  if not vim.deep_equal(expected, actual) then
    error(("%sexpected %s, got %s"):format(msg and (msg .. ": ") or "", vim.inspect(expected), vim.inspect(actual)), 2)
  end
end

function M.ok(value, msg)
  if not value then
    error(msg or "expected truthy value", 2)
  end
end

--- Fresh todo directory with roadmap milestones; returns its path.
---@param milestones table<string, { title: string, due?: string, duration?: string, done?: boolean }>
function M.fixture(milestones)
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir .. "/roadmap/done", "p")
  for id, m in pairs(milestones) do
    local path = dir .. "/roadmap/" .. (m.done and "done/" or "") .. id .. ".todo"
    vim.fn.writefile({ "[Title]", m.title, "[Memo]", "", "[Due]", m.due or "", "[Duration]", m.duration or "" }, path)
  end
  require("todo.config").setup({ directory = dir })
  return dir
end

function M.run()
  local failed = 0
  for _, case in ipairs(M.cases) do
    local ok, err = xpcall(case.fn, debug.traceback)
    if ok then
      io.stdout:write("ok   " .. case.name .. "\n")
    else
      failed = failed + 1
      io.stdout:write("FAIL " .. case.name .. "\n" .. tostring(err) .. "\n")
    end
  end
  io.stdout:write(("\n%d passed, %d failed\n"):format(#M.cases - failed, failed))
  os.exit(failed == 0 and 0 or 1)
end

return M
