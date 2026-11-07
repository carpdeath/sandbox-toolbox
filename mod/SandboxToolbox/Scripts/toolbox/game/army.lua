local config = require("toolbox.config")
local util = require("toolbox.core.util")
local player = require("toolbox.game.player")

local M = {}

local function handle_id(handle)
    local value = util.safe(function() return handle.Value end, nil)
    if value == nil then value = util.safe(function() return handle:get().Value end, nil) end
    return math.tointeger(tonumber(value))
end

local function each(array, fn)
    if array == nil then return end
    local n = util.safe(function() return array:GetArrayNum() end, nil)
    if n then
        for i = 1, n do
            local element = util.safe(function() return array[i] end, nil)
            if element ~= nil then fn(element) end
        end
    else
        for _, element in ipairs(array) do
            fn(element)
        end
    end
end

function M.squads()
    local ids, set = {}, {}
    local function collect(array)
        each(array, function(handle)
            local id = handle_id(handle)
            if id and not set[id] then
                set[id] = true
                ids[#ids + 1] = id
            end
        end)
    end
    local component = util.safe(function() return FindFirstOf("SquadComponent") end, nil)
    if util.valid(component) then collect(util.safe(function() return component[config.prop.squad_order] end, nil)) end
    if #ids == 0 then
        local pawn = player.pawn()
        if pawn then collect(util.safe(function() return pawn[config.prop.commanded_squads] end, nil)) end
    end
    return ids, set
end

function M.units()
    local _, set = M.squads()
    local found = {}
    for _, unit in ipairs(util.safe(function() return FindAllOf("SMUnit") end, {})) do
        if util.valid(unit) then
            local id = util.safe(function() return handle_id(unit[config.prop.unit_squad]) end, nil)
            if id and set[id] then found[#found + 1] = unit end
        end
    end
    return found
end

return M
