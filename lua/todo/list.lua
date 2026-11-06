local config = require("todo.config")
local store = require("todo.store")

local M = {}

---@type table<string, table>
local states = {}

local function valid(state)
  return state and vim.api.nvim_win_is_valid(state.win) and vim.api.nvim_buf_is_valid(state.buf)
    and vim.api.nvim_win_get_buf(state.win) == state.buf
end

local function duration(todo)
  local value = todo.meta.Duration
  return value and value ~= "" and "  " .. value or ""
end

local function selectable_row(state, todo, text)
  return { todo = todo, text = string.format("[%s] %s", state.selected[todo.path] and "x" or " ", text) }
end

--- Titles of milestones by id, including completed ones.
local function milestone_titles()
  local titles = {}
  for _, done in ipairs({ false, true }) do
    for _, milestone in ipairs(store.scan("roadmap", done)) do
      titles[milestone.id] = milestone.label .. (done and " (done)" or "")
    end
  end
  return titles
end

--- Number of todo files left directly in the root directory after daily_dir was introduced.
local function legacy_count()
  if (config.options.daily_dir or "") == "" then return 0 end
  local count, ext = 0, "." .. config.options.extension
  local root = config.root()
  if vim.fn.isdirectory(root) == 1 then
    for name, type in vim.fs.dir(root) do
      if type == "file" and vim.endswith(name, ext) then count = count + 1 end
    end
  end
  return count
end

