local log = require("toolbox.core.log")
local M = {}
function M.showTooltip(_) end
function M.clamp(rect, dx, dy)
    local w, h = rect.maxX - rect.minX, rect.maxY - rect.minY
    local x = math.max(0, math.min(1 - w, rect.minX + dx))
    local y = math.max(0, math.min(1 - h, rect.minY + dy))
    return { minX = x, minY = y, maxX = x + w, maxY = y + h }
end
function M.install()
    local registry = require("ModMenu.widgets.init")
    local dock = require("ModMenu.shell.dock")
    local U = require("ModMenu.core.umg")
    local helpers = require("UEHelpers.UEHelpers")
    local geometry
    local tooltip, tooltipText, tooltipSlot, tooltipName
    local function pointer(S)
        local world = helpers.GetGameInstance()
        local lib = StaticFindObject("/Script/UMG.Default__WidgetLayoutLibrary")
        local mouse = lib:GetMousePositionOnViewport(world)
        local size = lib:GetViewportSize(world)
        local scale = lib:GetViewportScale(world)
        scale = tonumber(scale) or 1
        return tonumber(mouse.X) * scale / tonumber(size.X), tonumber(mouse.Y) * scale / tonumber(size.Y)
    end
    local function apply(S, rect)
        S.panelSlot:SetAnchors({
            Minimum = { X = rect.minX, Y = rect.minY },
            Maximum = { X = rect.maxX, Y = rect.maxY },
        })
        S.panelSlot:SetOffsets({ Left = 0, Top = 0, Right = 0, Bottom = 0 })
    end
    local function positionTooltip()
        if not tooltipName or not tooltipSlot then return end
        local ok, x, y = pcall(pointer)
        if ok and x and y then
            x = math.max(0.02, math.min(0.8, x))
            y = math.max(0.04, math.min(0.97, y))
            tooltipSlot:SetAnchors({ Minimum = { X = x, Y = y }, Maximum = { X = x, Y = y } })
            tooltipSlot:SetPosition({ X = 14, Y = -12 })
        end
    end
    local tipSources = {}
    M.showTooltip = function(name, source)
        if source == nil then
            tipSources = {}
        else
            tipSources[source] = name
        end
        name = nil
        for _, v in pairs(tipSources) do
            name = name or v
        end
        tooltipName = name
        if not tooltip then return end
        if name then
            U.SetLabelText(tooltipText, name)
            tooltip:SetVisibility(4)
            positionTooltip()
        else
            tooltip:SetVisibility(1)
        end
    end
    local drag = { type = "windowdrag" }
    function drag.poll(ctrl, ctx)
        positionTooltip()
        local down = ctx.Input.WidgetIsDown(ctrl.widget)
        if not down then
            ctrl.start = nil
            return
        end
        local ok, x, y = pcall(pointer, ctrl.S)
        if not ok or not x or not y then return end
        if not ctrl.start then
            ctrl.start = { x = x, y = y, rect = geometry or dock.PercentRect(ctrl.S.config) }
            ctx.Input.IgnoreClicks(2)
        else
            geometry = M.clamp(ctrl.start.rect, x - ctrl.start.x, y - ctrl.start.y)
            apply(ctrl.S, geometry)
            ctrl.start = { x = x, y = y, rect = geometry }
        end
    end
    local get, has = registry.get, registry.has
    registry.get = function(t)
        if t == "windowdrag" then return drag end
        return get(t)
    end
    registry.has = function(t) return t == "windowdrag" or has(t) end
    dock.BuildChrome = function(S, content, suffix)
        local row = content:GetChildAt(0)
        local title = row:GetChildAt(0)
        local close = row:GetChildrenCount() > 1 and row:GetChildAt(1) or nil
        row:RemoveChild(title)
        if close then row:RemoveChild(close) end
        local handle, label = U.CreateTextButton(row, "Toolbox_Drag_" .. suffix, "Sandbox Toolbox")
        pcall(function() label.Font.Size = 17 end)
        require("toolbox.ui.skin").font(label, "font_heading")
        handle:SetClickMethod(0)
        for _, state in ipairs({ "Normal", "Hovered", "Pressed", "Disabled" }) do
            pcall(function() handle.WidgetStyle[state].DrawAs = 0 end)
        end
        local slot = row:AddChildToHorizontalBox(handle)
        slot:SetSize({ SizeRule = 1, Value = 1 })
        if close then
            local skin = require("toolbox.ui.skin")
            if skin.button(close, "exit") then skin.closeIcon(close) end
            row:AddChildToHorizontalBox(close)
        end
        local hint = content:GetChildAt(1)
        row:RemoveFromParent()
        hint:RemoveFromParent()
        local chrome = U.Construct("/Script/UMG.Border", content, "Toolbox_TitleChrome_" .. suffix)
        chrome:SetBrushColor({ R = 0.14, G = 0.19, B = 0.27, A = 1 })
        local skin = require("toolbox.ui.skin")
        if not skin.paint(chrome, "header") then
            skin.paint(chrome, "header_fallback", { R = 0.7, G = 0.75, B = 0.9, A = 1 })
        end
        chrome:SetPadding({ Left = 10, Top = 8, Right = 8, Bottom = 8 })
        chrome:AddChild(row)
        content:AddChildToVerticalBox(chrome)
        local chromeSlot = chrome.Slot
        pcall(function() chromeSlot:SetPadding({ Left = 0, Top = 0, Right = 0, Bottom = 8 }) end)
        tooltip = U.Construct("/Script/UMG.Border", S.menuCanvas, "Toolbox_Tooltip_" .. suffix)
        tooltip:SetBrushColor({ R = 0.55, G = 0.60, B = 0.66, A = 1 })
        tooltip:SetPadding({ Left = 1.5, Top = 1.5, Right = 1.5, Bottom = 1.5 })
        local tooltipFill = U.Construct("/Script/UMG.Border", tooltip, "Toolbox_TooltipFill_" .. suffix)
        tooltipFill:SetBrushColor({ R = 0.07, G = 0.10, B = 0.15, A = 0.97 })
        tooltipFill:SetPadding({ Left = 14, Top = 7, Right = 14, Bottom = 8 })
        tooltip:AddChild(tooltipFill)
        tooltipText = U.Construct("/Script/UMG.TextBlock", tooltipFill, "Toolbox_TooltipText_" .. suffix)
        U.StyleText(tooltipText, 15, { R = 0.96, G = 0.93, B = 0.85, A = 1 })
        require("toolbox.ui.skin").font(tooltipText, "font_heading")
        tooltipFill:AddChild(tooltipText)
        tooltipSlot = S.menuCanvas:AddChildToCanvas(tooltip)
        tooltipSlot:SetAutoSize(true)
        tooltipSlot:SetAlignment({ X = 0, Y = 1 })
        tooltipSlot:SetZOrder(10000)
        tooltip:SetVisibility(1)
        tooltipName = nil
        S.liveControls[#S.liveControls + 1] = { kind = "windowdrag", widget = handle, S = S }
        if geometry then apply(S, geometry) end
    end
    log.info("Floating title-bar drag installed.")
end
return M
