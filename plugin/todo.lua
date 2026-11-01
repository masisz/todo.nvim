if vim.g.loaded_todo then
  return
end
vim.g.loaded_todo = true

vim.api.nvim_create_user_command("TodoNew", function()
  require("todo").create()
end, { desc = "Create a new todo task" })

-- Backward compatibility alias
vim.api.nvim_create_user_command("TaskNew", function()
  require("todo").create()
end, { desc = "Create a new todo task (alias for :TodoNew)" })
