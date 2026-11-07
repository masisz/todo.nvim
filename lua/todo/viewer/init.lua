--- Roadmap viewer: dependency graph and gantt in a browser, served by this Neovim.
local M = {}

--- Start the local server (if needed) and open the viewer in the default browser.
function M.open()
  local server = require("todo.viewer.server")
  if not server.asset_path() then
    vim.notify("todo.nvim: assets/roadmap.html not found", vim.log.levels.ERROR)
    return
  end
  local url, err = server.start()
  if not url then
    vim.notify("todo.nvim: cannot start viewer: " .. tostring(err), vim.log.levels.ERROR)
    return
  end
  local ok, open_err = pcall(require("todo.calendar").open_url, url)
  if not ok then
    vim.notify("todo.nvim: open " .. url .. " in a browser (" .. tostring(open_err) .. ")", vim.log.levels.WARN)
  else
    vim.notify("todo.nvim: roadmap viewer at http://127.0.0.1:" .. server.state.port)
  end
end

function M.stop()
  require("todo.viewer.server").stop()
  vim.notify("todo.nvim: roadmap viewer stopped")
end

--- :RoadmapExport [format]
---@param format? string
function M.export(format)
  format = (format == nil or format == "") and "mermaid" or format
  if format ~= "mermaid" then
    vim.notify("todo.nvim: unknown export format " .. format .. " (images are saved from :RoadmapView)", vim.log.levels.ERROR)
    return
  end
  local ok, result = require("todo.viewer.mermaid").export()
  if ok then
    vim.notify("todo.nvim: wrote " .. result)
  else
    vim.notify("todo.nvim: " .. tostring(result), vim.log.levels.ERROR)
  end
end

return M
