local config = require("todo.config")
local creator = require("todo.creator")

local M = {}

--- Setup todo.nvim
---@param opts? TodoConfig
function M.setup(opts)
  config.setup(opts)
end

--- Create a new todo
---@param opts? table
---@return string Filepath of the newly created todo
function M.create(opts)
  return creator.create_task(opts)
end

-- Backward compatibility with my_task
M.create_task = M.create

--- Create a new roadmap milestone
---@param opts? table
---@return string Filepath of the newly created milestone
function M.create_roadmap(opts)
  return creator.create_task(vim.tbl_extend("force", opts or {}, { kind = "roadmap" }))
end

--- Open the daily todo list in a right-hand pane.
function M.list()
  require("todo.list").open("daily")
end

--- Open the roadmap view (milestones with their linked todos) in a right-hand pane.
function M.roadmap()
  require("todo.list").open("roadmap")
end

--- Parse todo buffer lines into metadata and memo
--- A known section heading on its own line starts the next field.
---@param lines string[]
---@return { meta: table<string, string>, memo: string }
function M.parse(lines)
  local meta, memo = {}, {}
  local section, pending = nil, false
  local keys = { ["Title"] = true, ["Memo"] = true, ["Due"] = true, ["Duration"] = true, ["Roadmap"] = true }

  for _, line in ipairs(lines) do
    local heading = line:match("^%s*%[(.-)%]%s*$")
    if heading and keys[heading] then
      section = heading
      pending = section ~= "Memo"
      if section ~= "Memo" then
        meta[section] = ""
      end
    elseif section == "Memo" then
      memo[#memo + 1] = line
    elseif pending then
      meta[section] = vim.trim(line)
      pending = false
    end
  end

  return { meta = meta, memo = table.concat(memo, "\n") }
end

return M
