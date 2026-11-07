local config = {
    debug = false,

    skin = true,
    skin_fonts = true,

    flash_speed = 0.8,

    panel_key = "F6",
    panel_key_hint = "F6",

    quick_wealth = 1000,
    quick_treasury = 1000,

    max_amount = 1000000,

    militia_default = 6,
    militia_unlocked = 99,
    morale_boost = 1000,
    op_multiplier = 10,
    op_minimum = 100,
    army_refresh_ms = 1000,

    big_storage = 100000,
    settlement_refresh_ms = 500,
    storage_rescan_ticks = 20,
    finish_delay_ticks = 2,
    finish_wait_ticks = 20,
    redraw_ticks = 10,
    redraw_max_ticks = 120,
    owner_wait_ticks = 10,
    raider_squads = 3,

    class = {
        engine = "RTSMultiEngineCPP",
        building = "SMBuildingMaster",
    },

    prop = {
        militia_cap = "maxNumOfMilitiaToSpawn",
        morale = "morale",
        stamina = "stamina",
        op_stats = { "baseAttack", "att", "rangedAtt", "armorPierce" },
        unit_squad = "assignedSquadID",
        squad_order = "PlayerSquadUIOrder",
        commanded_squads = "commandedSquads",
        owner_pawn = "ownerPawn",
        building_list = "buildingArr",
        building_lists = { "buildingArr", "independentBuildings", "lazyBuildings" },
        sites = "buildings",
        construction_progress = "constructionProgress",
        reverse_construction = "reverseConstruction",
        collapsing = "isCollapsing",
        storage_limits = { "storageLimitGeneric", "storageLimitLarge", "storageLimitPantry" },
        construction_goods = "constructionGoods",
        inventory = "Inventory",
    },

    fn = {
        change_treasury = "ChangeTreasury",
        give_by_name = "GiveItemByName",
        give_food_variety = "GiveFoodVariety",
        add_region_gold = "addRegionalWealth",
        change_influence = "changeInfluence",
        spawn_bandit_camp = "spawnBanditCamp",
        construction_redraw = {
            "updateConstructionLevel",
            "updateElementVisibilityCommon",
            "updateBoardVisibilityFast",
        },
        spawn_raiders = "spawnRaiders",
    },
}

return config
