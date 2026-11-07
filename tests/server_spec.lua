local h = require("helpers")
local uv = vim.uv or vim.loop
local server = require("todo.viewer.server")
local graph = require("todo.viewer.graph")

--- Raw HTTP request to the running server; returns status, body.
local function request(method, path, opts)
  opts = opts or {}
  local headers = opts.headers or {}
  if headers.Host == nil then headers.Host = "127.0.0.1:" .. server.state.port end
  if headers["X-Token"] == nil then headers["X-Token"] = server.state.token end
  local body = opts.body or ""
  local lines = { ("%s %s HTTP/1.1"):format(method, path) }
  for k, v in pairs(headers) do
    if v ~= false then lines[#lines + 1] = k .. ": " .. v end
  end
  lines[#lines + 1] = "Content-Length: " .. #body
  local raw = table.concat(lines, "\r\n") .. "\r\n\r\n" .. body

  local client, chunks, done = uv.new_tcp(), {}, false
  client:connect("127.0.0.1", server.state.port, function(err)
    assert(not err, err)
    -- Send in two pieces to exercise buffering of partial requests.
    local cut = math.floor(#raw / 2)
    client:write(raw:sub(1, cut))
    client:write(raw:sub(cut + 1))
    client:read_start(function(_, chunk)
      if chunk then chunks[#chunks + 1] = chunk else done = true; client:close() end
    end)
  end)
  assert(vim.wait(5000, function() return done end, 10), "request timed out")
  local response = table.concat(chunks)
  local status = tonumber(response:match("^HTTP/1%.1 (%d+)"))
  return status, response:match("\r\n\r\n(.*)$"), response
end

local function setup()
  server.stop()
  local dir = h.fixture({
    ["20261101-01"] = { title = "Design", due = "2026-11-30", duration = "1M" },
    ["20261101-02"] = { title = "Impl", due = "2026-12-31", duration = "1M" },
  })
  assert(server.start())
  return dir
end

h.test("parse_request waits for the full body", function()
  h.eq(nil, (server.parse_request("GET / HTTP/1.1\r\nHost: x")))
  h.eq(nil, (server.parse_request("PUT /a HTTP/1.1\r\nContent-Length: 4\r\n\r\nab")))
  local req = server.parse_request("PUT /a?x=1 HTTP/1.1\r\nContent-Length: 4\r\nX-Token: t\r\n\r\nabcd")
  h.eq({ "PUT", "/a", "x=1", "abcd", "t" }, { req.method, req.path, req.query, req.body, req.headers["x-token"] })
  local _, err = server.parse_request("GET / HTTP/1.1\r\nContent-Length: 999999999999\r\n\r\n")
  h.eq("too large", err)
end)

h.test("start binds 127.0.0.1 and serves the viewer page", function()
  setup()
  h.ok(server.url():match("^http://127%.0%.0%.1:%d+/#token=%x+$"), server.url())
  local status, body = request("GET", "/", { headers = { ["X-Token"] = false } })
  h.eq(200, status)
  h.ok(body:find("<html", 1, true))
  h.eq(server.url(), (server.start()))
end)

h.test("api rejects missing token and foreign Host", function()
  setup()
  h.eq(403, (request("GET", "/api/roadmap", { headers = { ["X-Token"] = "wrong" } })))
  h.eq(403, (request("GET", "/api/roadmap", { headers = { ["X-Token"] = false } })))
  h.eq(403, (request("GET", "/", { headers = { Host = "evil.example:" .. server.state.port } })))
end)

h.test("roadmap and version endpoints return JSON", function()
  setup()
  local status, body = request("GET", "/api/roadmap")
  h.eq(200, status)
  local model = vim.json.decode(body)
  h.eq(2, #model.nodes)
  h.eq("none", model.deps_version)
  local _, v1 = request("GET", "/api/version")
  vim.fn.writefile({ "[Title]", "Changed" }, require("todo.config").dir("roadmap") .. "/20261101-01.todo")
  local _, v2 = request("GET", "/api/version")
  h.ok(vim.json.decode(v1).version ~= vim.json.decode(v2).version)
end)

h.test("PUT deps validates, writes and detects conflicts", function()
  setup()
  local edges = { { from = "20261101-01", to = "20261101-02" } }
  local status, body = request("PUT", "/api/deps", { body = vim.json.encode({ deps_version = "none", edges = edges }) })
  h.eq(200, status, body)
  h.eq(edges, (graph.read_deps()))
  local version = vim.json.decode(body).deps_version

  -- stale version
  h.eq(409, (request("PUT", "/api/deps", { body = vim.json.encode({ deps_version = "none", edges = {} }) })))
  -- cycle
  local cyc = { edges[1], { from = "20261101-02", to = "20261101-01" } }
  h.eq(400, (request("PUT", "/api/deps", { body = vim.json.encode({ deps_version = version, edges = cyc }) })))
  -- bad JSON
  h.eq(400, (request("PUT", "/api/deps", { body = "{" })))
  h.eq(edges, (graph.read_deps()))
end)

h.test("roadmap exposes unknown-id edges so viewer edits preserve them", function()
  setup()
  local edges = { { from = "20261101-01", to = "missing-id" } }
  assert(graph.write_deps(edges))
  local _, body = request("GET", "/api/roadmap")
  local model = vim.json.decode(body)
  h.eq(edges, model.raw_edges)
  local updated = model.raw_edges
  updated[#updated + 1] = { from = "20261101-01", to = "20261101-02" }
  h.eq(200, (request("PUT", "/api/deps", {
    body = vim.json.encode({ deps_version = model.deps_version, edges = updated }),
  })))
  h.eq(updated, (graph.read_deps()))
end)

h.test("export endpoints write whitelisted files only", function()
  local dir = setup()
  local png = "\137PNG\r\n\26\n\0binary\255"
  local status = request("POST", "/api/export/graph.png", { body = png })
  h.eq(200, status)
  h.eq(png, require("todo.viewer.fsutil").read(dir .. "/roadmap/export/graph.png"))
  h.eq(404, (request("POST", "/api/export/evil.sh", { body = "x" })))
  h.eq(404, (request("POST", "/api/export/..%2Fdeps.txt", { body = "x" })))
  h.eq(200, (request("POST", "/api/export/mermaid")))
  h.eq(1, vim.fn.filereadable(dir .. "/roadmap/export/roadmap.md"))
end)

h.test("stop closes the listener", function()
  setup()
  server.stop()
  h.eq(nil, server.state)
end)
