local config = require("toolbox.config")
local cheats = require("toolbox.game.cheats")
local player = require("toolbox.game.player")
local region = require("toolbox.game.region")
local util = require("toolbox.core.util")

local M = {}

function M.add(kind, amount)
    if kind == "wealth" then
        local r, why = region.require_owned()
        if not r then return why end
        local fname = config.fn.add_region_gold
        if r[fname] == nil then return "Wealth function '" .. fname .. "' unavailable on this build." end
        local before = region.wealth(r)
        r[fname](r, amount)
        return "Regional wealth: " .. tostring(before) .. " -> " .. tostring(region.wealth(r))
    end

    if kind == "influence" then
        local pawn = player.pawn()
        local fname = config.fn.change_influence
        if not pawn or pawn[fname] == nil then return "Influence function unavailable on this build." end
        local before = util.safe(function() return pawn.influence end, nil)
        pawn[fname](pawn, amount)
        local after = util.safe(function() return pawn.influence end, nil)
        return "Influence: " .. tostring(before) .. " -> " .. tostring(after)
    end

    local cm = cheats.manager()
    if not cm or cm[config.fn.change_treasury] == nil then return "Treasury function unavailable." end
    cm[config.fn.change_treasury](cm, amount)
    return "Requested +" .. amount .. " treasury."
end

return M
