local file, lines
local function w(depth, text)
    lines = lines + 1
    file:write(string.rep("  ", depth) .. text .. "\n")
    file:flush()
end
local function try(f, ...)
    if file then
        file:write("~" .. tostring(debug.getinfo(f, "S").linedefined) .. "\n")
        file:flush()
    end
    local ok, r = pcall(f, ...)
    if ok then return r end
end
local function name(o)
    local n = try(function() return o:GetFullName() end)
    return n and tostring(n) or "?"
end
local function num(x)
    x = tonumber(x)
    return x and string.format("%.3g", x) or "?"
end
local function color(c)
    return c and ("(" .. num(c.R) .. "," .. num(c.G) .. "," .. num(c.B) .. "," .. num(c.A) .. ")") or "?"
end
local function brush(b)
    if not b then return "nil" end
    local res = try(function() return b.ResourceObject end)
    local resName = "none"
    if res then resName = try(function() return res:IsValid() and name(res) or "invalid" end) or "none" end
    local m = try(function() return b.Margin end)
    local size = try(function() return b.ImageSize end)
    return string.format(
        "draw=%s res=%s margin=%s size=%s tint=%s",
        tostring(try(function() return b.DrawAs end)),
        resName,
        m and (num(m.Left) .. "," .. num(m.Top) .. "," .. num(m.Right) .. "," .. num(m.Bottom)) or "?",
        size and (num(size.X) .. "x" .. num(size.Y)) or "?",
        color(try(function() return b.TintColor.SpecifiedColor end))
    )
end
local function pad(p)
    return p and (num(p.Left) .. "," .. num(p.Top) .. "," .. num(p.Right) .. "," .. num(p.Bottom)) or "?"
end
local function slotInfo(widget)
    local slot = try(function() return widget.Slot end)
    if not slot or not try(function() return slot:IsValid() end) then return "" end
    local s = " slot"
    local p = try(function() return slot.Padding end)
    if p then s = s .. " pad=" .. pad(p) end
    local h = try(function() return slot.HorizontalAlignment end)
    local v = try(function() return slot.VerticalAlignment end)
    if h then s = s .. " align=" .. tostring(h) .. "/" .. tostring(v) end
    local size = try(function() return slot.Size end)
    if size then
        s = s
            .. " size="
            .. tostring(try(function() return size.SizeRule end))
            .. ":"
            .. num(try(function() return size.Value end))
    end
    return s
end
local function props(widget, cls)
    local parts = {}
    local function add(s)
        if s then parts[#parts + 1] = s end
    end
    if cls == "Image" then add("brush: " .. brush(try(function() return widget.Brush end))) end
    if cls == "Border" then
        add("brush: " .. brush(try(function() return widget.Background end)))
        add("brushColor=" .. color(try(function() return widget.BrushColor end)))
        add("contentPad=" .. pad(try(function() return widget.Padding end)))
    end
    if cls == "Button" then
        for _, state in ipairs({ "Normal", "Hovered", "Pressed", "Disabled" }) do
            add(state .. ": " .. brush(try(function() return widget.WidgetStyle[state] end)))
        end
        add("normalPad=" .. pad(try(function() return widget.WidgetStyle.NormalPadding end)))
        add("bg=" .. color(try(function() return widget.BackgroundColor end)))
    end
    if cls == "TextBlock" or cls == "RichTextBlock" then
        add('text="' .. tostring(try(function() return widget:GetText():ToString() end)) .. '"')
        add("fontSize=" .. tostring(try(function() return widget.Font.Size end)))
        do
            local font = try(function() return widget.Font.FontObject end)
            if font then add("font=" .. name(font)) end
        end
        add("color=" .. color(try(function() return widget.ColorAndOpacity.SpecifiedColor end)))
        add("shadow=" .. color(try(function() return widget.ShadowColorAndOpacity end)))
    end
    if cls == "SizeBox" then
        add(
            "w="
                .. tostring(try(function() return widget.WidthOverride end))
                .. " h="
                .. tostring(try(function() return widget.HeightOverride end))
        )
    end
    if cls == "ScaleBox" then add("stretch=" .. tostring(try(function() return widget.Stretch end))) end
    return table.concat(parts, " | ")
end
local function walk(widget, depth)
    if depth > 40 or not widget then return end
    local cls = try(function() return widget:GetClass():GetFName():ToString() end) or "?"
    local vis = try(function() return widget:GetVisibility() end)
    w(
        depth,
        "> "
            .. cls
            .. " "
            .. (try(function() return widget:GetFName():ToString() end) or "?")
            .. " vis="
            .. tostring(vis)
    )
    w(depth, "  " .. slotInfo(widget) .. " " .. props(widget, cls))
    local count = try(function() return widget:GetChildrenCount() end)
    if count then
        for i = 0, count - 1 do
            walk(try(function() return widget:GetChildAt(i) end), depth + 1)
        end
    else
        local content = try(function() return widget:GetContent() end)
        if content then walk(content, depth + 1) end
        local tree = try(function() return widget.WidgetTree end)
        if tree then walk(try(function() return tree.RootWidget end), depth + 1) end
    end
end
local function dump()
    lines = 0
    file = io.open("ue4ss/widget-dump.txt", "w")
    if not file then return end
    local roots = try(FindAllOf, "UserWidget") or {}
    local n = 0
    for _, root in ipairs(roots) do
        local cls = name(root)
        w(0, "# candidate " .. cls)
        local visible = not cls:find("Default__", 1, true)
            and try(function() return root:IsValid() and root:IsInViewport() and root:IsVisible() end)
        if visible and not cls:find("ModMenu", 1, true) then
            n = n + 1
            w(0, "==== " .. cls)
            walk(try(function() return root.WidgetTree.RootWidget end), 1)
        end
    end
    file:close()
    print("[WidgetDump] " .. n .. " visible user widgets, " .. lines .. " lines -> ue4ss/widget-dump.txt\n")
end
RegisterKeyBind(Key.F9, { ModifierKey.CONTROL }, function()
    ExecuteInGameThread(function() pcall(dump) end)
end)
print("[WidgetDump] ready: Ctrl+F9 with a building window open.\n")
