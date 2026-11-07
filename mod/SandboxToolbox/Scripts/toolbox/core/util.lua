local M = {}

function M.safe(fn, default)
    local ok, value = pcall(fn)
    if not ok or value == nil then return default end
    return value
end

function M.valid(obj)
    return obj ~= nil and M.safe(function() return obj:IsValid() end, false) == true
end

function M.address(obj)
    return M.safe(function() return obj:GetAddress() end, nil)
end

function M.number(obj, field)
    local value = M.safe(function() return obj[field] end, nil)
    return type(value) == "number" and value or nil
end

function M.length(array)
    return array and M.safe(function() return array:GetArrayNum() end, 0) or 0
end

function M.class_name(obj)
    return M.safe(function() return obj:GetClass():GetFName():ToString() end, "<unknown>")
end

function M.fstring(value)
    local text = type(value) == "string" and value or M.safe(function() return value:ToString() end, nil)
    if type(text) == "string" and text ~= "" then return text end
    return nil
end

return M
