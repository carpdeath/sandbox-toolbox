local config = require("toolbox.config")
local log = require("toolbox.core.log")
local M = {}
function M.install(api)
    local menu = require("ModMenu.ModMenu")
    require("toolbox.ui.window_drag").install()
    require("toolbox.ui.skin").install()
    require("toolbox.ui.field_style").install()
    require("toolbox.ui.menu_lifetime").install()
    require("toolbox.ui.section_cards").install()
    local grid = require("toolbox.ui.resource_grid")
    grid.register()
    local catalog = require("toolbox.data.catalog")
    local labels = {}
    for _, r in ipairs(catalog) do
        labels[r.value] = r.label
    end
    local function status(message)
        log.info(message)
        if api.notify then api.notify(message) end
    end
    local function run(fn)
        ExecuteInGameThread(function()
            local ok, result = pcall(fn)
            status(ok and (result or "Requested.") or ("Failed: " .. tostring(result)))
        end)
    end
    local function amount(section)
        local n = tonumber(menu.Get(section, "amount"))
        if not n or n ~= n or n < 1 or n > config.max_amount or n % 1 ~= 0 then
            error("Enter a whole amount from 1 to " .. config.max_amount .. ".")
        end
        return n
    end
    local function give(id)
        run(function()
            if not labels[id] then error("Unknown resource.") end
            local n = amount("Resources")
            local result = api.give(id, n)
            if result ~= true then return result end
            return "Requested " .. n .. " " .. labels[id] .. "."
        end)
    end
    local function currency(kind, n)
        run(function() return api.currency(kind, n or amount("Currency")) end)
    end
    if Key[config.panel_key] == nil then
        log.info("Unknown panel_key '" .. tostring(config.panel_key) .. "'; the panel will have no hotkey.")
    end
    menu.Init({
        title = "Sandbox Toolbox",
        instanceId = "SandboxToolbox",
        key = Key[config.panel_key],
        keyHint = config.panel_key_hint,
        dock = "right",
        theme = "dark",
        widthFrac = 0.34,
        topFrac = 0.25,
        bottomFrac = 0.25,
        tabs = { "General", "Resources", "Settlement", "Armies" },
        consoleCommand = "toolbox",
        fontTitle = 17,
        fontSection = 12,
        fontItem = 11,
        fontHint = 10,
        colors = {
            panelBg = { R = 0.80, G = 0.76, B = 0.66, A = 1 },
            panelBorder = { R = 0.20, G = 0.16, B = 0.11, A = 1 },
            textPrimary = { R = 0.17, G = 0.12, B = 0.07, A = 1 },
            textMuted = { R = 0.36, G = 0.30, B = 0.22, A = 1 },
            textAccent = { R = 0.93, G = 0.78, B = 0.45, A = 1 },
            sectionHeaderBg = { R = 0.17, G = 0.17, B = 0.18, A = 1 },
            sectionMark = { R = 0.85, G = 0.80, B = 0.68, A = 1 },
            buttonBg = { R = 0.58, G = 0.44, B = 0.26, A = 1 },
            buttonText = { R = 0.97, G = 0.94, B = 0.86, A = 1 },
            buttonBgActive = { R = 0.62, G = 0.30, B = 0.26, A = 1 },
            buttonTextActive = { R = 0.99, G = 0.95, B = 0.88, A = 1 },
            buttonBgDisabled = { R = 0.40, G = 0.38, B = 0.33, A = 1 },
            buttonTextDisabled = { R = 0.62, G = 0.59, B = 0.52, A = 1 },
            fieldBg = { R = 0.93, G = 0.90, B = 0.82, A = 1 },
            fieldText = { R = 0.13, G = 0.20, B = 0.33, A = 1 },
            fieldHint = { R = 0.45, G = 0.43, B = 0.38, A = 1 },
            dropdownHeaderBg = { R = 0.58, G = 0.44, B = 0.26, A = 1 },
            dropdownOptionBg = { R = 0.93, G = 0.90, B = 0.82, A = 1 },
            dropdownOptionText = { R = 0.14, G = 0.12, B = 0.09, A = 1 },
            confirmCardBg = { R = 0.80, G = 0.76, B = 0.66, A = 1 },
            confirmDivider = { R = 0.58, G = 0.44, B = 0.26, A = 1 },
        },
        canOpen = function()
            log.debug("Ready check begin")
            local done = log.timer("TIMING canOpen ready check")
            local ready = api.ready()
            done()
            log.debug("Ready check end")
            if not ready then return false, "Load a village first." end
            return true
        end,
    })
    local function button(id, label, fn, tooltip)
        return { type = "button", id = id, label = label, width = 170, fill = true, onClick = fn, tooltip = tooltip }
    end
    local familyTip = "Raises next month's migration: extra families\narrive at the start of the coming month."
    menu.Register({
        id = "Currency",
        tab = "General",
        title = "Currency",
        collapsible = true,
        collapsed = false,
        items = {
            {
                type = "number",
                id = "amount",
                label = "Amount to add",
                default = 1000,
                min = 1,
                max = config.max_amount,
                integer = true,
                fieldWidth = 200,
                labelWidth = 110,
                fill = true,
            },
            button("influence", "+ Influence", function() currency("influence") end),
            button("wealth", "+ Regional wealth", function() currency("wealth") end),
            button("treasury", "+ Treasury", function() currency("treasury") end),
        },
    })
    menu.Register({
        id = "Threats",
        tab = "General",
        title = "Threats",
        collapsible = true,
        collapsed = false,
        items = {
            {
                type = "row",
                items = {
                    button("banditcamp", "Spawn bandit camp", function() run(api.bandit_camp) end),
                    button("raiders", "Spawn raiders", function() run(api.raiders) end),
                },
            },
        },
    })
    menu.Register({
        id = "Resources",
        tab = "Resources",
        title = "Resources",
        collapsible = true,
        collapsed = false,
        items = {
            {
                type = "number",
                id = "amount",
                label = "Amount per click",
                default = 100,
                min = 1,
                max = config.max_amount,
                integer = true,
                fieldWidth = 200,
                labelWidth = 110,
                fill = true,
            },
            {
                type = "textinput",
                id = "search",
                label = "Search",
                default = "",
                placeholder = "Find a resource...",
                fieldWidth = 200,
                labelWidth = 110,
                fill = true,
                maxLength = 80,
            },
            {
                type = "resourcegrid",
                catalog = catalog,
                query = function() return menu.Get("Resources", "search") or "" end,
                onGive = give,
            },
        },
    })
    local function switch(section, id, fn, label)
        return {
            type = "checkbox",
            id = id,
            label = label,
            showState = false,
            default = false,
            onChange = function(on)
                ExecuteInGameThread(function()
                    local ok, message = pcall(fn, on)
                    if not ok and on then pcall(menu.Set, section, id, false) end
                    status(ok and (message or "Requested.") or ("Failed: " .. tostring(message)))
                end)
            end,
        }
    end
    menu.Register({
        id = "Quick",
        tab = "Settlement",
        title = "Quick actions",
        collapsible = true,
        collapsed = false,
        items = {
            {
                type = "row",
                items = {
                    button("food", "Add all food", function()
                        run(function() return api.quick("food") end)
                    end),
                    button("staples", "Add staple goods", function()
                        run(function() return api.quick("staples") end)
                    end),
                },
            },
            {
                type = "row",
                items = {
                    button(
                        "wealth",
                        "+" .. config.quick_wealth .. " wealth",
                        function() currency("wealth", config.quick_wealth) end
                    ),
                    button(
                        "treasury",
                        "+" .. config.quick_treasury .. " treasury",
                        function() currency("treasury", config.quick_treasury) end
                    ),
                },
            },
        },
    })
    menu.Register({
        id = "People",
        tab = "Settlement",
        title = "People",
        collapsible = true,
        collapsed = false,
        items = {
            {
                type = "row",
                items = {
                    button("family1", "+1 family next month", function()
                        run(function() return api.people(1) end)
                    end, familyTip),
                    button("family5", "+5 families next month", function()
                        run(function() return api.people(5) end)
                    end, familyTip),
                },
            },
        },
    })
    menu.Register({
        id = "Buildings",
        tab = "Settlement",
        title = "Buildings",
        collapsible = true,
        collapsed = false,
        items = {
            switch("Buildings", "storage", api.storage, "Big storage"),
            switch("Buildings", "construction", api.construction, "Instant construction"),
        },
    })
    local function toggle(id, fn, off, on)
        return button(id, off, function()
            ExecuteInGameThread(function()
                local ok, message, state = pcall(fn)
                if ok and state ~= nil then
                    menu.SetButtonLabel("Armies", id, state and on or off)
                    menu.SetButtonActive("Armies", id, state)
                end
                status(ok and (message or "Requested.") or ("Failed: " .. tostring(message)))
            end)
        end)
    end
    menu.Register({
        id = "Armies",
        tab = "Armies",
        title = "Armies",
        collapsible = true,
        collapsed = false,
        items = {
            toggle("militia", api.militia, "Unlock militia cap", "Lock militia cap"),
            switch("Armies", "immortal", api.immortal, "Immortal units"),
            switch("Armies", "op", api.op, "OP units (attack, ranged, armor piercing)"),
            switch("Armies", "stamina", api.stamina, "Infinite stamina"),
            switch("Armies", "morale", api.morale, "Infinite morale"),
        },
    })
    log.info("Panel ready (" .. config.panel_key_hint .. "): currency, threats, resources, settlement, armies.")
    return menu
end
return M
