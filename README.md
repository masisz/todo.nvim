# todo.nvim

A lightweight, distraction-free todo management plugin for Neovim.

## Features

- Quick todo creation with custom template
- Automatically sequential todo files (`YYYYMMDD-01.todo`, `YYYYMMDD-02.todo`, ...)
- Filetype detection and syntax highlighting for todos
- Configurable todo directory, template, and extension

## Installation

### [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "masisz/todo.nvim",
  cmd = { "TodoNew", "TodoList" },
  keys = {
    { "<leader>Tn", "<Cmd>TodoNew<CR>", desc = "Create new todo" },
    { "<leader>Tl", "<Cmd>TodoList<CR>", desc = "Open todo list" },
  },
  opts = {
    directory = "~/todos", -- todo files directory
    extension = "todo",    -- "todo" or "task"
  },
}
```

## Configuration

Default options:

```lua
require("todo").setup({
  directory = "~/todos",
  extension = "todo",
  date_format = "%Y%m%d",
  template = {
    "[Title]",
    "",
    "[Memo]",
    "",
    "[Due]",
    function()
      return os.date("%Y-%m-%d")
    end,
    "[Duration]",
    "30m",
  },
  cursor_pos = { 2, 0 },
  start_insert = true,
})
```

## Commands

- `:TodoNew` - Create and open a new todo file.
- `:TodoList` / `<leader>Tl` - Open todos in a right-hand pane. Press Space to
  toggle selection and Enter to move selected todos into `done/` within the todo
  directory. Press `o` to edit the todo under the cursor (it opens in the
  previous window, or a new split if the list is the only window). Press `r` to
  refresh or `q` to close. Save modified todos before
  completing them; existing files in `done/` are never overwritten.
  Press `x` to permanently delete selected todos after confirmation. The
  confirmation lists the selected titles and defaults to No. Modified todos
  must be saved before deletion.

`TaskNew` and `TaskList` remain available as compatibility aliases.

In the todo list, select todos with Space and press `c` to schedule them in
Google Calendar, Outlook.com, Outlook for Microsoft 365, Outlook desktop
(Windows), or Apple Calendar.
Choose the provider when prompted (requires Neovim 0.10+). Enter a local start time
as `YYYY-MM-DD HH:MM` for each selected todo; the default is its Due date at
09:00. Google, Outlook.com, and Microsoft 365 open in your browser. Apple Calendar requires macOS
and opens an ICS file in the Calendar app; choose a calendar and import it.
Outlook desktop requires Windows and opens an ICS file with the app associated
with `.ics` files (normally Outlook); the event is marked "Show as: Free" via
`TRANSP:TRANSPARENT` and `X-MICROSOFT-CDO-BUSYSTATUS:FREE`. Save it in Outlook.
Generated ICS files are kept under `stdpath("cache")/todo/calendar/`.
A separate event editor/import opens for each todo with its Title, Memo, and
Duration filled in. Supported durations are `30m`, `1h`, and `1h30m`; an empty
Duration defaults to `30m`. Confirm and save in the browser or calendar app. Canceling a prompt
stops the remaining prompts. Scheduling does not mark todos as done, and
repeating the operation opens new drafts rather than updating existing events.

Outlook links request "Show as: Free" using `freebusy=free`. This deep-link
parameter is undocumented by Microsoft; verify the availability setting in the
event editor before saving.

## License

[MIT](LICENSE)
