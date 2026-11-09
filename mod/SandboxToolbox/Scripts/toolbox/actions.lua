local region = require("toolbox.game.region")
local util = require("toolbox.core.util")
local feedback = require("toolbox.game.feedback")
local currency = require("toolbox.features.currency")
local resources = require("toolbox.features.resources")
local armies = require("toolbox.features.armies")
local settlement = require("toolbox.features.settlement")

local M = {}

function M.build()
    return {
        ready = function() return util.valid((region.target())) end,
        notify = feedback.flash,
        quick = function(kind)
            if kind == "food" then return resources.feast() end
            return resources.staples()
        end,
        people = function(count) return require("toolbox.features.people").queue(count) end,
        currency = currency.add,
        give = resources.give,
        militia = armies.toggle_militia,
        immortal = armies.set_immortal,
        morale = armies.set_morale,
        op = armies.set_op,
        stamina = armies.set_stamina,
        storage = settlement.set_storage,
        construction = settlement.set_construction,
        fertility = settlement.set_fertility,
        bandit_camp = settlement.spawn_bandit_camp,
        raiders = settlement.spawn_raiders,
    }
end

return M
