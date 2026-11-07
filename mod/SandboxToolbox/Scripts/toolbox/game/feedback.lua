local config = require("toolbox.config")
local util = require("toolbox.core.util")
local player = require("toolbox.game.player")

local M = {}

function M.flash(text)
    local pawn = player.pawn()
    if not (pawn and pawn.playFeedbackText) then return false end
    local where = util.safe(function() return pawn:K2_GetActorLocation() end, nil)
    if not where then return false end
    return pcall(pawn.playFeedbackText, pawn, text, where, config.flash_speed)
end

return M
