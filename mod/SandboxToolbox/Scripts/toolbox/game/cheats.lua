local config = require("toolbox.config")
local util = require("toolbox.core.util")
local player = require("toolbox.game.player")

local M = {}

local LOOKUPS = {
    function() return FindFirstOf("MLCheatManager") end,
    function() return FindFirstOf("CheatManager") end,
    function()
        local pc = player.controller()
        return pc and pc.CheatManager
    end,
}

function M.find()
    for _, lookup in ipairs(LOOKUPS) do
        local cm = util.safe(lookup, nil)
        if util.valid(cm) then return cm end
    end
    return nil
end

function M.manager()
    local cm = M.find()
    if cm then return cm end
    local pc = player.controller()
    if not pc then return nil end
    pcall(function() pc:AddCheats(true) end)
    return M.find()
end

function M.give_items(cm, items, count)
    local give = cm[config.fn.give_by_name]
    if give == nil then return nil end
    local done = 0
    for _, item in ipairs(items) do
        if pcall(give, cm, item, count) then done = done + 1 end
    end
    return done
end

return M
