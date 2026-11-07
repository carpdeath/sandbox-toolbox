local M = {}
function M.install()
    local collapse = require("ModMenu.shell.collapse")
    local U = require("ModMenu.core.umg")
    local build, attach = collapse.BuildHeader, collapse.AttachBody
    collapse.BuildHeader = function(S, section, parent, suffix)
        local name = "ToolboxCard_" .. section.id .. "_" .. suffix
        local card = U.Construct("/Script/UMG.Border", parent, name)
        card:SetBrushColor({ R = 0.62, G = 0.58, B = 0.50, A = 1 })
        card:SetPadding({ Left = 12, Top = 0, Right = 12, Bottom = 0 })
        parent:AddChildToVerticalBox(card)
        local box = U.Construct("/Script/UMG.VerticalBox", card, name .. "_Content")
        card:AddChild(box)
        local ctrl = build(S, section, box, suffix)
        for _, state in ipairs({ "Normal", "Hovered", "Pressed", "Disabled" }) do
            pcall(function() ctrl.widget.WidgetStyle[state].DrawAs = 0 end)
        end
        local skin = require("toolbox.ui.skin")
        if skin.band(ctrl.widget, { R = 0.26, G = 0.25, B = 0.25, A = 1 }) then
            pcall(function() card:SetBrushColor({ R = 0, G = 0, B = 0, A = 0 }) end)
            pcall(function()
                U.StyleText(ctrl.label, S.config.fontSection + 1, { R = 0.95, G = 0.92, B = 0.84, A = 1 })
                skin.font(ctrl.label, "font_heading")
            end)
        end
        ctrl.cardContent = box
        return ctrl
    end
    collapse.AttachBody = function(ctrl, body, collapsed)
        if ctrl.cardContent then
            body:RemoveFromParent()
            ctrl.cardContent:AddChildToVerticalBox(body)
        end
        return attach(ctrl, body, collapsed)
    end
    local Button = require("ModMenu.widgets.button")
    local original = Button.build
    Button.build = function(ctx)
        if not ctx.item.width then return original(ctx) end
        local item = ctx.item
        local size = U.Construct("/Script/UMG.SizeBox", ctx.contentBox, ctx.namePrefix .. "_FixedWidth")
        if not item.fill then size:SetWidthOverride(item.width) end
        size:SetHeightOverride(44)
        U.AddToContent(ctx, size, { fill = item.fill == true })
        U.AddItemPad(ctx, ctx.namePrefix .. "_Gap", 6)
        local button, label = U.CreateTextButton(size, ctx.namePrefix, item.label)
        size:AddChild(button)
        U.EnableAutoWrap(label)
        pcall(function()
            label.Slot:SetHorizontalAlignment(0)
            label:SetJustification(1)
        end)
        pcall(function()
            label.Font.Size = 10
            label:SetClipping(1)
        end)
        local ctrl = {
            kind = "button",
            sectionId = ctx.section.id,
            item = item,
            widget = button,
            labelWidget = label,
            enabled = true,
            wasPressed = false,
        }
        Button.applyChrome(ctrl, ctx)
        require("toolbox.ui.skin").button(button)
        ctx.liveControls[#ctx.liveControls + 1] = ctrl
    end
    local poll = Button.poll
    Button.poll = function(ctrl, ctx)
        local tip = ctrl.item and ctrl.item.tooltip
        if tip then
            local ok, hovered = pcall(function() return ctrl.widget:IsHovered() end)
            hovered = ok and hovered == true
            if hovered ~= ctrl.tipShown then
                ctrl.tipShown = hovered
                require("toolbox.ui.window_drag").showTooltip(
                    hovered and tip or nil,
                    "button:" .. tostring(ctrl.sectionId) .. ":" .. tostring(ctrl.item.id)
                )
            end
        end
        return poll(ctrl, ctx)
    end
end
return M
