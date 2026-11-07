local M = {}

local source = debug.getinfo(1, "S").source:sub(2)
M.scripts_dir = source:match("^(.*[/\\])toolbox[/\\]core[/\\]paths%.lua$") or ""
M.native_dir = M.scripts_dir .. "native/"

return M
