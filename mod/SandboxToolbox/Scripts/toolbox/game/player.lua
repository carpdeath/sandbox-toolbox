local util = require("toolbox.core.util")

local M = {}

function M.controller()
    local pc = FindFirstOf("PlayerController")
    return util.valid(pc) and pc or nil
end

function M.pawn()
    local pawns = util.safe(function() return FindAllOf("PawnCPP") end, {})
    for _, pawn in ipairs(pawns) do
        if util.valid(pawn) and util.safe(function() return pawn.isMainPlayer end, false) == true then return pawn end
    end
    local pc = M.controller()
    local owned = pc and util.safe(function() return pc.Pawn end, nil)
    return util.valid(owned) and owned or nil
end

return M
