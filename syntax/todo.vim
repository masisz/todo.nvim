if exists('b:current_syntax')
  finish
endif

syntax match todoKey "^\s*\[\(Title\|Memo\|Due\|Duration\)\]\s*$"

highlight default link todoKey Identifier
let b:current_syntax = 'todo'
