local M = {}
local state

local function render()
  local lines = {}
  for _, todo in ipairs(state.todos) do
    lines[#lines + 1] = string.format("[%s] %s", state.selected[todo.path] and "x" or " ", todo.label)
  end
  if #lines == 0 then
    lines = { "No todos" }
  end
  vim.bo[state.buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
  vim.bo[state.buf].modifiable = false
end

local function refresh()
  state.todos = {}
  if vim.fn.isdirectory(state.directory) == 1 then
    for name, kind in vim.fs.dir(state.directory) do
      if kind == "file" and vim.endswith(name, "." .. state.extension) then
        local path = vim.fs.joinpath(state.directory, name)
        local ok, lines = pcall(vim.fn.readfile, path)
        local title = ok and require("todo").parse(lines).meta.Title or nil
        state.todos[#state.todos + 1] = {
          path = path,
          name = name,
          label = title and title ~= "" and title or name,
        }
      end
    end
  end
  table.sort(state.todos, function(a, b) return a.name < b.name end)
  render()
end

local function complete()
  local done = vim.fs.joinpath(state.directory, "done")
  local count = 0
  for _, todo in ipairs(state.todos) do
    if state.selected[todo.path] then
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
  end
  refresh()
  vim.notify(string.format("Completed %d todo(s)", count))
end

local function delete_selected()
  local selected, labels = {}, {}
  for _, todo in ipairs(state.todos) do
    if state.selected[todo.path] then
      selected[#selected + 1] = todo
      labels[#labels + 1] = todo.label
    end
  end
  if #selected == 0 then
    vim.notify("Select todos to delete", vim.log.levels.INFO)
    return
  end
  local prompt = string.format("Permanently delete %d todo(s)?\n\n%s", #selected, table.concat(labels, "\n"))
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
  refresh()
  vim.notify(string.format("Deleted %d todo(s)", count))
end

--- Open the todo under the cursor for editing, keeping the list pane open.
local function edit_todo()
  local todo = state.todos[vim.api.nvim_win_get_cursor(0)[1]]
  if not todo then return end
  -- Prefer the window the user came from; otherwise any normal window in this tab.
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
  local path = vim.fn.fnameescape(todo.path)
  if target then
    vim.api.nvim_set_current_win(target)
    vim.cmd("edit " .. path)
  else
    vim.cmd("topleft vsplit " .. path)
  end
end

function M.open()
  if state and vim.api.nvim_win_is_valid(state.win) and vim.api.nvim_buf_is_valid(state.buf)
      and vim.api.nvim_win_get_buf(state.win) == state.buf then
    vim.api.nvim_set_current_win(state.win)
    refresh()
    return
  end
  local config = require("todo.config").options
  vim.cmd("botright vnew")
  local win = vim.api.nvim_get_current_win()
  local buf = vim.api.nvim_get_current_buf()
  state = {
    win = win, buf = buf, todos = {}, selected = {},
    directory = vim.fn.fnamemodify(vim.fn.expand(config.directory), ":p"),
    extension = config.extension,
  }
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = "todolist"
  vim.wo[win].wrap = false
  vim.wo[win].cursorline = true
  vim.api.nvim_buf_set_name(buf, "todo://TodoList")
  vim.keymap.set("n", "<Space>", function()
    local todo = state.todos[vim.api.nvim_win_get_cursor(0)[1]]
    if todo then
      state.selected[todo.path] = not state.selected[todo.path]
      render()
    end
  end, { buffer = buf, desc = "Select todo" })
  vim.keymap.set("n", "<CR>", complete, { buffer = buf, desc = "Complete selected todos" })
  vim.keymap.set("n", "x", delete_selected, { buffer = buf, desc = "Delete selected todos with confirmation" })
  vim.keymap.set("n", "c", function()
    local selected = {}
    for _, todo in ipairs(state.todos) do
      if state.selected[todo.path] then selected[#selected + 1] = todo end
    end
    require("todo.calendar").schedule(selected)
  end, { buffer = buf, desc = "Schedule selected todos in a calendar" })
  vim.keymap.set("n", "o", edit_todo, { buffer = buf, desc = "Edit todo under cursor" })
  vim.keymap.set("n", "r", refresh, { buffer = buf, desc = "Refresh todos" })
  vim.keymap.set("n", "q", "<Cmd>close<CR>", { buffer = buf, desc = "Close todo list" })
  refresh()
end

return M
