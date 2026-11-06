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
  roadmap_dir = "roadmap", -- milestones: ~/todos/roadmap/
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

- `~/todos/` - daily tasks (`30m`, `2h`, `1d`)
- `~/todos/roadmap/` - mid/long-term milestones (`2w`, `1M`, `3M`)

A daily todo may belong to a milestone through its `[Roadmap]` field, which
holds the milestone's file name without extension (e.g. `20261106-01`). Leave
it empty for a one-off task. Completed items go to `done/` inside each folder.

### Example workflow

1. `:RoadmapNew` and write a milestone, e.g. Title `Release v1`, Duration `1M`.
2. `:RoadmapList`, move the cursor to `Release v1` and press `n` to add todos
   for it (e.g. `design`, `impl`). One-off tasks are created with `:TodoNew`
   as usual.
3. To attach an existing todo, open `:TodoList`, select it with Space and
   press `l`, then pick the milestone.
4. Complete todos in `:TodoList` with Space and Enter. The roadmap shows the
   progress:

   ```
   [ ] Release v1  1M  due 2026-12-01  (1/3)
         - impl  30m
         - test  2h

   Unlinked todos: 4
   ```

   `(1/3)` is completed/total linked todos (counting `~/todos/done/`), followed
   by the milestone's open todos. The last line counts todos not linked to any
   milestone.
5. When the milestone is finished, select it in `:RoadmapList` and press Enter.

## Commands

| Command | Default key | Description |
| --- | --- | --- |
| `:TodoNew` | `<leader>Tn`* | Create and open a new daily todo |
| `:TodoList` | `<leader>Tl` | Open daily todos in a right-hand pane |
| `:RoadmapNew` | | Create and open a new milestone in `roadmap/` |
| `:RoadmapList` | `<leader>Tr` | Open milestones with their linked todos in a right-hand pane |

\* Set in the lazy.nvim example above; the plugin itself maps only `<leader>Tl`
and `<leader>Tr`. `TaskNew` and `TaskList` remain available as compatibility
aliases.

### Keys in `:TodoList`

Each todo shows its Duration and linked milestone (`-> Release v1`).

| Key | Action |
| --- | --- |
| `Space` | Toggle selection of the todo under the cursor |
| `Enter` | Move selected todos into `done/` |
| `x` | Permanently delete selected todos (after confirmation, default No) |
| `o` | Edit the todo under the cursor |
| `a` | Add a todo |
| `l` | Link selected todos (or the one under the cursor) to a milestone; choose `(No roadmap)` to unlink |
| `c` | Schedule selected todos in a calendar (see below) |
| `t` | Switch to the todo list |
| `r` | Switch to the roadmap |
| `R` | Refresh |
| `q` | Close |

### Keys in `:RoadmapList`

| Key | Action |
| --- | --- |
| `Space` | Toggle selection of the milestone under the cursor |
| `Enter` | Move selected milestones into `roadmap/done/` |
| `x` | Permanently delete selected milestones (after confirmation, default No) |
| `o` | Edit the milestone or todo under the cursor |
| `n` | Create a daily todo linked to the milestone under the cursor (or the milestone of the todo under the cursor) |
| `a` | Add a milestone |
| `t` | Switch to the todo list |
| `r` | Switch to the roadmap |
| `R` | Refresh |
| `q` | Close |

Notes for both lists:

- Press `t` for the todo list or `r` for the roadmap. Switching reuses the list
  pane; if the other view is already open, it is focused and the source pane
  closes. Press `R` (uppercase) to refresh; `r` now switches to the roadmap.
- Key hints for the current view appear at the bottom of short lists and after
  the items in long lists (scroll down to see them).
- `o`, `a` and `n` open the file in the previous window, or in a new split if
  the list is the only window.
- Save modified files before completing, deleting or linking them. Existing
  files in `done/` are never overwritten.
- Open lists refresh automatically when a todo is saved.

## Calendar

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
