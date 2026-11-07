local paths = require("toolbox.core.paths")

local M = {}

local function write(path, text)
    local f = assert(io.open(path, "w"))
    f:write(text)
    f:close()
end

local function read(path)
    local f = assert(io.open(path, "r"))
    local text = f:read("*a")
    f:close()
    return text
end

function M.export(name, stem, label)
    local fn
    return function(request)
        local directory = paths.native_dir
        if not fn then
            local err
            fn, err = package.loadlib(directory .. "native_bridge.dll", name)
            if not fn then error(label .. " bridge could not load: " .. tostring(err), 0) end
        end
        write(directory .. stem .. "-request.txt", request)
        write(directory .. stem .. "-result.txt", "")
        fn()
        return read(directory .. stem .. "-result.txt")
    end
end

function M.failure(result, label)
    return result ~= "" and result or ("No result from the " .. label:lower() .. " bridge.")
end

return M
