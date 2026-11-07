local config = require("toolbox.config")
local log = require("toolbox.core.log")
local paths = require("toolbox.data.ui_textures")
local M = {}
local cache = {}
local WHITE = { R = 1, G = 1, B = 1, A = 1 }
local function valid(o)
    local ok, result = pcall(function() return o and o:IsValid() end)
    return ok and result == true
end
function M.texture(key)
    if not config.skin or not paths[key] then return nil end
    local object = cache[key]
    if object == false then return nil end
    if object and valid(object) then return object end
    local ok, found = pcall(StaticFindObject, paths[key])
    if not (ok and valid(found)) then
        local loaded, asset = pcall(LoadAsset, paths[key])
        found = loaded and asset or nil
    end
    object = valid(found) and found or false
    cache[key] = object
    if not object then log.info("Skin asset not found: " .. key .. " (" .. paths[key] .. ")") end
    return object or nil
end
local function isMaterial(object)
    local ok, name = pcall(function() return object:GetFullName() end)
    return ok and tostring(name):find("^Material") ~= nil
end
function M.paint(border, key, tint)
    local object = M.texture(key)
    if not object then return false end
    local ok = pcall(function()
        if isMaterial(object) then
            border:SetBrushFromMaterial(object)
        else
            border:SetBrushFromTexture(object)
        end
        border:SetBrushColor(tint or WHITE)
    end)
    return ok
end
local function setBrush(brush, object, draw, margin)
    brush.DrawAs = draw
    if margin then
        if type(margin) == "number" then margin = { margin, margin, margin, margin } end
        brush.Margin.Left = margin[1]
        brush.Margin.Top = margin[2]
        brush.Margin.Right = margin[3]
        brush.Margin.Bottom = margin[4]
    end
    brush.ResourceObject = object
end
local SETS = {
    castle = { keys = { "button_normal", "button_hover", "button_pressed", "button_disabled" }, draw = 3 },
    castleTexture = {
        keys = { "button_tex_normal", "button_tex_hover", "button_tex_pressed", "button_tex_disabled" },
        draw = 1,
        margin = { 0.09, 0.2, 0.09, 0.2 },
    },
    exit = { keys = { "exit_normal", "exit_hover", "exit_pressed", "exit_normal" }, draw = 1, margin = 0.3 },
}
local STATES = { "Normal", "Hovered", "Pressed", "Disabled" }
local function apply(button, set)
    local art = {}
    for i, key in ipairs(set.keys) do
        art[i] = M.texture(key)
    end
    if not art[1] then return false end
    for i, state in ipairs(STATES) do
        pcall(function() setBrush(button.WidgetStyle[state], art[i] or art[1], set.draw, set.margin) end)
    end
    pcall(function() button:SetBackgroundColor(WHITE) end)
    return true
end
function M.button(button, kind)
    if kind == "exit" then return apply(button, SETS.exit) end
    return apply(button, SETS.castle) or apply(button, SETS.castleTexture)
end
function M.band(button, tint)
    local material = M.texture("band")
    if not material then return false end
    for _, state in ipairs(STATES) do
        pcall(function() setBrush(button.WidgetStyle[state], material, 3) end)
    end
    pcall(function() button:SetBackgroundColor(tint or WHITE) end)
    return true
end
function M.ribbon(border, key) return M.paint(border, key) or M.paint(border, key .. "_fallback") end
local TAB_INK = { R = 0.14, G = 0.11, B = 0.08, A = 1 }
function M.font(label, key)
    if not config.skin_fonts then return end
    local font = M.texture(key)
    if font then pcall(function() label.Font.FontObject = font end) end
end
local TAB_ACTIVE = { R = 0.55, G = 0.14, B = 0.10, A = 1 }
function M.tab(button, label, active)
    local rest = M.texture(active and "tab_selected" or "tab")
    local draw, margin = 3, nil
    if not rest then
        rest = M.texture(active and "tab_selected_fallback" or "tab_fallback")
        draw, margin = 1, { 0.4, 0.4, 0.4, 0 }
    end
    if rest then
        local hover = (not active and draw == 3 and M.texture("tab_hover")) or rest
        for _, state in ipairs(STATES) do
            pcall(
                function() setBrush(button.WidgetStyle[state], state == "Hovered" and hover or rest, draw, margin) end
            )
        end
        pcall(function() button:SetBackgroundColor(WHITE) end)
    end
    pcall(function() require("ModMenu.core.umg").StyleText(label, 14, active and TAB_ACTIVE or TAB_INK) end)
    M.font(label, "font_heading")
    return rest ~= nil
