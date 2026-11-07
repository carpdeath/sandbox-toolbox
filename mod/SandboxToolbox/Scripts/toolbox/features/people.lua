local paths = require("toolbox.core.paths")
local bridge = require("toolbox.core.bridge")
local region = require("toolbox.game.region")

local M = {}

local queue_migration = bridge.export("queue_migration", "people", "Migration")

function M.add(target, count)
    assert(count == 1 or count == 5, "Invalid family count.")
    assert(paths.scripts_dir ~= "", "Could not locate the mod Scripts directory.")
    local result = queue_migration(("%x %d"):format(target:GetAddress(), count))
    local total = tonumber(result:match("^OK (%d+)$"))
    if not total then return bridge.failure(result, "Migration") end
    return ("Next month: +%d %s from Toolbox."):format(total, total == 1 and "family" or "families")
end

function M.queue(count)
    local target, why = region.require_owned()
    if not target then return why end
    return M.add(target, count)
end

return M
