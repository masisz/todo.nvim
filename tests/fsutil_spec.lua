-- REAL-MACHINE CHECK: run this on Windows and macOS (`nvim -l tests/run.lua tests/fsutil_spec.lua`).
-- It verifies that write_atomic (uv.fs_rename over an existing file) replaces the target.
local h = require("helpers")
local fsutil = require("todo.viewer.fsutil")

h.test("write_atomic creates and overwrites a file, leaving no temp files", function()
  local dir = vim.fn.tempname()
  local path = dir .. "/sub/deps.txt"
  h.ok(fsutil.write_atomic(path, "one\r\n"))
  h.eq("one\r\n", fsutil.read(path))
  local ok, err = fsutil.write_atomic(path, "two\n")
  h.ok(ok, "overwrite failed: " .. tostring(err))
  h.eq("two\n", fsutil.read(path))
  h.eq({ "deps.txt" }, vim.fn.readdir(dir .. "/sub"))
end)

h.test("write_atomic overwrites a file that is open for reading", function()
  -- On Windows a rename onto an open file may fail; this documents the behaviour on that platform.
  local path = vim.fn.tempname()
  fsutil.write_atomic(path, "old")
  local reader = assert(io.open(path, "rb"))
  local ok, err = fsutil.write_atomic(path, "new")
  reader:close()
  h.ok(ok, "overwrite while open failed: " .. tostring(err))
  h.eq("new", fsutil.read(path))
end)

h.test("write_atomic keeps binary data intact", function()
  local path = vim.fn.tempname() .. ".png"
  local bytes = "\137PNG\r\n\26\n\0\1\2\255"
  h.ok(fsutil.write_atomic(path, bytes))
  h.eq(bytes, fsutil.read(path))
end)
