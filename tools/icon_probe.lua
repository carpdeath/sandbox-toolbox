local M = {}
function M.run()
    local lines = {}
    for _, class in ipairs({ "Texture2D", "DataTable" }) do
        local ok, objects = pcall(FindAllOf, class)
        if ok and type(objects) == "table" then
            for _, obj in ipairs(objects) do
                pcall(function() lines[#lines + 1] = class .. " " .. obj:GetFullName() end)
            end
        end
    end
    local ok, h = pcall(require, "UEHelpers")
    if ok then
        local yes, gi = pcall(h.GetGameInstance)
        if yes and gi then
            pcall(function() lines[#lines + 1] = "GameInstance " .. gi:GetFullName() end)
            pcall(function() lines[#lines + 1] = "itemStats " .. gi.itemStats:GetFullName() end)
        end
    end
    table.sort(lines)
    local f = io.open("ue4ss/resource-icon-inventory.txt", "w")
    if f then
        f:write(table.concat(lines, "\n"))
        f:close()
    end
    print("[SandboxToolbox] Icon inventory: " .. #lines .. " entries.\n")
end
return M
