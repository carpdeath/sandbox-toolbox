local M = {}
local INK = { R = 0.14, G = 0.11, B = 0.08, A = 1 }
local PAPER = { R = 0.90, G = 0.86, B = 0.76, A = 1 }
function M.install()
    local U = require("ModMenu.core.umg")
    local skin = require("toolbox.ui.skin")
    local tabs = require("ModMenu.shell.tabs")
    U.CreateLabeledEditable = function(outer, prefix, caption, initial, opts)
        opts = opts or {}
        local size = opts.fontSize or 11
        local root = U.Construct("/Script/UMG.VerticalBox", outer, prefix .. "_Row")
        local titleBg = U.Construct("/Script/UMG.Border", root, prefix .. "_TitleBg")
        if not skin.ribbon(titleBg, "ribbon_title") then pcall(function() titleBg:SetBrushColor(PAPER) end) end
        pcall(function() titleBg:SetPadding({ Left = 16, Top = 3, Right = 16, Bottom = 4 }) end)
        local label = U.Construct("/Script/UMG.TextBlock", titleBg, prefix .. "_Label")
        U.StyleText(label, size, INK)
        U.SetLabelText(label, caption or "")
        titleBg:AddChild(label)
        local titleSlot = root:AddChildToVerticalBox(titleBg)
        pcall(function()
            titleSlot:SetHorizontalAlignment(1)
            titleSlot:SetPadding({ Left = 0, Top = 2, Right = 0, Bottom = 1 })
        end)
        local fieldBg = U.Construct("/Script/UMG.Border", root, prefix .. "_Border")
        if not skin.ribbon(fieldBg, "ribbon_field") then pcall(function() fieldBg:SetBrushColor(PAPER) end) end
        pcall(function() fieldBg:SetPadding({ Left = 16, Top = 5, Right = 16, Bottom = 6 }) end)
        local edit = U.Construct("/Script/UMG.EditableTextBox", fieldBg, prefix .. "_Edit")
        pcall(function()
            edit:SetText(FText(tostring(initial or "")))
            if opts.hint and opts.hint ~= "" then edit:SetHintText(FText(tostring(opts.hint))) end
        end)
        U.StyleEditableTextBox(edit, size)
        pcall(function() fieldBg:SetContent(edit) end)
        local host = fieldBg
        if not opts.fillField then
            host = U.Construct("/Script/UMG.SizeBox", root, prefix .. "_Size")
            pcall(function()
                host:SetWidthOverride(opts.fieldWidth or 96)
                host:SetContent(fieldBg)
            end)
        end
        local fieldSlot = root:AddChildToVerticalBox(host)
        pcall(function()
            fieldSlot:SetHorizontalAlignment(opts.fillField and 0 or 1)
            fieldSlot:SetPadding({ Left = 0, Top = 0, Right = 0, Bottom = 2 })
        end)
        return root, edit, label
    end
    local strip = tabs.BuildStrip
    tabs.BuildStrip = function(S, contentBox, suffix)
        local first = #S.liveControls + 1
        strip(S, contentBox, suffix)
        for i = first, #S.liveControls do
            local control = S.liveControls[i]
            if control.kind == "tab" then
                skin.tab(control.widget, control.label, control.tabId == S.activeTab)
                pcall(function() control.widget:SetPadding({ Left = 8, Top = 7, Right = 8, Bottom = 7 }) end)
            end
        end
    end
end
return M
