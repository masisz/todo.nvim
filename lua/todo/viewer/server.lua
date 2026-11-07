--- Local HTTP server for the roadmap viewer (assets/roadmap.html).
---
--- Listens on 127.0.0.1 only. Every /api request needs the per-start token in the X-Token header;
--- a custom header cannot be sent cross-origin without a CORS preflight, which this server never
--- grants, so other web pages cannot call the API. The Host header is checked against DNS rebinding.
local uv = vim.uv or vim.loop
local graph = require("todo.viewer.graph")
local fsutil = require("todo.viewer.fsutil")

local M = {}

M.MAX_BODY = 32 * 1024 * 1024

--- Files the viewer may write into the export directory.
M.EXPORTS = {
  ["graph.png"] = true,
  ["graph.svg"] = true,
  ["gantt.png"] = true,
  ["gantt.svg"] = true,
  ["roadmap.png"] = true,
  ["roadmap.svg"] = true,
}

---@type { tcp: userdata, port: integer, token: string }|nil
M.state = nil

local STATUS = {
  [200] = "OK",
  [400] = "Bad Request",
  [403] = "Forbidden",
  [404] = "Not Found",
  [405] = "Method Not Allowed",
  [409] = "Conflict",
  [413] = "Payload Too Large",
  [500] = "Internal Server Error",
}

local function random_token()
  local ok, bytes = pcall(uv.random, 16)
  if not ok or type(bytes) ~= "string" then
    math.randomseed(uv.hrtime())
    local t = {}
    for i = 1, 16 do
      t[i] = string.char(math.random(0, 255))
    end
    bytes = table.concat(t)
  end
  return (bytes:gsub(".", function(c) return ("%02x"):format(c:byte()) end))
end

--- Path of the bundled viewer page.
---@return string|nil
function M.asset_path()
  local found = vim.api.nvim_get_runtime_file("assets/roadmap.html", false)[1]
  if found then
    return found
  end
  -- Fallback when the plugin is not on 'runtimepath' (e.g. tests): <plugin>/lua/todo/viewer/server.lua
  local here = debug.getinfo(1, "S").source:sub(2)
  local candidate = vim.fs.normalize(vim.fn.fnamemodify(here, ":h:h:h:h") .. "/assets/roadmap.html")
  return vim.fn.filereadable(candidate) == 1 and candidate or nil
end

--- Parse a complete HTTP request out of buffered data.
---@param data string
---@return table|nil request, string|nil err  nil, nil means "need more data"
function M.parse_request(data)
  local head_end = data:find("\r\n\r\n", 1, true)
  if not head_end then
    if #data > 64 * 1024 then
      return nil, "headers too large"
    end
    return nil
  end
  local head = data:sub(1, head_end - 1)
  local method, target = head:match("^(%u+) (%S+) HTTP/1%.[01]")
  if not method then
    return nil, "bad request line"
  end
  local headers = {}
  for name, value in head:gmatch("\r\n([^:\r\n]+):%s*([^\r\n]*)") do
    headers[name:lower()] = value
  end
  local length = tonumber(headers["content-length"] or "0")
  if not length or length < 0 then
    return nil, "bad content-length"
  end
  if length > M.MAX_BODY then
    return nil, "too large"
  end
  local body_start = head_end + 4
  if #data < body_start + length - 1 then
    return nil
  end
  local path, query = target:match("^([^?]*)%??(.*)$")
  return {
    method = method,
    path = path,
    query = query,
    headers = headers,
    body = data:sub(body_start, body_start + length - 1),
  }
end

