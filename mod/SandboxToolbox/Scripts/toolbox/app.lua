local log = require("toolbox.core.log")
local version = require("toolbox.version")

local M = {}

function M.start()
    log.info("Sandbox Toolbox " .. version .. " starting.")
    local ok, err = pcall(function() require("toolbox.ui.panel").install(require("toolbox.actions").build()) end)
    if not ok then log.info("Panel could not load: " .. tostring(err)) end
end

return M
