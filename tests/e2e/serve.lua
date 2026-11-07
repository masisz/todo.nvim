-- Start the viewer server on a fixture roadmap for browser tests.
-- nvim -l tests/e2e/serve.lua <todo dir> <url file>
-- Writes the viewer URL to <url file> and keeps serving until <url file>.stop exists.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h:h")
vim.opt.runtimepath:prepend(root)
package.path = root .. "/lua/?.lua;" .. root .. "/lua/?/init.lua;" .. package.path
vim.uv = vim.uv or vim.loop
if not vim.fs.joinpath then
  vim.fs.joinpath = function(...) return (table.concat({ ... }, "/"):gsub("//+", "/")) end
end

local dir, url_file = _G.arg[1], _G.arg[2]
require("todo.config").setup({ directory = dir })
local url = assert(require("todo.viewer.server").start())
vim.fn.writefile({ url }, url_file)
vim.wait(10 * 60 * 1000, function() return vim.fn.filereadable(url_file .. ".stop") == 1 end, 100)
