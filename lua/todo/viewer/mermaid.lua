--- Mermaid export of the roadmap: a dependency flowchart and a gantt chart in one Markdown file.
--- Export only; deps.txt and the milestone files stay the source of truth.
local M = {}

--- Mermaid-safe node id: milestone ids start with digits and contain `-`.
---@param id string
---@return string
function M.node_id(id)
  return "m" .. id:gsub("[^%w]", "_")
end

--- Flowchart label inside double quotes.
local function flow_label(s)
  return (s:gsub("#", "#35;"):gsub('"', "#quot;"):gsub("<", "#lt;"):gsub(">", "#gt;"):gsub("[\r\n]", " "))
end

--- Gantt task name: `:` ends the name and `#`/`;` break the line, so swap them for full-width forms.
local function gantt_label(s)
  return (s:gsub(":", "："):gsub("#", "＃"):gsub(";", "；"):gsub("[\r\n]", " "))
end

---@param model table result of graph.analyze / graph.load
---@return string[]
function M.flowchart(model)
  local lines = { "flowchart LR" }
  for _, node in ipairs(model.nodes) do
    lines[#lines + 1] = ('  %s["%s"]'):format(M.node_id(node.id), flow_label(node.title))
  end
  for _, edge in ipairs(model.edges) do
    lines[#lines + 1] = ("  %s --> %s"):format(M.node_id(edge.from), M.node_id(edge.to))
  end
  local done, critical = {}, {}
  for _, node in ipairs(model.nodes) do
    if node.done then
      done[#done + 1] = M.node_id(node.id)
    elseif node.critical then
      critical[#critical + 1] = M.node_id(node.id)
    end
  end
  lines[#lines + 1] = "  classDef done fill:#e5e5e5,stroke:#999,color:#777"
  lines[#lines + 1] = "  classDef crit stroke:#d33,stroke-width:2px"
  if #done > 0 then
    lines[#lines + 1] = "  class " .. table.concat(done, ",") .. " done"
  end
  if #critical > 0 then
    lines[#lines + 1] = "  class " .. table.concat(critical, ",") .. " crit"
  end
  return lines
end

--- Gantt with explicit dates so Mermaid draws exactly the Due/Duration of the files.
---@param model table
---@return string[]
function M.gantt(model)
  local lines = { "gantt", "  dateFormat YYYY-MM-DD", "  axisFormat %m/%d", "  section Roadmap" }
  local by_id = {}
  for _, node in ipairs(model.nodes) do
    by_id[node.id] = node
  end
  local undated = {}
  for _, id in ipairs(model.order) do
    local node = by_id[id]
    if node.start and node.finish then
      local tags = {}
      if node.done then
        tags[#tags + 1] = "done"
      elseif node.critical then
        tags[#tags + 1] = "crit"
      end
      if node.sub_day or node.start == node.finish then
        tags[#tags + 1] = "milestone"
        tags[#tags + 1] = M.node_id(node.id)
        tags[#tags + 1] = node.finish
        tags[#tags + 1] = "0d"
      else
        tags[#tags + 1] = M.node_id(node.id)
        tags[#tags + 1] = node.start
        tags[#tags + 1] = node.finish
      end
      lines[#lines + 1] = ("  %s :%s"):format(gantt_label(node.title), table.concat(tags, ", "))
    else
      undated[#undated + 1] = node.title
    end
  end
  if #undated > 0 then
    lines[#lines + 1] = "  %% No valid Due: " .. table.concat(undated, ", ")
  end
  return lines
end

--- Markdown document with both diagrams; warnings become Mermaid comments.
---@param model table
---@return string
function M.render(model)
  local out = { "# Roadmap", "", "```mermaid" }
  vim.list_extend(out, M.flowchart(model))
  for _, w in ipairs(model.warnings) do
    out[#out + 1] = "  %% warning: " .. w.message:gsub("[\r\n]", " ")
  end
  vim.list_extend(out, { "```", "", "```mermaid" })
  vim.list_extend(out, M.gantt(model))
  vim.list_extend(out, { "```", "" })
  return table.concat(out, "\n")
end

--- Write export/roadmap.md from the files on disk.
---@return boolean ok, string path_or_err
function M.export()
  local graph = require("todo.viewer.graph")
  local path = vim.fs.normalize(graph.export_dir() .. "/roadmap.md")
  local ok, err = require("todo.viewer.fsutil").write_atomic(path, M.render(graph.load()))
  if not ok then
    return false, err or ("Cannot write " .. path)
  end
  return true, path
end

return M
