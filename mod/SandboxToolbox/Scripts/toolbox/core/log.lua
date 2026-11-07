local config = require("toolbox.config")

local M = {}
local TAG = "[SandboxToolbox]"

function M.info(msg) print(TAG .. " " .. tostring(msg) .. "\n") end

function M.debug(msg)
    if config.debug then M.info(msg) end
end

function M.timer(label)
    if not config.debug then
        return function() end
    end
    local started = os.clock()
    return function() M.info(string.format("%s: %.1f ms", label, (os.clock() - started) * 1000)) end
end

return M
