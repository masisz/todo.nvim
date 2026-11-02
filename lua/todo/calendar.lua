local M = {}

local function encode(value)
  return (value:gsub("[^%w%-._~]", function(char)
    return string.format("%%%02X", char:byte())
  end))
end

local function times(todo, start)
  local y, mo, d, h, mi = start:match("^(%d%d%d%d)%-(%d%d)%-(%d%d) (%d%d):(%d%d)$")
  if not y then
    return nil, "Use YYYY-MM-DD HH:MM for the start time"
  end
  local parts = { year = tonumber(y), month = tonumber(mo), day = tonumber(d), hour = tonumber(h), min = tonumber(mi), sec = 0 }
  local ok, timestamp = pcall(os.time, parts)
  if not ok or not timestamp or os.date("%Y-%m-%d %H:%M", timestamp) ~= start then
    return nil, "Invalid start date or time"
  end
  local duration = vim.trim(todo.meta.Duration or "")
  if duration == "" then duration = "30m" end
  local hours, minutes = duration:match("^(%d+)h%s*(%d+)m$")
  if not hours then
    hours = duration:match("^(%d+)h$")
    minutes = duration:match("^(%d+)m$")
  end
  local seconds = (tonumber(hours) or 0) * 3600 + (tonumber(minutes) or 0) * 60
  if seconds <= 0 then
    return nil, "Invalid duration; use 30m, 1h, or 1h30m"
  end
  return timestamp, timestamp + seconds
end

--- Build an event URL; provider is google, outlook, or outlook_work.
function M.url(todo, start, provider)
  local first, last = times(todo, start)
  if not first then return nil, last end
  if provider == "outlook" or provider == "outlook_work" then
    local host = provider == "outlook" and "outlook.live.com" or "outlook.office.com"
    return "https://" .. host .. "/calendar/0/deeplink/compose?path=%2Fcalendar%2Faction%2Fcompose&rru=addevent&subject="
      .. encode(todo.meta.Title or "") .. "&startdt=" .. encode(os.date("!%Y-%m-%dT%H:%M:%SZ", first))
      .. "&enddt=" .. encode(os.date("!%Y-%m-%dT%H:%M:%SZ", last)) .. "&body=" .. encode(todo.memo)
      .. "&freebusy=free"
  elseif provider and provider ~= "google" then
    return nil, "Unknown calendar provider: " .. tostring(provider)
  end
  local dates = os.date("!%Y%m%dT%H%M%SZ", first) .. "/" .. os.date("!%Y%m%dT%H%M%SZ", last)
  return "https://calendar.google.com/calendar/render?action=TEMPLATE&text="
    .. encode(todo.meta.Title or "") .. "&dates=" .. encode(dates)
    .. "&details=" .. encode(todo.memo)
end

local function escape(value)
  return (value:gsub("\\", "\\\\"):gsub("\r\n", "\n"):gsub("\r", "\n")
    :gsub("\n", "\\n"):gsub(";", "\\;"):gsub(",", "\\,"))
end

