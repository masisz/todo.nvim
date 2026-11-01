local M = {}

---@class TodoConfig
---@field directory string Directory to store todo files (default: "~/todos")
---@field extension string File extension for todo files (default: "todo")
---@field date_format string Date format for filename prefix (default: "%Y%m%d")
---@field template (string|fun():string)[] Default template lines for new todos
---@field cursor_pos number[] Initial cursor position [line, col] (1-indexed, default: { 2, 0 })
---@field start_insert boolean Whether to start in insert mode (default: true)

---@type TodoConfig
M.defaults = {
  directory = "~/todos",
  extension = "todo",
  date_format = "%Y%m%d",
  template = {
    "[Title]",
    "",
    "[Memo]",
    "",
    "[Due]",
    function()
      return os.date("%Y-%m-%d")
    end,
    "[Duration]",
    "30m",
  },
  cursor_pos = { 2, 0 },
  start_insert = true,
}

---@type TodoConfig
M.options = vim.deepcopy(M.defaults)

---@param opts? TodoConfig
function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", M.defaults, opts or {})
end

return M