local function build_daily(state)
  local rows = {}
  local titles = milestone_titles()
  for _, todo in ipairs(state.todos) do
    local link = todo.meta.Roadmap or ""
    local suffix = link ~= "" and "  -> " .. (titles[link] or link .. " (missing)") or ""
    rows[#rows + 1] = selectable_row(state, todo, todo.label .. duration(todo) .. suffix)
  end
  if #rows == 0 then rows[1] = { text = "No todos" } end
  local legacy = legacy_count()
  if legacy > 0 then
    rows[#rows + 1] = { text = "" }
    rows[#rows + 1] = { text = string.format("! %d todo(s) in %s are not shown; move them to %s/",
      legacy, config.root(), config.options.daily_dir) }
  end
  return rows
end

local function build_roadmap(state)
  local rows = {}
  local children, done_counts, unlinked = {}, {}, 0
  for _, todo in ipairs(store.scan("daily")) do
    local link = todo.meta.Roadmap or ""
    if link == "" then
      unlinked = unlinked + 1
    else
      children[link] = children[link] or {}
      table.insert(children[link], todo)
    end
  end
  for _, todo in ipairs(store.scan("daily", true)) do
    local link = todo.meta.Roadmap or ""
    if link ~= "" then done_counts[link] = (done_counts[link] or 0) + 1 end
  end
  for _, milestone in ipairs(state.todos) do
    local open = children[milestone.id] or {}
    local done = done_counts[milestone.id] or 0
    local due = milestone.meta.Due and milestone.meta.Due ~= "" and "  due " .. milestone.meta.Due or ""
    rows[#rows + 1] = selectable_row(state, milestone, string.format("%s%s%s  (%d/%d)",
      milestone.label, duration(milestone), due, done, done + #open))
    for _, todo in ipairs(open) do
      rows[#rows + 1] = { todo = todo, milestone = milestone, text = "      - " .. todo.label .. duration(todo) }
    end
  end
  if #state.todos == 0 then rows[#rows + 1] = { text = "No milestones (press a to add one)" } end
  rows[#rows + 1] = { text = "" }
  rows[#rows + 1] = { text = string.format("Unlinked todos: %d", unlinked) }
  return rows
end

local function render(state)
  state.rows = state.kind == "roadmap" and build_roadmap(state) or build_daily(state)
  local lines = {}
  for i, row in ipairs(state.rows) do lines[i] = row.text end
  vim.bo[state.buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
  vim.bo[state.buf].modifiable = false
end

local function refresh(state)
  state.todos = store.scan(state.kind)
  render(state)
end

--- Refresh every open list (a change in one mode can affect the other).
local function refresh_all()
  for _, state in pairs(states) do
    if valid(state) then refresh(state) end
  end
end

local function row_at_cursor(state)
  return state.rows[vim.api.nvim_win_get_cursor(state.win)[1]]
end

local function selected_items(state)
  local items = {}
  for _, todo in ipairs(state.todos) do
    if state.selected[todo.path] then items[#items + 1] = todo end
  end
  return items
end

local function complete(state)
  local done = vim.fs.joinpath(state.directory, "done")
  local count = 0
  for _, todo in ipairs(selected_items(state)) do
    local target = vim.fs.joinpath(done, todo.name)
    local buf = vim.fn.bufnr(todo.path)
    if buf ~= -1 and vim.bo[buf].modified then
      vim.notify("Save todo before completing: " .. todo.name, vim.log.levels.WARN)
    elseif vim.uv.fs_stat(target) then
      vim.notify("Completed todo already exists: " .. target, vim.log.levels.WARN)
    else
      local ok, err = pcall(vim.fn.mkdir, done, "p")
      if ok then
        ok, err = vim.uv.fs_rename(todo.path, target)
      end
      if ok then
        if buf ~= -1 then
          vim.api.nvim_buf_set_name(buf, target)
        end
        state.selected[todo.path] = nil
        count = count + 1
      else
        vim.notify("Cannot complete " .. todo.name .. ": " .. tostring(err), vim.log.levels.ERROR)
      end
    end
  end
  refresh_all()
  vim.notify(string.format("Completed %d %s", count, state.kind == "roadmap" and "milestone(s)" or "todo(s)"))
end

local function delete_selected(state)
  local selected, labels = selected_items(state), {}
  for _, todo in ipairs(selected) do labels[#labels + 1] = todo.label end
  if #selected == 0 then
    vim.notify("Select items to delete", vim.log.levels.INFO)
    return
  end
  local prompt = string.format("Permanently delete %d %s?\n\n%s", #selected,
    state.kind == "roadmap" and "milestone(s)" or "todo(s)", table.concat(labels, "\n"))
  if vim.fn.confirm(prompt, "&Yes\n&No", 2) ~= 1 then
    return
  end
  local count = 0
  for _, todo in ipairs(selected) do
    local buf = vim.fn.bufnr(todo.path)
    if buf ~= -1 and vim.bo[buf].modified then
      vim.notify("Save todo before deleting: " .. todo.name, vim.log.levels.WARN)
    else
      local ok, err = vim.uv.fs_unlink(todo.path)
      if ok then
        if buf ~= -1 then
          vim.api.nvim_buf_delete(buf, { force = false })
        end
        state.selected[todo.path] = nil
        count = count + 1
      else
        vim.notify("Cannot delete " .. todo.name .. ": " .. tostring(err), vim.log.levels.ERROR)
      end
    end
  end
  refresh_all()
  vim.notify(string.format("Deleted %d item(s)", count))
end

--- Move to a normal window other than the list (the previous one if possible).
--- Returns false when the list is the only window; callers then open a split.
local function focus_main(state)
  local target = vim.fn.win_getid(vim.fn.winnr("#"))
  local function usable(win)
    return win ~= 0 and win ~= state.win and vim.api.nvim_win_is_valid(win)
      and vim.api.nvim_win_get_config(win).relative == ""
  end
  if not usable(target) then
    target = nil
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      if usable(win) then target = win break end
    end
  end
  if target then
    vim.api.nvim_set_current_win(target)
    return true
  end
  return false
end

--- Open the todo (or milestone) under the cursor for editing, keeping the list pane open.
local function edit_item(state)
  local row = row_at_cursor(state)
  if not row or not row.todo then return end
  local path = vim.fn.fnameescape(row.todo.path)
  if focus_main(state) then
    vim.cmd("edit " .. path)
  else
    vim.cmd("topleft vsplit " .. path)
  end
end

local function create(state, opts)
  if focus_main(state) then
    require("todo.creator").create_task(opts)
    return
  end
  -- The list is the only window: open the new todo in a split, dropping the scratch buffer.
  vim.cmd("topleft vnew")
  local scratch = vim.api.nvim_get_current_buf()
  require("todo.creator").create_task(opts)
  if scratch ~= vim.api.nvim_get_current_buf() and vim.api.nvim_buf_is_valid(scratch) then
    pcall(vim.api.nvim_buf_delete, scratch, {})
  end
end

--- Roadmap view: create a daily todo linked to the milestone under the cursor.
local function new_linked_todo(state)
  local row = row_at_cursor(state)
  local milestone = row and (row.milestone or row.todo)
  if not milestone then
    vim.notify("Move the cursor to a milestone first", vim.log.levels.INFO)
    return
  end
  create(state, { kind = "daily", roadmap = milestone.id })
end

--- Daily list: link the selected todos (or the one under the cursor) to a milestone.
local function link(state)
  local todos = selected_items(state)
  if #todos == 0 then
    local row = row_at_cursor(state)
    if row and row.todo then todos = { row.todo } end
  end
  if #todos == 0 then
    vim.notify("Select todos to link", vim.log.levels.INFO)
    return
  end
  local choices = { { id = "", label = "(No roadmap)" } }
  vim.list_extend(choices, store.scan("roadmap"))
  vim.ui.select(choices, {
    prompt = "Roadmap milestone:", format_item = function(item) return item.label end,
  }, function(choice)
    if not choice then return end
    local count = 0
    for _, todo in ipairs(todos) do
      local ok, err = store.write_field(todo.path, "Roadmap", choice.id)
      if ok then
        count = count + 1
      else
        vim.notify(err, vim.log.levels.WARN)
      end
    end
    refresh_all()
    vim.notify(string.format("%s %d todo(s)", choice.id == "" and "Unlinked" or "Linked", count))
  end)
end

---@param kind? "daily"|"roadmap"
function M.open(kind)
  kind = kind == "roadmap" and "roadmap" or "daily"
  local existing = states[kind]
  if valid(existing) then
    vim.api.nvim_set_current_win(existing.win)
    refresh(existing)
    return
  end
  vim.cmd("botright vnew")
  local win = vim.api.nvim_get_current_win()
  local buf = vim.api.nvim_get_current_buf()
  local state = {
    kind = kind, win = win, buf = buf, todos = {}, rows = {}, selected = {},
    directory = config.dir(kind),
  }
  states[kind] = state
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = kind == "roadmap" and "todoroadmap" or "todolist"
  vim.wo[win].wrap = false
  vim.wo[win].cursorline = true
  vim.api.nvim_buf_set_name(buf, kind == "roadmap" and "todo://RoadmapList" or "todo://TodoList")

  local function map(lhs, fn, desc)
    vim.keymap.set("n", lhs, function() fn(state) end, { buffer = buf, desc = desc })
  end
  map("<Space>", function()
    local row = row_at_cursor(state)
    if row and row.todo and not row.milestone then
      state.selected[row.todo.path] = not state.selected[row.todo.path]
      render(state)
    end
  end, "Select item")
  map("<CR>", complete, "Complete selected items")
  map("x", delete_selected, "Delete selected items with confirmation")
  map("o", edit_item, "Edit item under cursor")
  map("r", refresh_all, "Refresh")
  vim.keymap.set("n", "q", "<Cmd>close<CR>", { buffer = buf, desc = "Close list" })
  if kind == "roadmap" then
    map("a", function() create(state, { kind = "roadmap" }) end, "Add a milestone")
    map("n", new_linked_todo, "New todo linked to the milestone under cursor")
  else
    map("a", function() create(state, { kind = "daily" }) end, "Add a todo")
    map("l", link, "Link selected todos to a roadmap milestone")
    map("c", function() require("todo.calendar").schedule(selected_items(state)) end,
      "Schedule selected todos in a calendar")
  end

  local group = vim.api.nvim_create_augroup("todo_list_" .. kind, { clear = true })
  vim.api.nvim_create_autocmd("BufWritePost", {
    group = group,
    pattern = "*." .. config.options.extension,
    callback = function()
      if valid(state) then vim.schedule(refresh_all) end
    end,
  })
  vim.api.nvim_create_autocmd("BufWipeout", {
    group = group, buffer = buf,
    callback = function() pcall(vim.api.nvim_del_augroup_by_id, group) end,
  })
  refresh(state)
end

return M
