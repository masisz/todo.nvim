if vim.g.loaded_todo then
  return
end
vim.g.loaded_todo = true

vim.filetype.add({
  extension = {
    todo = "todo",
    task = "task",
  },
})

vim.api.nvim_create_user_command("TodoList", function()
  require("todo").list()
end, { desc = "Select and complete todos in a right-hand pane" })

vim.keymap.set("n", "<leader>Tl", "<Cmd>TodoList<CR>", { desc = "Open todo list" })

vim.api.nvim_create_user_command("TodoNew", function()
  require("todo").create()
end, { desc = "Create a new todo" })

vim.api.nvim_create_user_command("RoadmapNew", function()
  require("todo").create_roadmap()
end, { desc = "Create a new roadmap milestone" })

vim.api.nvim_create_user_command("RoadmapList", function()
  require("todo").roadmap()
end, { desc = "Open roadmap milestones with their linked todos" })

vim.api.nvim_create_user_command("RoadmapView", function()
  require("todo.viewer").open()
end, { desc = "Open the roadmap dependency graph and gantt in a browser" })

vim.api.nvim_create_user_command("RoadmapViewStop", function()
  require("todo.viewer").stop()
end, { desc = "Stop the roadmap viewer server" })

vim.api.nvim_create_user_command("RoadmapExport", function(cmd)
  require("todo.viewer").export(cmd.args)
end, {
  nargs = "?",
  complete = function() return { "mermaid" } end,
  desc = "Export the roadmap (mermaid: roadmap/export/roadmap.md)",
})

vim.keymap.set("n", "<leader>Tr", "<Cmd>RoadmapList<CR>", { desc = "Open roadmap" })

-- Backward compatibility alias
vim.api.nvim_create_user_command("TaskNew", function()
  require("todo").create()
end, { desc = "Create a new todo (alias for :TodoNew)" })

-- Compatibility alias for existing configurations.
vim.api.nvim_create_user_command("TaskList", function()
  require("todo").list()
end, { desc = "Open todo list (alias for :TodoList)" })
