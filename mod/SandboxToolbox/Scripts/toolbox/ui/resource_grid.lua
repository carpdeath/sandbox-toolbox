local log = require("toolbox.core.log")
local skin = require("toolbox.ui.skin")
local M = { type = "resourcegrid" }
local TILE_REST = { R = 0.85, G = 0.85, B = 0.85, A = 1 }
local TILE_HOVER = { R = 1, G = 1, B = 1, A = 1 }
local categories = { "Food", "Construction", "Crafting materials", "Commodities", "Military" }
local groups = {
    Food = "apples Beef Beetroots Berries Cabbages Carrots Cheese Chevon ChickenMeat Eel Eggs fish lebkuchen Honey meat Milk mushrooms Mutton Pastries Pears Pork Quinces RyeBread sausage smokedfish vegetables Venison WheatBread zweiback",
    Construction = "Timber planks Rubble RoughStone DressedStone Mortar clayTILES WoodenParts Irontools",
    Military = "spears weapons_sidearms weapons_polearms warbows crossbows shields_small shields_large militia_helmets_resource gambesons mail_armor PlateArmor",
    ["Crafting materials"] = "WheatGrain RyeGrain OatGrain WheatFlour RyeFlour WheatSheaves RyeSheaves OatSheaves Malt Barley Flax Hides Leather Pelts Wool Cloth_Linen Yarn dyes Wax Salt Herbs Spices Clay IronOre IronSlabs iron_parts Dung",
    Commodities = "Firewood Charcoal Clothes Shoes Ale mead cider Fertilizer AnimalFeed",
}
M.groups = groups
local categoryOf = {}
for name, words in pairs(groups) do
    for token in words:gmatch("%S+") do
        categoryOf[token] = name
    end