local function response(status, body, content_type, extra)
  body = body or ""
  local lines = {
    ("HTTP/1.1 %d %s"):format(status, STATUS[status] or "Status"),
    "Content-Type: " .. (content_type or "application/json; charset=utf-8"),
    "Content-Length: " .. #body,
    "Cache-Control: no-store",
    "X-Content-Type-Options: nosniff",
    "Connection: close",
  }
  for _, h in ipairs(extra or {}) do
    lines[#lines + 1] = h
  end
  return table.concat(lines, "\r\n") .. "\r\n\r\n" .. body
end

local function json(status, value)
  return response(status, vim.json.encode(value))
end

local function err(status, message)
  return json(status, { error = message })
end

--- Version over the roadmap folder, for the viewer to notice external edits.
---@return string
function M.version()
  local config = require("todo.config")
  local parts = {}
  for _, dir in ipairs({ config.dir("roadmap"), config.dir("roadmap") .. "/done" }) do
    if vim.fn.isdirectory(dir) == 1 then
      for name, kind in vim.fs.dir(dir) do
        if kind == "file" then
          local stat = uv.fs_stat(dir .. "/" .. name)
          if stat then
            parts[#parts + 1] = ("%s/%s:%d:%d:%d"):format(dir, name, stat.size, stat.mtime.sec, stat.mtime.nsec or 0)
          end
        end
      end
    end
  end
  table.sort(parts)
  -- Unsaved milestone buffers are part of the model too (store.read_lines prefers buffers).
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].modified then
      parts[#parts + 1] = ("buf%d:%d"):format(buf, vim.api.nvim_buf_get_changedtick(buf))
    end
  end
  return vim.fn.sha256(table.concat(parts, "\n"))
end

--- Handle a parsed request; returns the raw HTTP response.
---@param req table
---@param token string
---@param port integer
---@return string
function M.handle(req, token, port)
  local host = req.headers["host"]
  if host ~= "127.0.0.1:" .. port and host ~= "localhost:" .. port then
    return err(403, "bad host")
  end

  if req.path == "/" or req.path == "/index.html" then
    if req.method ~= "GET" then
      return err(405, "method not allowed")
    end
    local asset = M.asset_path()
    local html = asset and fsutil.read(asset)
    if not html then
      return err(500, "assets/roadmap.html not found")
    end
    return response(200, html, "text/html; charset=utf-8", { "Content-Security-Policy: default-src 'self'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; img-src 'self' data: blob:" })
  end

  if req.path:sub(1, 5) ~= "/api/" then
    return err(404, "not found")
  end
  if req.headers["x-token"] ~= token then
    return err(403, "bad token")
  end

  if req.path == "/api/roadmap" and req.method == "GET" then
    local model = graph.load()
    model.version = M.version()
    return json(200, model)
  end

  if req.path == "/api/version" and req.method == "GET" then
    return json(200, { version = M.version() })
  end

  if req.path == "/api/deps" and req.method == "PUT" then
    local ok, body = pcall(vim.json.decode, req.body)
    if not ok or type(body) ~= "table" then
      return err(400, "body must be JSON")
    end
    if body.deps_version ~= graph.deps_version() then
      return err(409, "deps.txt changed on disk; reload")
    end
    local valid, msg = graph.validate(body.edges)
    if not valid then
      return err(400, msg)
    end
    local written, write_err = graph.write_deps(body.edges)
    if not written then
      return err(500, write_err or "cannot write deps.txt")
    end
    return json(200, { deps_version = graph.deps_version() })
  end

  if req.path == "/api/export/mermaid" and req.method == "POST" then
    local ok, result = require("todo.viewer.mermaid").export()
    if not ok then
      return err(500, result)
    end
    return json(200, { path = result })
  end

  local name = req.path:match("^/api/export/([%w%.]+)$")
  if name then
    if req.method ~= "POST" then
      return err(405, "method not allowed")
    end
    if not M.EXPORTS[name] then
      return err(404, "unknown export " .. name)
    end
    local path = vim.fs.normalize(graph.export_dir() .. "/" .. name)
    local ok, write_err = fsutil.write_atomic(path, req.body)
    if not ok then
      return err(500, write_err or ("cannot write " .. path))
    end
    return json(200, { path = path })
  end

  return err(404, "not found")
end

local function on_connection(server, token, port)
  local client = uv.new_tcp()
  server:accept(client)
  local chunks, size, handled = {}, 0, false
  local function finish(raw)
    handled = true
    client:read_stop()
    client:write(raw, function()
      if not client:is_closing() then
        client:close()
      end
    end)
  end
  client:read_start(function(read_err, chunk)
    if handled then
      return
    end
    if read_err or not chunk then
      if not client:is_closing() then
        client:close()
      end
      return
    end
    chunks[#chunks + 1] = chunk
    size = size + #chunk
    if size > M.MAX_BODY + 64 * 1024 then
      return finish(err(413, "too large"))
    end
    local data = table.concat(chunks)
    chunks = { data }
    local req, parse_err = M.parse_request(data)
    if parse_err then
      return finish(err(parse_err == "too large" and 413 or 400, parse_err))
    end
    if req then
      handled = true
      client:read_stop()
      -- libuv callbacks run in a fast event context where most of vim.api/vim.fn is unavailable.
      vim.schedule(function()
        local ok, raw = pcall(M.handle, req, token, port)
        if not ok then
          raw = err(500, tostring(raw))
        end
        client:write(raw, function()
          if not client:is_closing() then
            client:close()
          end
        end)
      end)
    end
  end)
end

--- Start the server (or reuse the running one).
---@return string|nil url, string|nil err
function M.start()
  if M.state then
    return M.url()
  end
  local tcp = uv.new_tcp()
  local ok, bind_err = tcp:bind("127.0.0.1", 0)
  if not ok then
    tcp:close()
    return nil, bind_err
  end
  local port = tcp:getsockname().port
  local token = random_token()
  local listening, listen_err = tcp:listen(16, function(listen_cb_err)
    if not listen_cb_err then
      on_connection(tcp, token, port)
    end
  end)
  if not listening then
    tcp:close()
    return nil, listen_err
  end
  M.state = { tcp = tcp, port = port, token = token }
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = vim.api.nvim_create_augroup("TodoRoadmapViewer", { clear = true }),
    callback = function() M.stop() end,
  })
  return M.url()
end

---@return string|nil
function M.url()
  if not M.state then
    return nil
  end
  -- The token travels in the fragment so it is never sent in a request line or a Referer.
  return ("http://127.0.0.1:%d/#token=%s"):format(M.state.port, M.state.token)
end

function M.stop()
  if M.state then
    if not M.state.tcp:is_closing() then
      M.state.tcp:close()
    end
    M.state = nil
  end
end

return M
