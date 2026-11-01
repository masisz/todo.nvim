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

-- Backward compatibility alias
vim.api.nvim_create_user_command("TaskNew", function()
  require("todo").create()
end, { desc = "Create a new todo (alias for :TodoNew)" })

-- Compatibility alias for existing configurations.
vim.api.nvim_create_user_command("TaskList", function()
  require("todo").list()
end, { desc = "Open todo list (alias for :TodoList)" })
