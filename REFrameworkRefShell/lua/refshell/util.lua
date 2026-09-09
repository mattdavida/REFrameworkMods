-- Shared table helpers for RefShell.

local util = {}

function util.copy_defaults(dst, src)
    for k, v in pairs(src) do
        if dst[k] == nil then
            dst[k] = v
        elseif type(v) == "table" and type(dst[k]) == "table" and not v[1] then
            util.copy_defaults(dst[k], v)
        end
    end
    return dst
end

function util.deep_copy(value, seen)
    if type(value) ~= "table" then
        return value
    end
    seen = seen or {}
    if seen[value] then
        error("RefShell.Config: circular table")
    end
    seen[value] = true
    local out = {}
    for k, v in pairs(value) do
        out[util.deep_copy(k, seen)] = util.deep_copy(v, seen)
    end
    seen[value] = nil
    return out
end

function util.deep_equal(a, b)
    if a == b then
        return true
    end
    if type(a) ~= type(b) or type(a) ~= "table" then
        return false
    end
    for k, v in pairs(a) do
        if not util.deep_equal(v, b[k]) then
            return false
        end
    end
    for k in pairs(b) do
        if a[k] == nil then
            return false
        end
    end
    return true
end

function util.is_json_safe(value)
    local t = type(value)
    if value == nil or t == "boolean" or t == "string" then
        return true
    end
    if t == "number" then
        return value == value and value ~= math.huge and value ~= -math.huge
    end
    if t ~= "table" then
        return false
    end
    for k, v in pairs(value) do
        local kt = type(k)
        if kt ~= "string" and kt ~= "number" then
            return false
        end
        if not util.is_json_safe(v) then
            return false
        end
    end
    return true
end

return util
