local config = require("toolbox.config")
local util = require("toolbox.core.util")
local log = require("toolbox.core.log")
local bridge = require("toolbox.core.bridge")
local buildings = require("toolbox.game.buildings")
local region = require("toolbox.game.region")

local M = {}

local key_of = util.address

local state = {
    storage = false,
    construction = false,
    fertility = false,
    fertility_regions = {},
    fertility_rescan = 0,
    saved = {},
    fresh = {},
    redraw = {},
    pending = {},
    rescan = 0,
    seen = {},
    loop = false,
}

local function apply_storage(building)
    local key = key_of(building)
    if not key then return false end
    local entry = state.saved[key]
    local changed = false
    for _, field in ipairs(config.prop.storage_limits) do
        local current = util.number(building, field)
        if current and current > 0 and current < config.big_storage then
            if not entry then
                entry = { building = building, original = {} }
                state.saved[key] = entry
            end
            if entry.original[field] == nil then entry.original[field] = current end
            building[field] = config.big_storage
            changed = true
        end
    end
    return changed
end

local function restore_storage()
    local restored = 0
    for key, entry in pairs(state.saved) do
        if util.valid(entry.building) then
            for field, original in pairs(entry.original) do
                entry.building[field] = original
            end
            restored = restored + 1
        end
        state.saved[key] = nil
    end
    return restored
end

