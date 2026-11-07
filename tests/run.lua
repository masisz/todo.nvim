-- Minimal test runner: nvim -l tests/run.lua [spec ...]
-- Runs tests/*_spec.lua (or the given files) and exits non-zero on failure.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.runtimepath:prepend(root)
package.path = root .. "/lua/?.lua;" .. root .. "/lua/?/init.lua;" .. root .. "/tests/?.lua;" .. package.path

-- Neovim 0.9 compatibility for running the suite on older CI images; the plugin targets 0.10+.
vim.uv = vim.uv or vim.loop
if not vim.fs.joinpath then
  vim.fs.joinpath = function(...) return (table.concat({ ... }, "/"):gsub("//+", "/")) end
end

local h = require("helpers")
local files = _G.arg and #_G.arg > 0 and _G.arg or vim.fn.glob(root .. "/tests/*_spec.lua", false, true)
for _, file in ipairs(files) do
  h.current_file = vim.fn.fnamemodify(file, ":t")
  dofile(file)
end
h.run()
