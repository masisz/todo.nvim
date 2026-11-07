local h = require("helpers")
local graph = require("todo.viewer.graph")

h.test("parse_deps reads edges, comments, CRLF and BOM", function()
  local edges, warnings = graph.parse_deps("\239\187\191# header\r\na -> b\r\n\r\nb->c  # note\r\n")
  h.eq({ { from = "a", to = "b" }, { from = "b", to = "c" } }, edges)
  h.eq(0, #warnings)
end)

h.test("parse_deps warns on invalid, self and duplicate lines", function()
  local edges, warnings = graph.parse_deps("a -> b\na -> b\nc -> c\nnot an edge\n")
  h.eq(1, #edges)
  local kinds = vim.tbl_map(function(w) return w.kind end, warnings)
  table.sort(kinds)
  h.eq({ "duplicate", "invalid", "self" }, kinds)
end)

h.test("format_deps round-trips and drops duplicates", function()
  local text = graph.format_deps({ { from = "a", to = "b" }, { from = "a", to = "b" }, { from = "x", to = "x" } })
  h.eq(graph.HEADER .. "\na -> b\n", text)
  h.eq({ { from = "a", to = "b" } }, (graph.parse_deps(text)))
end)

h.test("parse_date validates real dates", function()
  h.eq("2026-02-28", graph.parse_date(" 2026-02-28 "))
  h.eq(nil, graph.parse_date("2026-02-30"))
  h.eq(nil, graph.parse_date("2026/02/01"))
  h.eq(nil, graph.parse_date(nil))
end)

h.test("parse_duration distinguishes minutes and months", function()
  h.eq({ n = 30, unit = "m" }, graph.parse_duration("30m"))
  h.eq({ n = 3, unit = "M" }, graph.parse_duration("3M"))
  h.eq(nil, graph.parse_duration("1y"))
end)

h.test("subtract handles days, weeks, months and clamps month ends", function()
  h.eq("2026-11-30", graph.subtract("2026-12-01", { n = 1, unit = "d" }))
  h.eq("2026-11-17", graph.subtract("2026-12-01", { n = 2, unit = "w" }))
  h.eq("2026-02-28", graph.subtract("2026-03-31", { n = 1, unit = "M" }))
  h.eq("2025-12-15", graph.subtract("2026-03-15", { n = 3, unit = "M" }))
  h.eq("2026-12-01", graph.subtract("2026-12-01", { n = 2, unit = "h" }))
end)

h.test("toposort orders and reports cycles", function()
  local order, cyclic = graph.toposort({ "c", "b", "a" }, { { from = "a", to = "b" }, { from = "b", to = "c" } })
  h.eq({ "a", "b", "c" }, order)
  h.eq({}, cyclic)
  local by_start = { a = "2026-03-01", b = "2026-01-01", c = "2026-02-01" }
  h.eq({ "b", "c", "a" }, (graph.toposort({ "a", "b", "c" }, {}, function(id) return by_start[id] end)))
  h.eq({ "c", "a", "b" }, (graph.toposort({ "a", "b", "c" }, { { from = "a", to = "b" } }, function(id) return by_start[id] end)))
  local _, cyc = graph.toposort({ "a", "b", "z" }, { { from = "a", to = "b" }, { from = "b", to = "a" } })
  h.eq({ "a", "b" }, cyc)
end)

h.test("would_cycle and validate reject cycles", function()
  local edges = { { from = "a", to = "b" }, { from = "b", to = "c" } }
  h.ok(graph.would_cycle(edges, "c", "a"))
  h.ok(not graph.would_cycle(edges, "a", "c"))
  h.ok(graph.would_cycle(edges, "a", "a"))
  h.ok(graph.validate(edges))
  h.ok(not graph.validate({ { from = "a", to = "b" }, { from = "b", to = "a" } }))
  h.ok(not graph.validate({ { from = "a b", to = "c" } }))
  h.ok(not graph.validate({ { from = "a", to = 1 } }))
  h.ok(not graph.validate("x"))
end)

h.test("load computes schedule, warnings and critical path", function()
  h.fixture({
    ["20261101-01"] = { title = "Design", due = "2026-11-30", duration = "1M" },
    ["20261101-02"] = { title = "Impl", due = "2026-12-31", duration = "1M" },
    ["20261101-03"] = { title = "Docs", due = "2026-12-10", duration = "2w" },
    ["20261101-04"] = { title = "Undated", due = "", duration = "1d" },
    ["20261001-01"] = { title = "Research", due = "2026-11-10", duration = "2w", done = true },
  })
  graph.write_deps({
    { from = "20261001-01", to = "20261101-01" },
    { from = "20261101-01", to = "20261101-02" },
    { from = "20261101-01", to = "20261101-03" },
    { from = "20261101-03", to = "gone" },
  })
  local model = graph.load()
  local by = {}
  for _, n in ipairs(model.nodes) do by[n.id] = n end
  h.eq("2026-10-30", by["20261101-01"].start)
  h.eq(true, by["20261001-01"].done)
  h.eq(true, by["20261101-02"].critical)
  h.eq(true, by["20261101-01"].critical)
  h.eq(false, by["20261101-03"].critical)
  -- Design starts 10-30, before Research is due 11-10.
  local kinds = {}
  for _, w in ipairs(model.warnings) do kinds[w.kind] = (kinds[w.kind] or 0) + 1 end
  h.eq({ schedule = 2, missing = 1, undated = 1 }, kinds) -- Docs starts 11-26 < Design due 11-30
  h.eq(3, #model.edges)
  h.ok(model.deps_version ~= "none")
  local pos = {}
  for i, id in ipairs(model.order) do pos[id] = i end
  h.ok(pos["20261001-01"] < pos["20261101-01"] and pos["20261101-01"] < pos["20261101-02"])
end)

h.test("analyze reports a cycle and skips the critical path", function()
  local nodes = graph.nodes_from({
    { id = "a", label = "A", path = "a", done = false, meta = { Due = "2026-01-10", Duration = "1d" } },
    { id = "b", label = "B", path = "b", done = false, meta = { Due = "2026-01-20", Duration = "1d" } },
  })
  local model = graph.analyze(nodes, { { from = "a", to = "b" }, { from = "b", to = "a" } })
  h.eq("cycle", model.warnings[#model.warnings].kind)
  h.eq(2, #model.order)
  h.ok(not model.nodes[1].critical and not model.nodes[2].critical)
end)
