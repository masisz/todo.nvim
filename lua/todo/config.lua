local M = {}

---@class TodoConfig
---@field directory string Root directory for todo files (default: "~/todos")
---@field daily_dir string Subdirectory for daily todos (default: "daily"; "" uses `directory` itself)
---@field roadmap_dir string Subdirectory for roadmap milestones (default: "roadmap")
---@field extension string File extension for todo files (default: "todo")
---@field date_format string Date format for filename prefix (default: "%Y%m%d")
---@field template (string|fun():string)[] Template lines for new daily todos
---@field roadmap_template (string|fun():string)[] Template lines for new roadmap milestones
---@field cursor_pos number[] Initial cursor position [line, col] (1-indexed, default: { 2, 0 })
---@field start_insert boolean Whether to start in insert mode (default: true)

local function today()
  return os.date("%Y-%m-%d")
end

---@type TodoConfig
M.defaults = {
  directory = "~/todos",
  daily_dir = "daily",
  roadmap_dir = "roadmap",
  extension = "todo",
  date_format = "%Y%m%d",
  template = {
    "[Title]",
    "",
    "[Memo]",
    "",
    "[Due]",
    today,
    "[Duration]",
    "30m",
    "[Roadmap]",
    "",
  },
  roadmap_template = {
    "[Title]",
    "",
    "[Memo]",
    "",
    "[Due]",
    today,
    "[Duration]",
    "1M",
  },
  cursor_pos = { 2, 0 },
  start_insert = true,
}

---@type TodoConfig
M.options = vim.deepcopy(M.defaults)

---@param opts? TodoConfig
function M.setup(opts)
  opts = opts or {}
  M.options = vim.tbl_deep_extend("force", M.defaults, opts)
  -- Templates are lists: replace them as a whole instead of merging by index.
  for _, key in ipairs({ "template", "roadmap_template", "cursor_pos" }) do
    if opts[key] then
      M.options[key] = vim.deepcopy(opts[key])
    end
  end
end

--- Root todo directory as an absolute path without a trailing slash.
---@return string
function M.root()
  return vim.fs.normalize(vim.fn.fnamemodify(vim.fn.expand(M.options.directory), ":p"))
end

--- Absolute directory for "daily" or "roadmap" todos.
---@param kind "daily"|"roadmap"
---@return string
function M.dir(kind)
  local root = vim.fn.fnamemodify(vim.fn.expand(M.options.directory), ":p")
  local sub = kind == "roadmap" and M.options.roadmap_dir or M.options.daily_dir
  if sub and sub ~= "" then
    root = vim.fs.joinpath(root, sub)
  end
  return vim.fs.normalize(root)
end

return M
