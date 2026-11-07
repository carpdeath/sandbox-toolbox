local util = require("toolbox.core.util")
local player = require("toolbox.game.player")

local M = {}

M.OWNED, M.UNKNOWN, M.FOREIGN = 2, 1, 0

M.FIELDS = { "regionUnderCursor", "hoveringRegion", "RegionPanelTarget", "selectedRegion", "currentRegion" }

local function same(a, b)
    if a == b then return true end
    local na = util.safe(function() return a:GetFullName() end, nil)
    return na ~= nil and na == util.safe(function() return b:GetFullName() end, nil)
end

function M.ownership(region, pawn)
    local owner = util.safe(function() return region.ownerPawn end, nil)
    if owner == nil then return M.UNKNOWN end
    return same(owner, pawn) and M.OWNED or M.FOREIGN
end

function M.target()
    local pawn = player.pawn()
    if not pawn then return nil, "player pawn not found" end
    local best, from, rank
    for _, field in ipairs(M.FIELDS) do
        local candidate = util.safe(function() return pawn[field] end, nil)
        if util.valid(candidate) then
            local r = M.ownership(candidate, pawn)
            if rank == nil or r > rank then
                best, from, rank = candidate, field, r
            end
        end
    end
    if best == nil then return nil, "no region under the cursor, in the panel, or selected" end
    return best, from, rank
end

function M.require_owned()
    local r, _, rank = M.target()
    if not util.valid(r) then return nil, "Load and select a settlement first." end
    if rank == M.FOREIGN then return nil, "Select a settlement you own first." end
    if rank ~= M.OWNED then return nil, "Can't tell who owns this settlement. Hover or select one of yours." end
    return r
end

function M.wealth(region) return util.number(region, "regionalWealth") end

return M
