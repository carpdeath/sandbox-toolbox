local ok, err = pcall(function() require("toolbox.app").start() end)
if not ok then print("[SandboxToolbox] Failed to start: " .. tostring(err) .. "\n") end