--- Serialize an RFC 5545 event with CRLF and UTF-8-safe line folding.
--- With opts.free, the event is marked as free time (TRANSP and Outlook's busy status).
function M.ics(todo, start, opts)
  opts = opts or {}
  local first, last = times(todo, start)
  if not first then return nil, last end
  local lines = {
    "BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//todo.nvim//Calendar//EN", "CALSCALE:GREGORIAN",
    "BEGIN:VEVENT", "UID:" .. vim.fn.sha256(vim.fn.tempname() .. tostring(vim.uv.hrtime())) .. "@todo.nvim",
    "DTSTAMP:" .. os.date("!%Y%m%dT%H%M%SZ"),
    "DTSTART:" .. os.date("!%Y%m%dT%H%M%SZ", first),
    "DTEND:" .. os.date("!%Y%m%dT%H%M%SZ", last),
    "SUMMARY:" .. escape(todo.meta.Title or ""), "DESCRIPTION:" .. escape(todo.memo),
  }
  if opts.free then
    vim.list_extend(lines, { "TRANSP:TRANSPARENT", "X-MICROSOFT-CDO-BUSYSTATUS:FREE" })
  end
  vim.list_extend(lines, { "END:VEVENT", "END:VCALENDAR" })
  local folded = {}
  for _, line in ipairs(lines) do
    while #line > 75 do
      local cut = 75
      while line:byte(cut + 1) >= 128 and line:byte(cut + 1) < 192 do cut = cut - 1 end
      folded[#folded + 1] = line:sub(1, cut)
      line = " " .. line:sub(cut + 1)
    end
    folded[#folded + 1] = line
  end
  return table.concat(folded, "\r\n") .. "\r\n"
end

local function open_url(url)
  -- Neovim 0.12 opens URLs on Windows via `cmd.exe /c start`, which treats `&`
  -- as a command separator and drops every query parameter after the first one.
  -- Hand the URL to the shell URL handler directly (as Neovim 0.10/0.11 did).
  if vim.fn.has("win32") == 1 and vim.fn.executable("rundll32") == 1 then
    return vim.system({ "rundll32", "url.dll,FileProtocolHandler", url }, { detach = true })
  end
  return vim.ui.open(url)
end

local function write_ics(content)
  local directory = vim.fs.joinpath(vim.fn.stdpath("cache"), "todo", "calendar")
  vim.fn.mkdir(directory, "p")
  local path = vim.fs.joinpath(directory, vim.fn.sha256(content) .. ".ics")
  local file, file_err = io.open(path, "wb")
  if not file then return nil, file_err end
  local written, write_err = file:write(content)
  file:close()
  if not written then return nil, write_err end
  return path
end

local function open_event(event, start, provider)
  if provider == "outlook_desktop" then
    if vim.fn.has("win32") ~= 1 then return nil, "Outlook desktop requires Windows" end
    local content, err = M.ics(event, start, { free = true })
    if not content then return nil, err end
    local path, write_err = write_ics(content)
    if not path then return nil, write_err end
    -- Opens with the app associated with .ics files (normally Outlook).
    -- explorer.exe accepts quoted paths (user names with spaces) and avoids cmd.exe parsing.
    local windows_path = (vim.fs.normalize(path):gsub("/", "\\"))
    return vim.system({ "explorer.exe", windows_path }, { detach = true })
  end
  if provider ~= "apple" then
    local url, err = M.url(event, start, provider)
    if not url then return nil, err end
    return open_url(url)
  end
  if vim.fn.has("mac") ~= 1 then return nil, "Apple Calendar requires macOS" end
  local content, err = M.ics(event, start)
  if not content then return nil, err end
  local path, write_err = write_ics(content)
  if not path then return nil, write_err end
  return vim.system({ "open", "-a", "Calendar", path }, {}, function(result)
    if result.code ~= 0 then
      vim.schedule(function() vim.notify("Cannot open Apple Calendar: " .. result.stderr, vim.log.levels.ERROR) end)
    end
  end)
end

--- Prompt for each selected todo and open its calendar event editor.
function M.schedule(todos, provider)
  if #todos == 0 then
    vim.notify("Select todos with Space first", vim.log.levels.INFO)
    return
  end
  if not provider then
    local providers = {
      { id = "google", label = "Google Calendar" },
      { id = "outlook", label = "Outlook.com (personal)" },
      { id = "outlook_work", label = "Outlook (Microsoft 365)" },
      { id = "outlook_desktop", label = "Outlook desktop (Windows, ICS)" },
      { id = "apple", label = "Apple Calendar (macOS)" },
    }
    vim.ui.select(providers, {
      prompt = "Calendar:", format_item = function(item) return item.label end,
    }, function(item)
      if item then M.schedule(todos, item.id) end
    end)
    return
  end
  -- Capture metadata now so async prompts do not depend on the list buffer.
  local events = {}
  for _, todo in ipairs(todos) do
    local buf = vim.fn.bufnr(todo.path)
    local ok, lines
    if buf ~= -1 and vim.api.nvim_buf_is_loaded(buf) then
      ok, lines = true, vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    else
      ok, lines = pcall(vim.fn.readfile, todo.path)
    end
    if not ok then
      vim.notify("Cannot read todo: " .. todo.path, vim.log.levels.ERROR)
      return
    end
    local event = require("todo").parse(lines)
    if not event.meta.Title or event.meta.Title == "" then event.meta.Title = todo.name end
    events[#events + 1] = event
  end
  local function prompt(index)
    local event = events[index]
    if not event then return end
    local due = event.meta.Due or ""
    local default = (due:match("^%d%d%d%d%-%d%d%-%d%d$") and due or os.date("%Y-%m-%d")) .. " 09:00"
    vim.ui.input({ prompt = "Start (local time) for " .. event.meta.Title .. " [YYYY-MM-DD HH:MM]: ", default = default }, function(value)
      if value == nil then return end
      local opened, process, open_err = pcall(open_event, event, vim.trim(value), provider)
      if not opened or not process then
        vim.notify("Cannot open calendar: " .. tostring(open_err or process), vim.log.levels.ERROR)
        return
      end
      prompt(index + 1)
    end)
  end
  prompt(1)
end

return M
