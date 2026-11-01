# todo.nvim

A lightweight, distraction-free task management plugin for Neovim.

## Features

- Quick task creation with custom template
- Automatically sequential task files (`YYYYMMDD-01.task`, `YYYYMMDD-02.task`, ...)
- Filetype detection and syntax highlighting for tasks
- Configurable task directory, template, and extension

## Installation

### [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "masisz/todo.nvim",
  cmd = { "TodoNew", "TaskNew" },
  keys = {
    { "<leader>Tn", "<Cmd>TodoNew<CR>", desc = "Create new task" },
  },
  opts = {
    directory = "~/tasks", -- task files directory
    extension = "task",    -- "task" or "todo"
  },
}
```

## Configuration

Default options:

```lua
require("todo").setup({
  directory = "~/tasks",
  extension = "task",
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
    "1h",
  },
  cursor_pos = { 2, 0 },
  start_insert = true,
})
```

## Commands

- `:TodoNew` - Create and open a new task file.
- `:TaskNew` - Alias for `:TodoNew`.

## License

[MIT](LICENSE)
