local config = require("toolbox.config")
local log = require("toolbox.core.log")
local ids = require("toolbox.data.item_ids")
local M = {}
local tableObject, cache, paths, misses
local function valid(o)
    local ok, result = pcall(function() return o and o:IsValid() end)
    return ok and result == true
end
function M.begin()
    tableObject = StaticFindObject("/Game/NotStronghold/Data/DT_Items.DT_Items")
    cache, paths, misses = {}, {}, {}
end
function M.get(id)
    if cache[id] ~= nil then return cache[id] or nil end
    local value
    if valid(tableObject) then
        for _, key in ipairs({ tostring(ids[id]), id }) do
            local ok, row = pcall(function() return tableObject:FindRow(key) end)
            if ok and row then
                for _, field in ipairs({
                    "IconTextureV2",
                    "IconTexture",
                    "iconTexture",
                    "iconTextureV2",
                    "ResourceIcon",
                    "Icon",
                }) do
                    local yes, texture = pcall(function() return row[field] end)
                    if yes and valid(texture) then
                        local good, name = pcall(function() return texture:GetFullName() end)
                        if good and name:find("Texture2D", 1, true) then
                            value = texture
                            paths[id] = name
                            break
                        end
                    end
                end
            end
            if value then break end
        end
    end
    cache[id] = value or false
    if not value then misses[#misses + 1] = id end
    return value
end
function M.report()
    if not config.debug then return end
    local lines = {}
    for id, path in pairs(paths) do
        lines[#lines + 1] = id .. " = " .. path
    end
    table.sort(lines)
    lines[#lines + 1] = "MISSING: " .. table.concat(misses, ", ")
    local f = io.open("ue4ss/resource-icon-map.txt", "w")
    if f then
        f:write(table.concat(lines, "\n"))
        f:close()
    end
    log.info("Item-table icons: " .. (#lines - 1) .. " resolved, " .. #misses .. " missing.")
end
return M
