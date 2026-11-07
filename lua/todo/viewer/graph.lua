--- Milestone dependencies (roadmap/deps.txt) and the schedule computed from milestone files.
---
--- deps.txt holds one dependency per line, `<predecessor id> -> <successor id>`, where an id is a
--- milestone file name without extension. `#` starts a comment. Successors are never stored: they
--- are derived from the predecessor lines.
local config = require("todo.config")
local fsutil = require("todo.viewer.fsutil")

local M = {}

M.HEADER = "# Milestone dependencies: <predecessor id> -> <successor id>"

---@class RoadmapEdge
---@field from string predecessor id
---@field to string successor id

---@class RoadmapWarning
---@field kind "invalid"|"missing"|"self"|"duplicate"|"cycle"|"schedule"|"undated"
---@field message string
---@field ids string[]

--- Absolute path of the dependency file.
---@return string
function M.deps_path()
  return vim.fs.normalize(config.dir("roadmap") .. "/" .. config.options.deps_file)
end

--- Absolute path of the export directory.
---@return string
function M.export_dir()
  return vim.fs.normalize(config.dir("roadmap") .. "/" .. config.options.export_dir)
end

local function trim(s)
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

--- Parse deps.txt text. Self references and duplicates are dropped with a warning.
---@param text string
---@return RoadmapEdge[] edges, RoadmapWarning[] warnings
function M.parse_deps(text)
  local edges, warnings, seen = {}, {}, {}
  text = text:gsub("^\239\187\191", "") -- UTF-8 BOM
  local n = 0
  for line in (text .. "\n"):gmatch("([^\n]*)\n") do
    n = n + 1
    line = trim((line:gsub("\r$", ""):gsub("#.*$", "")))
    if line ~= "" then
      local from, to = line:match("^(%S+)%s*%->%s*(%S+)$")
      if not from then
        warnings[#warnings + 1] = { kind = "invalid", message = ("deps line %d is not `a -> b`: %s"):format(n, line), ids = {} }
      elseif from == to then
        warnings[#warnings + 1] = { kind = "self", message = from .. " depends on itself", ids = { from } }
      elseif seen[from .. "\0" .. to] then
        warnings[#warnings + 1] = { kind = "duplicate", message = from .. " -> " .. to .. " is listed twice", ids = { from, to } }
      else
        seen[from .. "\0" .. to] = true
        edges[#edges + 1] = { from = from, to = to }
      end
    end
  end
  return edges, warnings
end

--- deps.txt text for edges (order kept, duplicates and self references dropped).
---@param edges RoadmapEdge[]
---@return string
function M.format_deps(edges)
  local lines, seen = { M.HEADER }, {}
  for _, e in ipairs(edges) do
    local key = e.from .. "\0" .. e.to
    if e.from ~= e.to and not seen[key] then
      seen[key] = true
      lines[#lines + 1] = e.from .. " -> " .. e.to
    end
  end
  return table.concat(lines, "\n") .. "\n"
end

---@return string|nil text, nil when the file does not exist
function M.read_deps_text()
  return fsutil.read(M.deps_path())
end

---@return RoadmapEdge[] edges, RoadmapWarning[] warnings
function M.read_deps()
  return M.parse_deps(M.read_deps_text() or "")
end

---@param edges RoadmapEdge[]
---@return boolean ok, string|nil err
function M.write_deps(edges)
  return fsutil.write_atomic(M.deps_path(), M.format_deps(edges))
end

--- Version of the dependency file, used to detect concurrent edits.
---@return string
function M.deps_version()
  local text = M.read_deps_text()
  return text and vim.fn.sha256(text) or "none"
end

-- Dates ---------------------------------------------------------------------

--- Parse "YYYY-MM-DD" into a normalized date string, or nil if it is not a real date.
---@param s string|nil
---@return string|nil
function M.parse_date(s)
  local y, m, d = (s or ""):match("^%s*(%d%d%d%d)%-(%d%d)%-(%d%d)%s*$")
  if not y then
    return nil
  end
  y, m, d = tonumber(y), tonumber(m), tonumber(d)
  local t = os.date("*t", os.time({ year = y, month = m, day = d, hour = 12 }))
  if t.year ~= y or t.month ~= m or t.day ~= d then
    return nil
  end
  return ("%04d-%02d-%02d"):format(y, m, d)
end

--- Parse a Duration such as "30m", "2h", "1d", "2w", "1M". `m` is minutes, `M` is months.
---@param s string|nil
---@return { n: integer, unit: "m"|"h"|"d"|"w"|"M" }|nil
function M.parse_duration(s)
  local n, unit = (s or ""):match("^%s*(%d+)%s*([mhdwM])%s*$")
  if not n then
    return nil
  end
  return { n = tonumber(n), unit = unit }
end

--- date minus duration. Months go back by calendar month and clamp the day (03-31 - 1M = 02-28).
--- Sub-day durations (m, h) start on the due date itself.
---@param date string YYYY-MM-DD
---@param dur { n: integer, unit: string }
---@return string
function M.subtract(date, dur)
  local y, m, d = date:match("^(%d+)%-(%d+)%-(%d+)$")
  y, m, d = tonumber(y), tonumber(m), tonumber(d)
  if dur.unit == "M" then
    local last = os.date("*t", os.time({ year = y, month = m - dur.n + 1, day = 0, hour = 12 })).day
    local t = os.date("*t", os.time({ year = y, month = m - dur.n, day = 1, hour = 12 }))
    return ("%04d-%02d-%02d"):format(t.year, t.month, math.min(d, last))
  end
  local days = dur.unit == "w" and dur.n * 7 or dur.unit == "d" and dur.n or 0
  return os.date("%Y-%m-%d", os.time({ year = y, month = m, day = d - days, hour = 12 }))
end

-- Graph ---------------------------------------------------------------------

--- Ids in dependency order (Kahn). Among milestones that are ready at the same time, the one that
--- sorts first by `key` (default: the id) comes first. Ids left over are on or behind a cycle.
---@param ids string[]
---@param edges RoadmapEdge[]
---@param key? fun(id: string): string
---@return string[] order, string[] cyclic
function M.toposort(ids, edges, key)
  key = key or function(id) return id end
  local indeg, out, known = {}, {}, {}
  for _, id in ipairs(ids) do
    indeg[id], out[id], known[id] = 0, {}, true
  end
  for _, e in ipairs(edges) do
    if known[e.from] and known[e.to] then
      indeg[e.to] = indeg[e.to] + 1
      table.insert(out[e.from], e.to)
    end
  end
  local ready, order = {}, {}
  for _, id in ipairs(ids) do
    if indeg[id] == 0 then
      ready[#ready + 1] = id
    end
  end
  while #ready > 0 do
    local best = 1
    for i = 2, #ready do
      local a, b = key(ready[i]), key(ready[best])
      if a < b or (a == b and ready[i] < ready[best]) then
        best = i
      end
    end
    local id = table.remove(ready, best)
    order[#order + 1] = id
    for _, to in ipairs(out[id]) do
      indeg[to] = indeg[to] - 1
      if indeg[to] == 0 then
        ready[#ready + 1] = to
      end
    end
  end
  local cyclic = {}
  for _, id in ipairs(ids) do
    if indeg[id] > 0 then
      cyclic[#cyclic + 1] = id
    end
  end
  return order, cyclic
end

--- Whether adding from -> to would close a cycle (to already reaches from).
---@param edges RoadmapEdge[]
---@param from string
---@param to string
---@return boolean
function M.would_cycle(edges, from, to)
  if from == to then
    return true
  end
  local out = {}
  for _, e in ipairs(edges) do
    out[e.from] = out[e.from] or {}
    table.insert(out[e.from], e.to)
  end
  local stack, seen = { to }, { [to] = true }
  while #stack > 0 do
    local id = table.remove(stack)
    if id == from then
      return true
    end
    for _, next_id in ipairs(out[id] or {}) do
      if not seen[next_id] then
        seen[next_id] = true
        stack[#stack + 1] = next_id
      end
    end
  end
  return false
end

--- Check edges sent by a client before saving: well-formed, no self reference, no cycle.
--- Unknown ids are allowed (they are reported as warnings when loading).
---@param edges any
---@return boolean ok, string|nil err
function M.validate(edges)
  if type(edges) ~= "table" then
    return false, "edges must be a list"
  end
  local clean = {}
  for i, e in ipairs(edges) do
    if type(e) ~= "table" or type(e.from) ~= "string" or type(e.to) ~= "string"
      or not e.from:match("^[^%s#]+$") or not e.to:match("^[^%s#]+$") or e.from:find("->", 1, true) or e.to:find("->", 1, true) then
      return false, ("edge %d is invalid"):format(i)
    end
    if M.would_cycle(clean, e.from, e.to) then
      return false, ("%s -> %s creates a cycle"):format(e.from, e.to)
    end
    clean[#clean + 1] = { from = e.from, to = e.to }
  end
  return true
end

-- Model ---------------------------------------------------------------------

---@class RoadmapNode
---@field id string
---@field title string
---@field path string
---@field done boolean
---@field due string|nil
---@field duration string
---@field start string|nil
---@field finish string|nil
---@field sub_day boolean true for durations in minutes/hours
---@field critical boolean

--- Build nodes from milestone records as returned by store.scan.
---@param items { id: string, label: string, path: string, done: boolean, meta: table<string, string> }[]
---@return RoadmapNode[]
function M.nodes_from(items)
  local nodes = {}
  for _, item in ipairs(items) do
    local due = M.parse_date(item.meta.Due)
    local dur = M.parse_duration(item.meta.Duration)
    nodes[#nodes + 1] = {
      id = item.id,
      title = item.label,
      path = item.path,
      done = item.done,
      due = due,
      duration = item.meta.Duration or "",
      start = due and (dur and M.subtract(due, dur) or due) or nil,
      finish = due,
      sub_day = dur ~= nil and (dur.unit == "m" or dur.unit == "h"),
      critical = false,
    }
  end
  return nodes
end

--- Compute warnings, dependency order and the critical path.
--- The critical path is the chain that drives the latest finish: from the milestone that finishes
--- last, repeatedly step to the predecessor that finishes last.
---@param nodes RoadmapNode[]
---@param edges RoadmapEdge[]
---@param warnings? RoadmapWarning[]
---@return { nodes: RoadmapNode[], edges: (RoadmapEdge|{ critical: boolean, violated: boolean })[], order: string[], warnings: RoadmapWarning[] }
function M.analyze(nodes, edges, warnings)
  warnings = vim.deepcopy(warnings or {})
  local by_id, ids = {}, {}
  for _, node in ipairs(nodes) do
    by_id[node.id] = node
    ids[#ids + 1] = node.id
    if not node.due then
      warnings[#warnings + 1] = { kind = "undated", message = node.title .. " has no valid Due", ids = { node.id } }
    end
  end

  local out_edges, preds = {}, {}
  for _, e in ipairs(edges) do
    local missing = {}
    for _, id in ipairs({ e.from, e.to }) do
      if not by_id[id] then
        missing[#missing + 1] = id
      end
    end
    if #missing > 0 then
      warnings[#warnings + 1] = {
        kind = "missing",
        message = ("%s -> %s refers to an unknown milestone: %s"):format(e.from, e.to, table.concat(missing, ", ")),
        ids = { e.from, e.to },
      }
    else
      local edge = { from = e.from, to = e.to, critical = false, violated = false }
      local a, b = by_id[e.from], by_id[e.to]
      if a.finish and b.start and b.start < a.finish then
        edge.violated = true
        warnings[#warnings + 1] = {
          kind = "schedule",
          message = ("%s starts %s, before %s is due %s"):format(b.title, b.start, a.title, a.finish),
          ids = { e.from, e.to },
        }
      end
      out_edges[#out_edges + 1] = edge
      preds[e.to] = preds[e.to] or {}
      table.insert(preds[e.to], edge)
    end
  end

  -- Dependency order first, then by start date; undated milestones go last.
  local order, cyclic = M.toposort(ids, out_edges, function(id)
    return (by_id[id].start or "9999-99-99") .. "\0" .. id
  end)
  if #cyclic > 0 then
    warnings[#warnings + 1] = { kind = "cycle", message = "Dependency cycle among: " .. table.concat(cyclic, ", "), ids = cyclic }
    vim.list_extend(order, cyclic)
  else
    local last
    for _, node in ipairs(nodes) do
      if node.finish and (not last or node.finish > last.finish) then
        last = node
      end
    end
    local node = last
    while node do
      node.critical = true
      local best
      for _, edge in ipairs(preds[node.id] or {}) do
        local p = by_id[edge.from]
        if p.finish and (not best or p.finish > by_id[best.from].finish) then
          best = edge
        end
      end
      if best then
        best.critical = true
        node = by_id[best.from]
      else
        node = nil
      end
    end
  end

  return { nodes = nodes, edges = out_edges, order = order, warnings = warnings }
end

--- Load milestones (open and done) and dependencies from disk and analyze them.
function M.load()
  local store = require("todo.store")
  local items = store.scan("roadmap")
  vim.list_extend(items, store.scan("roadmap", true))
  local edges, warnings = M.read_deps()
  local model = M.analyze(M.nodes_from(items), edges, warnings)
  model.deps_version = M.deps_version()
  return model
end

return M