end
function M.closeIcon(button)
    local icon = M.texture("icon_close")
    if not icon then return false end
    local U = require("ModMenu.core.umg")
    return pcall(function()
        local size = U.Construct("/Script/UMG.SizeBox", button, "Toolbox_CloseSize")
        size:SetWidthOverride(22)
        size:SetHeightOverride(22)
        local image = U.Construct("/Script/UMG.Image", size, "Toolbox_CloseIcon")
        image:SetBrushFromTexture(icon, false)
        size:AddChild(image)
        image:SetVisibility(4)
        size:SetVisibility(4)
        button:SetContent(size)
        button:SetPadding({ Left = 7, Top = 5, Right = 7, Bottom = 5 })
    end)
end
local CHECK_SIZE = 24
local CHECK_STATES = {
    Unchecked = { "UncheckedImage", "UncheckedHoveredImage", "UncheckedPressedImage" },
    Checked = {
        "CheckedImage",
        "CheckedHoveredImage",
        "CheckedPressedImage",
        "UndeterminedImage",
        "UndeterminedHoveredImage",
        "UndeterminedPressedImage",
    },
}
function M.checkbox(check)
    local on, off = M.texture("checkbox_on"), M.texture("checkbox_off")
    if not (on and off) then return false end
    for kind, fields in pairs(CHECK_STATES) do
        for _, field in ipairs(fields) do
            pcall(function()
                local brush = check.WidgetStyle[field]
                setBrush(brush, kind == "Checked" and on or off, 3)
                brush.ImageSize.X = CHECK_SIZE
                brush.ImageSize.Y = CHECK_SIZE
            end)
        end
    end
    return true
end
function M.install()
    local dock = require("ModMenu.shell.dock")
    local U = require("ModMenu.core.umg")
    local toggle = U.CreateLabeledToggle
    if toggle then
        U.CreateLabeledToggle = function(...)
            local check, label = toggle(...)
            M.checkbox(check)
            pcall(function() require("ModMenu.core.umg").StyleText(label, 13, TAB_INK) end)
            pcall(function() check.WidgetStyle.Padding.Left = 8 end)
            pcall(function() check:SetForegroundColor({ SpecifiedColor = WHITE, ColorUseRule = 0 }) end)
            return check, label
        end
    end
    local chrome = dock.BuildChrome
    local style = U.StyleText
    U.StyleText = function(label, size, color)
        style(label, size, color)
        M.font(label, "font_body")
    end
    if config.skin then
        require("ModMenu.core.theme").PadPanel = function() return { Left = 0, Top = 0, Right = 0, Bottom = 0 } end
    end
    dock.BuildChrome = function(S, content, suffix)
        chrome(S, content, suffix)
        local fill, scroll = S.panelBorder, S.menuScroll
        if not M.paint(fill, "paper") then M.paint(fill, "paper_fallback") end
        pcall(function() S.panelOutline:SetPadding({ Left = 0, Top = 0, Right = 0, Bottom = 0 }) end)
        local texture = M.texture("frame")
        if not texture then return end
        local ok = pcall(function()
            local overlay = U.Construct("/Script/UMG.Overlay", fill, "Toolbox_Frame_" .. suffix)
            scroll:RemoveFromParent()
            local slot = overlay:AddChildToOverlay(scroll)
            slot:SetHorizontalAlignment(0)
            slot:SetVerticalAlignment(0)
            slot:SetPadding({ Left = 9, Top = 6, Right = 9, Bottom = 22 })
            local frame = U.Construct("/Script/UMG.Image", overlay, "Toolbox_FrameImage_" .. suffix)
            frame:SetBrushFromTexture(texture, false)
            setBrush(frame.Brush, texture, 2, 0.2)
            frame:SetVisibility(4)
            local frameSlot = overlay:AddChildToOverlay(frame)
            frameSlot:SetHorizontalAlignment(0)
            frameSlot:SetVerticalAlignment(0)
            fill:SetContent(overlay)
        end)
        if not ok then
            log.info("Skin: frame overlay failed; using the plain frame.")
            pcall(function() fill:SetContent(scroll) end)
        end
    end
    log.info("Base-game skin installed.")
end
return M
