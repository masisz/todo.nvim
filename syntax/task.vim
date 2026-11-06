if exists('b:current_syntax')
  finish
endif

syntax match taskKey "^\s*\[\(Title\|Memo\|Due\|Duration\|Roadmap\)\]\s*$"

highlight default link taskKey Identifier
let b:current_syntax = 'task'
