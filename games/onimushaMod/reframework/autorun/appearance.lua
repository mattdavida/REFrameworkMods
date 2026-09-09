-- Appearance tab: shrine catalog + live mesh swap.
-- Does not write unlocks. DLC only works if those files are mounted.

local Appearance = {}

local try_call, try_field, try_any, try_static, is_managed, enum_value
local get_player_entity, get_player_context, log_action

local PARTS_BODY = 0
local PARTS_CLOAK = 5
local PARTS_WEAPON = 6

local catalog = {
    sword = { parts = PARTS_WEAPON, items = {}, labels = {} },
    cloak = { parts = PARTS_CLOAK, items = {}, labels = {} },
    body = { parts = PARTS_BODY, items = {}, labels = {} },
}

local state = {
    ready = false,
    named = false,
    sword_i = 0,
    cloak_i = 0,
    body_i = 0,
}

function Appearance.bind(deps)
    deps = deps or {}
    try_call = deps.try_call
    try_field = deps.try_field
    try_any = deps.try_any
    try_static = deps.try_static
    is_managed = deps.is_managed
    enum_value = deps.enum_value
    get_player_entity = deps.get_player_entity
    get_player_context = deps.get_player_context
    log_action = deps.log_action
end

local function serial_int(obj)
    if type(obj) == "number" then
        return obj
    end
    if not is_managed(obj) then
        return nil
    end
    local value = try_any(obj, { "get_Value", "get_FixedValue" })
        or try_field(obj, "_Value")
        or try_field(obj, "value__")
    if type(value) == "number" then
        return value
    end
    return nil
end

local function foreach_managed(collection, visitor)
    if not is_managed(collection) then
        return
    end
    local size = try_any(collection, { "get_Count", "get_Length", "get_size" })
    if type(size) ~= "number" then
        local ok, n = pcall(function()
            return collection:get_size()
        end)
        if ok then
            size = n
        end
    end
    if type(size) ~= "number" then
        return
    end
    for i = 0, size - 1 do
        local item = try_call(collection, "get_Item", i)
        if item == nil then
            local ok, value = pcall(function()
                return collection[i]
            end)
            if ok then
                item = value
            end
        end
        if item == nil then
            local ok, value = pcall(function()
                return collection:get_element(i)
            end)
            if ok then
                item = value
            end
        end
        if item ~= nil then
            visitor(item)
        end
    end
end

local function get_various_setting()
    local vdm = sdk.get_managed_singleton("app.VariousDataManager")
    return try_any(vdm, { "get_Setting" }) or try_field(vdm, "_Setting")
end

local function managed_string(value)
    if type(value) == "string" and value ~= "" then
        return value
    end
    if not is_managed(value) then
        return nil
    end
    local text = try_call(value, "ToString")
    if type(text) == "string" and text ~= "" and text ~= "System.String" then
        return text
    end
    return nil
end

local function guid_text(guid)
    if guid == nil then
        return nil
    end
    local td = sdk.find_type_definition("app.MessageUtil")
    local method = td and (td:get_method("getText(System.Guid)") or td:get_method("getText"))
    if method then
        local ok, text = pcall(function()
            return method:call(nil, guid)
        end)
        if ok then
            return managed_string(text)
        end
    end
    return nil
end

local function is_placeholder_name(name)
    if type(name) ~= "string" or name == "" then
        return true
    end
    if name == "No Name" or name == "None" or name == "INVALID" then
        return true
    end
    if name:find("アイテム名が設定されていません", 1, true) then
        return true
    end
    local lower = name:lower()
    if lower:find("item name is not set", 1, true) then
        return true
    end
    return false
end

local function item_name(item_id)
    item_id = serial_int(item_id) or item_id
    if type(item_id) ~= "number" or item_id == 0 then
        return nil
    end
    local name = managed_string(try_static("app.ItemUtil", { "getItemName" }, item_id))
    if name and not is_placeholder_name(name) then
        return name
    end
    local data = try_static("app.ItemUtil", { "getData" }, item_id)
    local guid = try_any(data, { "get_NameGuid" }) or try_field(data, "_NameGuid")
    name = guid_text(guid)
    if name and not is_placeholder_name(name) then
        return name
    end
    return nil
end

local function is_dlc_enum_name(name)
    return type(name) == "string" and name:find("5%d%d$") ~= nil
end

local function pretty_mesh_name(enum_name)
    if type(enum_name) ~= "string" then
        return "Mesh"
    end
    local label = enum_name
        :gsub("^WEAPONS", "Sword ")
        :gsub("^CLOAK", "Haori ")
        :gsub("^BODY", "Clothing ")
    if is_dlc_enum_name(enum_name) then
        label = label .. " (DLC)"
    end
    return label
end

local function with_dlc_suffix(label, dlc)
    if type(label) ~= "string" or label == "" then
        return label
    end
    if dlc and not label:find("%(DLC%)", 1, false) then
        return label .. " (DLC)"
    end
    return label
end

