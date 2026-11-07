local h = require("helpers")
local graph = require("todo.viewer.graph")
local mermaid = require("todo.viewer.mermaid")

local function model()
  local nodes = graph.nodes_from({
    { id = "20261101-01", label = 'Design "v1": UI #1', path = "", done = true, meta = { Due = "2026-11-30", Duration = "1M" } },
    { id = "20261101-02", label = "Impl <core>", path = "", done = false, meta = { Due = "2026-12-31", Duration = "1M" } },
    { id = "20261101-03", label = "Review", path = "", done = false, meta = { Due = "2026-12-31", Duration = "2h" } },
    { id = "20261101-04", label = "Someday", path = "", done = false, meta = { Due = "", Duration = "" } },
  })
  return graph.analyze(nodes, { { from = "20261101-01", to = "20261101-02" } })
end

h.test("node_id is mermaid-safe", function()
  h.eq("m20261101_01", mermaid.node_id("20261101-01"))
end)

h.test("flowchart has escaped labels, edges and classes", function()
  local text = table.concat(mermaid.flowchart(model()), "\n")
  h.ok(text:find('m20261101_01["Design #quot;v1#quot;: UI #35;1"]', 1, true), text)
  h.ok(text:find("m20261101_01 --> m20261101_02", 1, true), text)
  h.ok(text:find('m20261101_02["Impl #lt;core#gt;"]', 1, true), text)
  h.ok(text:find("class m20261101_01 done", 1, true), text)
end)

h.test("gantt uses explicit dates, milestones and escapes names", function()
  local text = table.concat(mermaid.gantt(model()), "\n")
  h.ok(text:find('Design "v1"： UI ＃1 :done, m20261101_01, 2026-10-30, 2026-11-30', 1, true), text)
  h.ok(text:find("Review :milestone, m20261101_03, 2026-12-31, 0d", 1, true), text)
  h.ok(text:find("%% No valid Due: Someday", 1, true), text)
  h.ok(not text:find("after", 1, true))
end)

h.test("render wraps both diagrams and writes export/roadmap.md", function()
  local doc = mermaid.render(model())
  local _, fences = doc:gsub("```mermaid", "")
  h.eq(2, fences)
  h.ok(doc:find("%% warning: Someday has no valid Due", 1, true), doc)

  local dir = h.fixture({ ["20261101-01"] = { title = "A", due = "2026-11-30", duration = "1d" } })
  local ok, path = mermaid.export()
  h.ok(ok, path)
  h.eq(vim.fs.normalize(dir .. "/roadmap/export/roadmap.md"), path)
  h.ok(vim.fn.readfile(path)[1] == "# Roadmap")
end)
