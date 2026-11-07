local config = require("toolbox.config")
local cheats = require("toolbox.game.cheats")
local region = require("toolbox.game.region")
local util = require("toolbox.core.util")
local lists = require("toolbox.data.quick_lists")
local log = require("toolbox.core.log")

local M = {}

local FOOD_EACH, STAPLES_EACH = 50, 100

local function owned_manager()
    local r, why = region.require_owned()
    if not r then return nil, why end
    local cm = cheats.manager()
    if not cm then return nil, "Cheat manager is not up yet. Load a settlement, then try again." end
    return cm
end

function M.give(item, amount)
    local cm, why = owned_manager()
    if not cm then return why end
    if cm[config.fn.give_by_name] == nil then return "Give-item function unavailable. Load a settlement first." end
    cm[config.fn.give_by_name](cm, item, amount)
    return true
end

function M.feast()
    local cm, why = owned_manager()
    if not cm then return why end
    local variety = config.fn.give_food_variety
    local did_variety = cm[variety] ~= nil and pcall(cm[variety], cm)
    local foods = cheats.give_items(cm, lists.food, FOOD_EACH)
    if not did_variety and foods == nil then
        log.info("Feast: no food functions on " .. util.class_name(cm) .. ".")
        return "Feast: no food functions found."
    end
    local sent = {}
    if did_variety then sent[#sent + 1] = "food variety" end
    if foods ~= nil then sent[#sent + 1] = foods .. " foods x " .. FOOD_EACH end
    return "Feast: larder refilled (" .. table.concat(sent, ", ") .. ") -- granary space permitting."
end

function M.staples()
    local cm, why = owned_manager()
    if not cm then return why end
    local count = cheats.give_items(cm, lists.staples, STAPLES_EACH)
    if count == nil then
        log.info("Staples: '" .. config.fn.give_by_name .. "' not found on " .. util.class_name(cm))
        return "Staples: item function missing."
    end
    return "Staples: " .. count .. " goods x " .. STAPLES_EACH .. " requested -- storage space permitting."
end

return M