end
M.categoryOf = categoryOf
local function group(id) return categoryOf[id] or "Food" end
function M.filter(catalog, query)
    query = tostring(query or ""):lower():match("^%s*(.-)%s*$")
    local out = {}
    for _, item in ipairs(catalog) do
        if query == "" or item.label:lower():find(query, 1, true) or item.value:lower():find(query, 1, true) then
            out[#out + 1] = item
        end
    end
    return out, query ~= ""
end
local function normalized(s) return s:lower():gsub("[^a-z0-9]", "") end
local textures
local function discover()
    if textures then return end
    textures = {}
    local ok, all = pcall(FindAllOf, "Texture2D")
    if not ok or type(all) ~= "table" then return end
    for _, texture in ipairs(all) do
        pcall(function()
            local name = texture:GetFName():ToString()
            local path = texture:GetFullName():lower()
            if path:find("icon", 1, true) or path:find("ui/", 1, true) or path:find("interface", 1, true) then
                local key = name:lower()
                for _ = 1, 5 do
                    key = key:gsub("^t_", "")
                        :gsub("^icon_", "")
                        :gsub("^item_", "")
                        :gsub("^resource_", "")
                        :gsub("^ui_", "")
                        :gsub("^tex_", "")
                end
                key = key:gsub("_icon$", ""):gsub("_texture$", "")
                textures[normalized(key)] = texture
            end
        end)
    end
end
local function liveTexture(key, stale)
    local texture = textures[key]
    if texture == nil then return nil end
    local ok, valid = pcall(function() return texture:IsValid() end)
    if ok and valid == true then return texture end
    stale.hit = true
end
function M.validate(item) assert(type(item.catalog) == "table" and type(item.onGive) == "function") end
function M.build(ctx)
    local U, Button = ctx.umg, require("ModMenu.widgets.button")
    local item, prefix = ctx.item, ctx.namePrefix
    local doneDiscover = log.timer("TIMING grid texture scan (0 when cached)")
    discover()
    doneDiscover()
    local doneGrid = log.timer("TIMING grid build total")
    local iconMs = 0
    local stale = {}
    local icons = require("toolbox.ui.icons")
    icons.begin()
    log.debug("Grid build: started")
    local root = U.Construct("/Script/UMG.VerticalBox", ctx.contentBox, prefix .. "_Root")
    U.AddToContent(ctx, root)
    local serial = 0
    local function make(class, outer, suffix)
        serial = serial + 1
        return U.Construct("/Script/UMG." .. class, outer, prefix .. "_" .. suffix .. serial)
    end
    local controls = {}
    local collapsed = {}
    local function font(text, points)
        pcall(function() text.Font.Size = points end)
    end
    local function flat(button)
        for _, state in ipairs({ "Normal", "Hovered", "Pressed", "Disabled" }) do
            pcall(function() button.WidgetStyle[state].DrawAs = 0 end)
        end
    end
    local function clickButton(parent, label, id, click)
        local button, text = U.CreateTextButton(parent, prefix .. "_" .. id, label)
        local entry = {
            kind = "button",
            sectionId = ctx.section.id,
            item = { id = id, label = label, onClick = click },
            widget = button,
            labelWidget = text,
            enabled = true,
            wasPressed = false,
        }
        Button.applyChrome(entry, ctx)
        flat(button)
        ctx.liveControls[#ctx.liveControls + 1] = entry
        return button, text
    end
    local function tiles(parent, list, suffix)
        local wrap = make("WrapBox", parent, suffix)
        parent:AddChildToVerticalBox(wrap)
        local entries = {}
        for _, resource in ipairs(list) do
            local r = resource
            local size = make("SizeBox", wrap, "Tile")
            size:SetWidthOverride(66)
            size:SetHeightOverride(66)
            local slot = wrap:AddChildToWrapBox(size)
            pcall(function() slot:SetPadding({ Left = 2, Top = 2, Right = 2, Bottom = 2 }) end)
            local card = make("Border", size, "Card")
            size:AddChild(card)
            card:SetBrushColor({ R = 0.09, G = 0.09, B = 0.10, A = 1 })
            local textured = skin.paint(card, "tile", TILE_REST)
            pcall(function() card:SetPadding({ Left = 4, Top = 4, Right = 4, Bottom = 4 }) end)
            local button, label = clickButton(card, r.label, suffix .. r.value, function() item.onGive(r.value) end)
            card:AddChild(button)
            font(label, 9)
            U.EnableAutoWrap(label)
            pcall(function() label:SetWrapTextAt(48) end)
            pcall(function() label:SetJustification(1) end)
            pcall(function()
                label:SetClipping(1)
                button:SetClipping(1)
                size:SetClipping(1)
            end)
            controls[#controls + 1] =
                { widget = button, card = card, hovered = false, name = r.label, textured = textured }
            pcall(function() button:SetToolTipText(FText(r.label)) end)
            local t0 = os.clock()
            local texture = icons.get(r.value)
                or liveTexture(normalized(r.value), stale)
                or liveTexture(normalized(r.label), stale)
            iconMs = iconMs + (os.clock() - t0) * 1000
            if texture then
                pcall(function()
                    local fit = make("ScaleBox", button, "IconFit")
                    fit:SetStretch(2)
                    local image = make("Image", fit, "Icon")
                    image:SetBrushFromTexture(texture, true)
                    fit:AddChild(image)
                    button:ClearChildren()
                    button:AddChild(fit)
                    pcall(function()
                        fit.Slot:SetHorizontalAlignment(0)
                        fit.Slot:SetVerticalAlignment(0)
                    end)
                    fit:SetVisibility(4)
                    image:SetVisibility(4)
                end)
            end
            entries[#entries + 1] = { size = size, resource = r }
        end
        return wrap, entries
    end
    local state = { searching = false }
    local catRoot = make("VerticalBox", root, "Categories")
    root:AddChildToVerticalBox(catRoot)
    local cats = {}
    for _, category in ipairs(categories) do
        log.debug("Grid build: " .. category)
        local list = {}
        for _, r in ipairs(item.catalog) do
            if group(r.value) == category then list[#list + 1] = r end
        end
        local categoryCard = make("Border", catRoot, "CategoryCard")
        categoryCard:SetBrushColor({ R = 0, G = 0, B = 0, A = 0 })
        categoryCard:SetPadding({ Left = 8, Top = 0, Right = 8, Bottom = 8 })
        local categorySlot = catRoot:AddChildToVerticalBox(categoryCard)
        categorySlot:SetPadding({ Left = 0, Top = 0, Right = 0, Bottom = 8 })
        local categoryRoot = make("VerticalBox", categoryCard, "CategoryRoot")
        categoryCard:AddChild(categoryRoot)
        local content
        local header, label
        collapsed[category] = true
        local function setArrow(open) U.SetLabelText(label, (open and "v  " or ">  ") .. category) end
        header, label = clickButton(categoryRoot, ">  " .. category, "category" .. category:gsub("%s", ""), function()
            if state.searching then return end
            collapsed[category] = not collapsed[category]
            content:SetVisibility(collapsed[category] and 1 or 0)
            setArrow(not collapsed[category])
        end)
        font(label, 11)
        skin.band(header, { R = 0.40, G = 0.38, B = 0.35, A = 1 })
        pcall(function() label:SetJustification(0) end)
        pcall(function() header.Slot:SetHorizontalAlignment(0) end)
        local headingSize = make("SizeBox", categoryRoot, "Heading")
        headingSize:SetHeightOverride(26)
        headingSize:AddChild(header)
        local headingSlot = categoryRoot:AddChildToVerticalBox(headingSize)
        pcall(function() headingSlot:SetPadding({ Left = 2, Top = 8, Right = 0, Bottom = 2 }) end)
        pcall(function() label.Slot:SetHorizontalAlignment(0) end)
        local entries
        content, entries = tiles(categoryRoot, list, "Cat" .. category:gsub("%s", ""))
        content:SetVisibility(1)
        cats[#cats + 1] =
            { name = category, card = categoryCard, content = content, entries = entries, setArrow = setArrow }
    end
    local empty = make("TextBlock", catRoot, "Empty")
    U.SetLabelText(empty, "No resources match your search.")
    catRoot:AddChildToVerticalBox(empty)
    empty:SetVisibility(1)
    icons.report()
    log.debug(string.format("TIMING grid icon lookups (%d tiles): %.1f ms", #item.catalog, iconMs))
    doneGrid()
    if stale.hit then textures = nil end
    log.debug("Grid build: complete")
    ctx.liveControls[#ctx.liveControls + 1] = {
        kind = "resourcegrid",
        item = item,
        cats = cats,
        collapsed = collapsed,
        state = state,
        empty = empty,
        lastQuery = "",
        hoverControls = controls,
    }
end
function M.poll(ctrl)
    ctrl.hoverTick = (ctrl.hoverTick or 0) + 1
    if ctrl.hoverTick % 4 == 0 then
        local hoverName
        for _, tile in ipairs(ctrl.hoverControls or {}) do
            local ok, hovered = pcall(function() return tile.widget:IsHovered() end)
            hovered = ok and hovered == true
            if hovered then hoverName = tile.name end
            if hovered ~= tile.hovered then
                tile.hovered = hovered
                pcall(
                    function()
                        tile.card:SetBrushColor(
                            tile.textured and (hovered and TILE_HOVER or TILE_REST)
                                or hovered and { R = 0.30, G = 0.27, B = 0.20, A = 1 }
                                or { R = 0.09, G = 0.09, B = 0.10, A = 1 }
                        )
                    end
                )
            end
        end
        require("toolbox.ui.window_drag").showTooltip(hoverName, "grid")
    end
    local query = ctrl.item.query()
    query = tostring(query or "")
    if ctrl.lastQuery == query then return end
    local matched, searching = M.filter(ctrl.item.catalog, query)
    ctrl.lastQuery = query
    ctrl.state.searching = searching
    local keep = {}
    for _, r in ipairs(matched) do
        keep[r.value] = true
    end
    for _, cat in ipairs(ctrl.cats) do
        local shown = 0
        for _, tile in ipairs(cat.entries) do
            local show = not searching or keep[tile.resource.value] == true
            tile.size:SetVisibility(show and 0 or 1)
            if show then shown = shown + 1 end
        end
        local open = searching or not ctrl.collapsed[cat.name]
        cat.card:SetVisibility((searching and shown == 0) and 1 or 0)
        cat.content:SetVisibility(open and 0 or 1)
        cat.setArrow(open)
    end
    ctrl.empty:SetVisibility((searching and #matched == 0) and 0 or 1)
end
function M.register()
    local registry = require("ModMenu.widgets.init")
    local get, has = registry.get, registry.has
    registry.get = function(t)
        if t == M.type then return M end
        return get(t)
    end
    registry.has = function(t) return t == M.type or has(t) end
end
return M
