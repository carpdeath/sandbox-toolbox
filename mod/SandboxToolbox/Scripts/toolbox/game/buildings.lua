local util = require("toolbox.core.util")
local player = require("toolbox.game.player")
local config = require("toolbox.config")

local M = {}

local cache = {}

local address = util.address

function M.engine()
    if not util.valid(cache.engine) then
        cache.engine = util.safe(function() return FindFirstOf(config.class.engine) end, nil)
    end
    return util.valid(cache.engine) and cache.engine or nil
end

function M.player_address()
    if not util.valid(cache.pawn) then cache.pawn = player.pawn() end
    return util.valid(cache.pawn) and address(cache.pawn) or nil
end

function M.list(name)
    local engine = M.engine()
    name = name or config.prop.building_list
    return engine and util.safe(function() return engine[name] end, nil)
end

function M.count(list) return util.length(list) end

function M.slice(list, first, last)
    local found = {}
    for i = first, last do
        local building = util.safe(function() return list[i] end, nil)
        if building and util.valid(building) then found[#found + 1] = building end
    end
    return found
end

function M.is_players(building, mine)
    local owner = util.safe(function() return building[config.prop.owner_pawn] end, nil)
    if not (mine and owner and util.valid(owner)) then return nil end
    return address(owner) == mine
end

function M.owned()
    local mine = M.player_address()
    if not mine then return {} end
    local found, seen = {}, {}
    for _, name in ipairs(config.prop.building_lists) do
        local list = M.list(name)
        for _, building in ipairs(M.slice(list, 1, M.count(list))) do
            local key = address(building)
            if key and not seen[key] then
                seen[key] = true
                if M.is_players(building, mine) then found[#found + 1] = building end
            end
        end
    end
    return found
end

return M