local function enum_entries(type_name)
    local td = sdk.find_type_definition(type_name)
    if not td then
        return {}, nil
    end
    local ok, fields = pcall(function()
        return td:get_fields()
    end)
    if not ok or not fields then
        return {}, nil
    end
    local out = {}
    local invalid = nil
    for _, field in ipairs(fields) do
        local name = field.get_name and field:get_name()
        if type(name) == "string" then
            local ok_val, value = pcall(function()
                return field:get_data(nil)
            end)
            if ok_val and type(value) == "number" then
                if name == "INVALID" then
                    invalid = value
                elseif name ~= "value__" and name ~= "MAX" then
                    table.insert(out, { name = name, id = value })
                end
            end
        end
    end
    table.sort(out, function(a, b)
        return a.name < b.name
    end)
    return out, invalid
end

local function catalog_add(bucket, id, label, sid, named, dlc)
    id = serial_int(id) or id
    if type(id) ~= "number" then
        return
    end
    for _, item in ipairs(bucket.items) do
        if item.id == id then
            if dlc then
                item.dlc = true
            end
            if label and (named or not item.named) then
                item.label = with_dlc_suffix(label, item.dlc)
                if named then
                    item.named = true
                end
            end
            if sid and not item.sid then
                item.sid = sid
            end
            return
        end
    end
    table.insert(bucket.items, {
        id = id,
        sid = sid,
        dlc = dlc == true,
        label = with_dlc_suffix(label or ("Mesh " .. tostring(id)), dlc == true),
        named = named == true,
    })
end

local function fill_from_enum(bucket, fixed_type, seq_type)
    local seq_by_name = {}
    if seq_type then
        local seq_entries = enum_entries(seq_type)
        for _, entry in ipairs(seq_entries) do
            seq_by_name[entry.name] = entry.id
        end
    end
    local entries, invalid = enum_entries(fixed_type)
    for _, entry in ipairs(entries) do
        if entry.id ~= invalid then
            catalog_add(
                bucket,
                entry.id,
                pretty_mesh_name(entry.name),
                seq_by_name[entry.name],
                false,
                is_dlc_enum_name(entry.name)
            )
        end
    end
    return invalid
end

local function fill_from_costume_table()
    local setting = get_various_setting()
    local costume_table = try_any(setting, { "get_CostumeItemData" })
        or try_field(setting, "_CostumeItemData")
    local list = try_field(costume_table, "_ItemList") or try_any(costume_table, { "get_ItemList" })
    local invalid_weapon = enum_value("app.PlayerEquipWeaponsID.TYPE_Fixed", "INVALID")
    local invalid_cloak = enum_value("app.PlayerEquipCloakID.TYPE_Fixed", "INVALID")
    local invalid_body = enum_value("app.PlayerEquipBodyID.TYPE_Fixed", "INVALID")
    local dlc_cond = enum_value("app.user_data.CostumeItemTable.DISPLAY_CONDITION", "PURCHASED_DLC") or 5
    local named = 0
    foreach_managed(list, function(row)
        local cond = serial_int(try_any(row, { "get_Condition" }) or try_field(row, "_Condition"))
        local dlc = cond == dlc_cond
        local name = item_name(try_any(row, { "get_ItemID" }) or try_field(row, "_ItemID"))
        if not name then
            return
        end
        local weapon = serial_int(try_any(row, { "get_PlayerWeaponsID" }) or try_field(row, "_PlayerWeaponsID"))
        local cloak = serial_int(try_any(row, { "get_PlayerCloakID" }) or try_field(row, "_PlayerCloakID"))
        local body = serial_int(try_any(row, { "get_PlayerBodyID" }) or try_field(row, "_PlayerBodyID"))
        if weapon and weapon ~= invalid_weapon then
            catalog_add(catalog.sword, weapon, name, nil, true, dlc)
            named = named + 1
        end
        if cloak and cloak ~= invalid_cloak then
            catalog_add(catalog.cloak, cloak, name, nil, true, dlc)
            named = named + 1
        end
        if body and body ~= invalid_body then
            catalog_add(catalog.body, body, name, nil, true, dlc)
            named = named + 1
        end
    end)
    return named
end

local function refresh_labels(bucket)
    bucket.labels = {}
    for i, item in ipairs(bucket.items) do
        bucket.labels[i] = item.label
    end
end

local function refresh_all_labels()
    refresh_labels(catalog.sword)
    refresh_labels(catalog.cloak)
    refresh_labels(catalog.body)
end

local function build_catalog()
    catalog.sword.items = {}
    catalog.cloak.items = {}
    catalog.body.items = {}
    fill_from_enum(catalog.sword, "app.PlayerEquipWeaponsID.TYPE_Fixed", "app.PlayerEquipWeaponsID.TYPE")
    fill_from_enum(catalog.cloak, "app.PlayerEquipCloakID.TYPE_Fixed", "app.PlayerEquipCloakID.TYPE")
    fill_from_enum(catalog.body, "app.PlayerEquipBodyID.TYPE_Fixed", "app.PlayerEquipBodyID.TYPE")
    fill_from_costume_table()
    refresh_all_labels()
end

