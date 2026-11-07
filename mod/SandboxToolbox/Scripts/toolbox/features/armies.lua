local config = require("toolbox.config")
local paths = require("toolbox.core.paths")
local bridge = require("toolbox.core.bridge")
local log = require("toolbox.core.log")
local util = require("toolbox.core.util")
local player = require("toolbox.game.player")
local army = require("toolbox.game.army")

local M = {}

local MAX_SQUADS = 512

local state = {
    damage = 1.0,
    morale = false,
    op = false,
    stamina = false,
    saved = {},
    stamina_full = 0,
    loop = false,
    seen = 0,
    mine = 0,
}

function M.toggle_militia()
    local pawn = player.pawn()
    if not pawn then return "Load a village first." end
    local field = config.prop.militia_cap
    local current = util.safe(function() return pawn[field] end, nil)
    if type(current) ~= "number" then return "Militia cap unavailable on this build." end
    local unlock = current <= config.militia_default
    local target = unlock and config.militia_unlocked or config.militia_default
    pawn[field] = target
    local now = util.safe(function() return pawn[field] end, nil)
    if now ~= target then return "Could not change the militia cap (still " .. tostring(now) .. ")." end
    return "Militia cap: " .. current .. " -> " .. now .. (unlock and " (unlocked)." or " (locked)."), unlock
end

local set_damage_scale = bridge.export("set_damage_scale", "damage", "Damage")

local function call_bridge(ids, mult)
    assert(paths.scripts_dir ~= "", "Could not locate the mod Scripts directory.")
    local list = {}
    for i = 1, math.min(#ids, MAX_SQUADS) do
        list[i] = tostring(ids[i])
    end
    local result = set_damage_scale(("%.4f %d %s"):format(mult, #list, table.concat(list, " ")))
    local squads, seen, mine = result:match("^OK %S+ (%d+) (%d+) (%d+)$")
    if not squads then return nil, bridge.failure(result, "Damage") end
    return { squads = tonumber(squads), seen = tonumber(seen), mine = tonumber(mine) }
end

local function push_damage()
    local ids = army.squads()
    local info, why = call_bridge(ids, state.damage)
    if not info then error(why, 0) end
    if info.mine ~= state.mine or info.seen ~= state.seen then
        log.debug(("Damage bridge: %d hits seen, %d on your squads."):format(info.seen, info.mine))
        state.seen, state.mine = info.seen, info.mine
    end
    return info, #ids
end

local function entry_for(unit)
    local address = util.address(unit)
    if not address then return nil end
    local entry = state.saved[address]
    if not entry then
        entry = { unit = unit, original = {} }
        state.saved[address] = entry
    end
    return entry
end

local function raise(entry, field, target_of)
    local current = util.number(entry.unit, field)
    if not current then return false end
    local fresh = entry.original[field] == nil
    if fresh then entry.original[field] = current end
    local target = target_of(entry.original[field])
    if current < target then entry.unit[field] = target end
    return fresh
end

local function apply_morale(entry)
    return raise(entry, config.prop.morale, function(v) return v + config.morale_boost end)
end

local function apply_op(entry)
    local fresh = false
    for _, field in ipairs(config.prop.op_stats) do
        if raise(entry, field, function(v) return math.max(v * config.op_multiplier, config.op_minimum) end) then
            fresh = true
        end
    end
    return fresh
end

local function apply_stamina(entry)
    local field = config.prop.stamina
    local current = util.number(entry.unit, field)
    if not current then return false end
    if current > state.stamina_full then state.stamina_full = current end
    if current < state.stamina_full then entry.unit[field] = state.stamina_full end
    return false
end

local function each_unit(fn)
    for address, entry in pairs(state.saved) do
        if not util.valid(entry.unit) then state.saved[address] = nil end
    end
    local count, fresh = 0, 0
    for _, unit in ipairs(army.units()) do
        local entry = entry_for(unit)
        if entry then
            count = count + 1
            if fn(entry) then fresh = fresh + 1 end
        end
    end
    return count, fresh
end

local function restore(fields, lower_only)
    local restored = 0
    for _, entry in pairs(state.saved) do
        local touched = false
        for _, field in ipairs(fields) do
            local original = entry.original[field]
            if original ~= nil then
                if util.valid(entry.unit) then
                    local current = util.number(entry.unit, field)
                    if current then
                        entry.unit[field] = lower_only and math.min(current, original) or original
                        touched = true
                    end
                end
                entry.original[field] = nil
            end
        end
        if touched then restored = restored + 1 end
    end
    return restored
end

local function tick()
    if state.damage ~= 1.0 then pcall(push_damage) end
    if state.morale then pcall(each_unit, apply_morale) end
    if state.op then pcall(each_unit, apply_op) end
    if state.stamina then pcall(each_unit, apply_stamina) end
    return false
end

local function ensure_loop()
    if state.loop or not LoopInGameThreadWithDelay then return end
    state.loop = true
    M._tick = tick
    LoopInGameThreadWithDelay(config.army_refresh_ms, M._tick)
end

local function no_units(count)
    return count == 0 and " No units of yours yet; applies as soon as you have an army." or ""
end

function M.set_immortal(on)
    local previous = state.damage
    state.damage = on and 0.0 or 1.0
    local ok, info, squads = pcall(push_damage)
    if not ok then
        state.damage = previous
        error(info, 0)
    end
    if not on then return "Your units can be killed again." end
    ensure_loop()
    local text = ("Your units are immortal in combat (%d squads)."):format(squads)
    if squads == 0 then text = text .. " No squads found yet; applies once you have an army." end
    if info.mine == 0 and info.seen > 0 then text = text .. " Hits seen but none on your squads." end
    return text
end

function M.set_morale(on)
    state.morale = on
    if not on then
        local n = restore({ config.prop.morale }, true)
        return n == 0 and "Infinite morale off." or ("Infinite morale off (%d units restored)."):format(n)
    end
    ensure_loop()
    local count = each_unit(apply_morale)
    return ("Infinite morale on: +%d morale on %d units."):format(config.morale_boost, count) .. no_units(count)
end

function M.set_op(on)
    state.op = on
    if not on then
        local n = restore(config.prop.op_stats, false)
        return n == 0 and "OP units off." or ("OP units off (%d units restored)."):format(n)
    end
    ensure_loop()
    local count = each_unit(apply_op)
    return ("OP units on: attack, ranged attack and armor piercing x%d on %d units."):format(
        config.op_multiplier,
        count
    ) .. no_units(count)
end

function M.set_stamina(on)
    state.stamina = on
    if not on then return "Infinite stamina off." end
    ensure_loop()
    local count = each_unit(apply_stamina)
    return ("Infinite stamina on (%d units)."):format(count) .. no_units(count)
end

return M
