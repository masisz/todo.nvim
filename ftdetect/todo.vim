augroup todo_filetype
  autocmd!
  autocmd BufRead,BufNewFile *.todo setfiletype todo
  autocmd BufRead,BufNewFile *.task setfiletype task
augroup END