local function collect_new()
    local found = {}
    for _, name in ipairs(config.prop.building_lists) do
        local list = buildings.list(name)
        local n = buildings.count(list)
        local seen = state.seen[name] or n
        local first = n < seen and 1 or seen + 1
        for _, building in ipairs(buildings.slice(list, first, n)) do
            found[#found + 1] = building
        end
        state.seen[name] = n
    end
    return found
end

local function mark_seen()
    for _, name in ipairs(config.prop.building_lists) do
        state.seen[name] = buildings.count(buildings.list(name))
    end
end

local finish_construction = bridge.export("finish_construction", "finish", "Construction")
local unbuilt_buildings = bridge.export("unbuilt_buildings", "unbuilt", "Construction")

local function finish(list)
    if #list == 0 then return 0, {} end
    local hex = {}
    for _, building in ipairs(list) do
        local key = key_of(building)
        if key then hex[#hex + 1] = ("%x"):format(key) end
    end
    local result = finish_construction(table.concat(hex, " "))
    local finished, rest = result:match("^OK (%d+) %d+(.*)$")
    if not finished then error(bridge.failure(result, "Construction"), 0) end
    local done = {}
    for address in rest:gmatch("%x+") do
        done[tonumber(address, 16)] = true
    end
    return tonumber(finished), done
end

local function unbuilt()
    local list = buildings.list()
    local n = buildings.count(list)
    if n < 2 then return {} end
    local engine = buildings.engine()
    local first = util.safe(function() return list[1] end, nil)
    local second = util.safe(function() return list[2] end, nil)
    if not (engine and first and second) then return {} end
    local result = unbuilt_buildings(("%x %d %x %x"):format(key_of(engine), n, key_of(first), key_of(second)))
    local rest = result:match("^OK(.*)$")
    if not rest then error(bridge.failure(result, "Construction"), 0) end
    local mine, found = buildings.player_address(), {}
    for index in rest:gmatch("%d+") do
        local building = util.safe(function() return list[tonumber(index) + 1] end, nil)
        if building and util.valid(building) and buildings.is_players(building, mine) then
            found[#found + 1] = building
        end
    end
    return found
end

local function redraw(building)
    local sites = util.safe(function() return building[config.prop.sites] end, nil)
    local n = util.length(sites)
    local behind = 0
    for i = 1, n do
        local site = util.safe(function() return sites[i] end, nil)
        if
            site
            and util.valid(site)
            and util.safe(function() return site[config.prop.reverse_construction] end, false) ~= true
            and util.safe(function() return site[config.prop.collapsing] end, false) ~= true
        then
            local progress = util.safe(function() return site[config.prop.construction_progress] end, 0)
            if type(progress) ~= "number" or progress < 1.0 then behind = behind + 1 end
            pcall(function() site[config.prop.construction_progress] = 1.0 end)
            for _, name in ipairs(config.fn.construction_redraw) do
                pcall(function() site[name](site) end)
            end
        end
    end
    return n, behind
end

local function goods(building, field)
    local list = util.safe(function() return building[field] end, nil)
    local n = util.length(list)
    local out = {}
    for i = 1, n do
        local good = util.safe(function() return list[i] end, nil)
        local kind = good and util.safe(function() return good.Type end, nil)
        local amount = good and util.safe(function() return good.amt end, nil)
        out[#out + 1] = tostring(kind) .. "x" .. tostring(amount)
    end
    return table.concat(out, " "), list, n
end

local function clear_owed(building, key)
    local owed, list, n = goods(building, config.prop.construction_goods)
    log.debug(
        ("Instant construction: %x owes [%s], holds [%s]."):format(key, owed, (goods(building, config.prop.inventory)))
    )
    for i = 1, n do
        pcall(function() list[i].amt = 0 end)
    end
end

local function complete(list)
    for _, building in ipairs(list) do
        local key = key_of(building)
        if key then pcall(clear_owed, building, key) end
    end
    local finished, done = finish(list)
    for _, building in ipairs(list) do
        local key = key_of(building)
        if key and done[key] then
            local n = redraw(building)
            log.debug(("Instant construction: finished %x with %d scaffolds."):format(key, n))
            state.redraw[key] = { building = building, calm = 0, age = 0 }
        end
    end
    return finished
end

local function settled(list)
    local ready, now = {}, {}
    for _, building in ipairs(list) do
        local key = key_of(building)
        if key then
            local age = (state.pending[key] or 0) + 1
            now[key] = age
            local sites = util.safe(function() return building[config.prop.sites] end, nil)
            local scaffolds = util.length(sites)
            if (scaffolds > 0 and age > config.finish_delay_ticks) or age > config.finish_wait_ticks then
                ready[#ready + 1] = building
            end
        end
    end
    state.pending = now
    return ready
end

local function redraw_pass()
    for key, entry in pairs(state.redraw) do
        local valid = util.valid(entry.building)
        local n, behind = 0, 0
        if valid then
            n, behind = redraw(entry.building)
        end
        entry.age = entry.age + 1
        entry.calm = (n > 0 and behind == 0) and entry.calm + 1 or 0
        if behind > 0 then
            log.debug(
                ("Instant construction: %x had %d of %d scaffolds behind (tick %d)."):format(key, behind, n, entry.age)
            )
        end
        if not valid or entry.calm >= config.redraw_ticks or entry.age >= config.redraw_max_ticks then
            state.redraw[key] = nil
        end
    end
end

local function storage_pass()
    local n = 0
    for _, building in ipairs(buildings.owned()) do
        if apply_storage(building) then n = n + 1 end
    end
    return n
end

local function fresh_pass()
    local new = collect_new()
    if #new > 0 then log.debug(("Settlement: %d new buildings in the engine list."):format(#new)) end
    for _, building in ipairs(new) do
        local key = key_of(building)
        if key and not state.fresh[key] then state.fresh[key] = { building = building, age = 0 } end
    end
    if not next(state.fresh) then return end
    local player = buildings.player_address()
    local mine = {}
    for key, entry in pairs(state.fresh) do
        local owned = util.valid(entry.building) and buildings.is_players(entry.building, player)
        entry.age = entry.age + 1
        if owned then mine[#mine + 1] = entry.building end
        if owned ~= nil or entry.age > config.owner_wait_ticks or not util.valid(entry.building) then
            state.fresh[key] = nil
        end
    end
    if #mine == 0 then return end
    log.debug(("Settlement: %d new buildings of yours."):format(#mine))
    for _, building in ipairs(mine) do
        pcall(apply_storage, building)
    end
end

local force_fertility = bridge.export("force_fertility", "fertility", "Fertility")

local function refresh_fertility_regions()
    local hex = {}
    for _, r in ipairs(region.owned()) do
        hex[#hex + 1] = ("%x"):format(key_of(r))
    end
    table.sort(hex)
    state.fertility_regions = hex
end

local function apply_fertility(on)
    local actor = buildings.engine()
    if not actor then error("Game engine actor not found. Load a village first.", 0) end
    local request = ("%x %d %s"):format(key_of(actor), on and 1 or 0, table.concat(state.fertility_regions, " "))
    local result = force_fertility(request)
    local cells, rebuilt = result:match("^OK (%d+) (%d)")
    if not cells then error(bridge.failure(result, "Fertility"), 0) end
    if rebuilt == "1" then pcall(function() actor[config.fn.redraw_fertility](actor) end) end
    return tonumber(cells)
end

local function fertility_pass()
    state.fertility_rescan = state.fertility_rescan + 1
    if state.fertility_rescan >= config.fertility_rescan_ticks then
        state.fertility_rescan = 0
        refresh_fertility_regions()
    end
    apply_fertility(true)
end

local function count(map)
    local n = 0
    for _ in pairs(map) do
        n = n + 1
    end
    return n
end

local function tick()
    if config.debug and (state.storage or state.construction) then
        local sizes = {}
        for _, name in ipairs(config.prop.building_lists) do
            sizes[#sizes + 1] = name .. " " .. buildings.count(buildings.list(name))
        end
        log.debug(
            ("Settlement tick: %s; waiting for owner %d, redrawing %d."):format(
                table.concat(sizes, ", "),
                count(state.fresh),
                count(state.redraw)
            )
        )
    end
    local done = log.timer("Settlement tick")
    if state.storage then pcall(fresh_pass) end
    if state.construction then
        local ok, err = pcall(function() complete(settled(unbuilt())) end)
        if not ok then log.debug("Instant construction tick failed: " .. tostring(err)) end
    end
    if next(state.redraw) then pcall(redraw_pass) end
    if state.fertility then
        local ok, err = pcall(fertility_pass)
        if not ok then log.debug("Fertility tick failed: " .. tostring(err)) end
    end
    done()
    if state.storage then
        state.rescan = state.rescan + 1
        if state.rescan >= config.storage_rescan_ticks then
            state.rescan = 0
            pcall(storage_pass)
        end
    end
    return false
end

local function ensure_loop()
    if state.loop or not LoopInGameThreadWithDelay then return end
    state.loop = true
    M._tick = tick
    LoopInGameThreadWithDelay(config.settlement_refresh_ms, M._tick)
end

function M.set_storage(on)
    state.storage = on
    if not on then
        local n = restore_storage()
        return n == 0 and "Big storage off." or ("Big storage off (%d buildings restored)."):format(n)
    end
    mark_seen()
    ensure_loop()
    local n = storage_pass()
    return ("Big storage on: storage limits set to %d on %d buildings."):format(config.big_storage, n)
end

function M.set_construction(on)
    if not on then
        state.construction = false
        return "Instant construction off."
    end
    local done = log.timer("Instant construction first pass")
    local finished = complete(unbuilt())
    done()
    state.construction = true
    ensure_loop()
    return ("Instant construction on (%d buildings finished now)."):format(finished)
end

function M.set_fertility(on)
    if not on then
        state.fertility = false
        apply_fertility(false)
        return "100% fertility off (original fertility restored)."
    end
    refresh_fertility_regions()
    if #state.fertility_regions == 0 then error("No lands of yours found. Load a village first.", 0) end
    local cells = apply_fertility(true)
    state.fertility = true
    state.fertility_rescan = 0
    ensure_loop()
    return ("100%% fertility on (%d cells)."):format(cells)
end

local function engine()
    local actor = buildings.engine()
    if not actor then error("Game engine actor not found. Load a village first.", 0) end
    return actor
end

local function call(name, ...)
    local actor = engine()
    local fn = actor[name]
    if fn == nil then error("This game build has no " .. name .. ".", 0) end
    local args = table.pack(...)
    local ok, err = pcall(function() fn(actor, table.unpack(args, 1, args.n)) end)
    if not ok then error(name .. " failed: " .. tostring(err), 0) end
end

function M.spawn_bandit_camp()
    call(config.fn.spawn_bandit_camp)
    return "Bandit camp spawned."
end

function M.spawn_raiders()
    call(config.fn.spawn_raiders, config.raider_squads, { X = 0, Y = 0, Z = 0 })
    return ("Raiders spawned (%d squads)."):format(config.raider_squads)
end

return M
