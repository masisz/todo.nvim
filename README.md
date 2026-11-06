# todo.nvim

A lightweight, distraction-free todo management plugin for Neovim.

## Features

- Quick todo creation with custom template
- Roadmap mode: mid/long-term milestones with linked daily todos and progress
- Automatically sequential todo files (`YYYYMMDD-01.todo`, `YYYYMMDD-02.todo`, ...)
- Filetype detection and syntax highlighting for todos
- Configurable todo directory, template, and extension

## Installation

### [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "masisz/todo.nvim",
  cmd = { "TodoNew", "TodoList", "RoadmapNew", "RoadmapList" },
  keys = {
    { "<leader>Tn", "<Cmd>TodoNew<CR>", desc = "Create new todo" },
    { "<leader>Tl", "<Cmd>TodoList<CR>", desc = "Open todo list" },
    { "<leader>Tr", "<Cmd>RoadmapList<CR>", desc = "Open roadmap" },
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
  daily_dir = "daily",     -- daily todos: ~/todos/daily/ ("" = ~/todos itself)
  roadmap_dir = "roadmap", -- milestones:  ~/todos/roadmap/
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
    "[Roadmap]",
    "", -- id of the linked milestone; empty for a one-off todo
  },
  roadmap_template = {
    "[Title]",
    "",
    "[Memo]",
    "",
    "[Due]",
    function()
      return os.date("%Y-%m-%d")
    end,
    "[Duration]",
    "1M",
  },
  cursor_pos = { 2, 0 },
  start_insert = true,
})
```

## Daily todos and roadmap

Todos are split by folder:

- `~/todos/daily/` - daily tasks (`30m`, `2h`, `1d`)
- `~/todos/roadmap/` - mid/long-term milestones (`2w`, `1M`, `3M`)

A daily todo may belong to a milestone through its `[Roadmap]` field, which
holds the milestone's file name without extension (e.g. `20261106-01`). Leave
it empty for a one-off task. Completed items go to `done/` inside each folder.

> **Upgrading:** todos used to live directly in `~/todos/`. Move them to
> `~/todos/daily/`, or set `daily_dir = ""` to keep the old location.
> `:TodoList` shows a notice while such files remain.

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

- `:RoadmapNew` - Create a new milestone in `roadmap/`.
- `:RoadmapList` / `<leader>Tr` - Roadmap mode. Shows each milestone with its
  Duration, Due date and progress (completed/total linked todos, counting
  `daily/done/`), followed by its open linked todos. The last line shows how
  many todos are not linked to any milestone.
  - `n` - create a daily todo linked to the milestone under the cursor
  - `a` - add a milestone
  - `o` - edit the milestone or todo under the cursor
  - Space / Enter / `x` - select / complete / delete milestones
  - `r` refresh, `q` close
- In `:TodoList`, each todo shows its Duration and linked milestone
  (`-> Release v1`). Press `l` to link the selected todos (or the one under
  the cursor) to a milestone, or choose `(No roadmap)` to unlink. Press `a` to
  add a todo. Lists refresh when a todo is saved.

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
Duration filled in. Calendar durations must be in hours/minutes (e.g. `30m`,
`2h`, `1h30m`); day/week/month durations such as `1d` are rejected. An empty
Duration defaults to `30m`. Confirm and save in the browser or calendar app. Canceling a prompt
stops the remaining prompts. Scheduling does not mark todos as done, and
repeating the operation opens new drafts rather than updating existing events.

Outlook links request "Show as: Free" using `freebusy=free`. This deep-link
parameter is undocumented by Microsoft; verify the availability setting in the
event editor before saving.

## License

[MIT](LICENSE)
