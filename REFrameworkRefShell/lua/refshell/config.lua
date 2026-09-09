-- Tiny JSON key/value store. Files live in reframework/data/ via json.load_file.

local util = require("refshell.util")

local function create_config(opts)
    opts = opts or {}
    if type(opts.id) ~= "string" or opts.id == "" then
        error("RefShell.Config: id must be a non-empty string")
    end
    if opts.defaults ~= nil and type(opts.defaults) ~= "table" then
        error("RefShell.Config: defaults must be a table")
    end
    if opts.defaults ~= nil and not util.is_json_safe(opts.defaults) then
        error("RefShell.Config: defaults must be JSON-safe")
    end

    local id = opts.id
    local file_path = opts.file
    if type(file_path) ~= "string" or file_path == "" then
        file_path = "refshell_" .. id .. ".json"
    end
    local autosave = opts.autosave ~= false
    local defaults = util.deep_copy(opts.defaults or {})
    local store = {}
    local load_failed = false
    local cfg = {}

    local function merge_loaded(loaded)
        store = util.deep_copy(defaults)
        if type(loaded) ~= "table" then
            return
        end
        for k, v in pairs(loaded) do
            if type(k) == "string" then
                store[k] = util.deep_copy(v)
            end
        end
    end

    local loaded = nil
    local ok_load, result = pcall(json.load_file, file_path)
    if ok_load then
        loaded = result
    end
    if loaded == nil then
        merge_loaded(nil)
        log.info(string.format("[RefShell.Config] %s: no config yet (%s)", id, file_path))
    elseif type(loaded) ~= "table" then
        load_failed = true
        merge_loaded(nil)
        log.error(string.format("[RefShell.Config] %s: %s is not an object (file left untouched)", id, file_path))
    else
        merge_loaded(loaded)
        log.info(string.format("[RefShell.Config] %s: loaded %s", id, file_path))
    end

    function cfg:has(key)
        return type(key) == "string" and store[key] ~= nil
    end

    function cfg:Get(key)
        if type(key) ~= "string" or key == "" then
            error("RefShell.Config:Get: key must be a non-empty string")
        end
        local value = store[key]
        if value == nil then
            value = defaults[key]
        end
        return util.deep_copy(value)
    end

    function cfg:Set(key, value)
        if type(key) ~= "string" or key == "" then
            error("RefShell.Config:Set: key must be a non-empty string")
        end
        if value ~= nil and not util.is_json_safe(value) then
            error("RefShell.Config:Set: value must be JSON-safe")
        end

        local current = store[key]
        if current == nil then
            current = defaults[key]
        end
        if util.deep_equal(current, value) then
            return
        end

        if value == nil then
            store[key] = nil
        else
            store[key] = util.deep_copy(value)
        end
        load_failed = false
        if autosave then
            cfg:Save()
        end
    end

    function cfg:Save()
        if load_failed then
            log.error(string.format("[RefShell.Config] %s: skip save, %s did not parse", id, file_path))
            return false
        end
        local out = {}
        for k, v in pairs(store) do
            out[k] = v
        end
        local ok, err = pcall(json.dump_file, file_path, out, 4)
        if not ok then
            log.error(string.format("[RefShell.Config] %s: save failed %s — %s", id, file_path, tostring(err)))
            return false
        end
        return true
    end

    function cfg:File()
        return file_path
    end

    return cfg
end

return {
    create = create_config,
    Init = create_config,
}