local function ensure_catalog()
    if not state.ready or #catalog.sword.items == 0 then
        build_catalog()
        state.ready = #catalog.sword.items > 0
    end
    if not state.named then
        local named = fill_from_costume_table()
        refresh_all_labels()
        if type(named) == "number" and named > 0 then
            state.named = true
        end
    end
end

local function get_game_object_supporter()
    local entity = get_player_entity()
    local go = try_any(entity, { "get_GameObjectSupporter" })
        or try_field(entity, "<GameObjectSupporter>k__BackingField")
    if is_managed(go) then
        return go
    end
    return nil
end

local EQUIP_API = {
    [PARTS_BODY] = {
        get = "get_CurrentEquipBodyID",
        set = "set_CurrentEquipBodyID",
        field = "<CurrentEquipBodyID>k__BackingField",
    },
    [PARTS_CLOAK] = {
        get = "get_CurrentEquipCloakID",
        set = "set_CurrentEquipCloakID",
        field = "<CurrentEquipCloakID>k__BackingField",
    },
    [PARTS_WEAPON] = {
        get = "get_CurrentEquipWeaponsID",
        set = "set_CurrentEquipWeaponsID",
        field = "<CurrentEquipWeaponsID>k__BackingField",
    },
}

local function read_equip_id(ctx, parts)
    local api = EQUIP_API[parts]
    if api and is_managed(ctx) then
        local value = try_call(ctx, api.get) or try_field(ctx, api.field)
        if type(value) == "number" then
            return value
        end
    end
    local td = sdk.find_type_definition("app.PlayerManager")
    local method = td and td:get_method("getCurrentEquipID")
    if method and is_managed(ctx) then
        local ok, value = pcall(function()
            return method:call(nil, parts, ctx)
        end)
        if ok and type(value) == "number" then
            return value
        end
    end
    return nil
end

local function pick_equip_id(current, fixed, seq)
    if type(current) == "number" and current > 0 and current < 64 and type(seq) == "number" then
        return seq, "seq"
    end
    if type(fixed) == "number" then
        return fixed, "fixed"
    end
    return seq, "seq"
end

local function write_equip_id(ctx, parts, id)
    local api = EQUIP_API[parts]
    if not (api and is_managed(ctx) and type(id) == "number") then
        return false
    end
    local ok = pcall(function()
        ctx:call(api.set, id)
    end)
    pcall(function()
        ctx:set_field(api.field, id)
    end)
    return ok or read_equip_id(ctx, parts) == id
end

local function refresh_live_model(gos)
    if not is_managed(gos) then
        return false
    end
    pcall(function()
        gos:call("resetChangeState")
    end)
    local ok_a = pcall(function()
        gos:call("checkEquip")
    end)
    local ok_b = pcall(function()
        gos:call("checkModelChange")
    end)
    pcall(function()
        gos:call("checkModelUpdate")
    end)
    pcall(function()
        gos:call("checkSwitchBodyModelParts")
    end)
    return ok_a or ok_b
end

local function apply_mesh(parts, id, label, sid)
    if type(id) ~= "number" then
        log_action("mesh failed: bad id")
        return
    end
    local ctx = get_player_context()
    local gos = get_game_object_supporter()
    local was = read_equip_id(ctx, parts)
    local use_id, kind = pick_equip_id(was, id, sid)
    local set_ok = write_equip_id(ctx, parts, use_id)
    local refresh_ok = refresh_live_model(gos)
    local now = read_equip_id(ctx, parts)

    local bits = {
        tostring(label),
        kind .. "=" .. tostring(use_id),
        "was=" .. tostring(was),
        "now=" .. tostring(now),
        set_ok and "set" or "noset",
        refresh_ok and "check" or "nocheck",
        is_managed(gos) and "gos" or "nogos",
        is_managed(ctx) and "ctx" or "noctx",
    }
    log_action("mesh " .. table.concat(bits, " "))
end

local function draw_mesh_picker(ui, title, bucket, index_key)
    ui.section(title, function()
        if #bucket.labels == 0 then
            ui.muted("Waiting for mesh list.")
            return
        end
        local sel = ui.choice_grid(bucket.labels, state[index_key], 1)
        if sel ~= state[index_key] then
            state[index_key] = sel
            local item = bucket.items[sel]
            if item then
                apply_mesh(bucket.parts, item.id, item.label, item.sid)
            end
        end
    end, title ~= "Clothing")
end

function Appearance.draw(ui)
    ensure_catalog()
    ui.muted("Pick a mesh. DLC skins only work for DLC you own.")
    draw_mesh_picker(ui, "Sword", catalog.sword, "sword_i")
    draw_mesh_picker(ui, "Haori Coat", catalog.cloak, "cloak_i")
    draw_mesh_picker(ui, "Clothing", catalog.body, "body_i")
end

function Appearance.reset()
    state.ready = false
    state.named = false
    catalog.sword.items = {}
    catalog.cloak.items = {}
    catalog.body.items = {}
    refresh_all_labels()
end

_G.OnimushaAppearance = Appearance
return Appearance
