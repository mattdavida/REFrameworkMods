-- Give tab: ItemData master table, same Type groups as the pause Items tab.
-- _Category is CATEGORY_Fixed. Grant via SaveDataHelper_Item.addItem.

local Give = {}

local try_call, try_field, try_any, try_static, is_managed, enum_value
local get_item_helper, log_action

local CAT_SKIP = {
    INVALID = true,
    VIRTUAL = true,
    MAX = true,
}

-- Pause Items tab groups, plus Genma Notes (picture book / portraits).
-- Pouches and skins stay omitted.
local CAT_OMIT = {
    MEDICINE_BAG = true,
    APPEARANCE_CHANGE = true,
}

local UI_CAT = {
    { "items", "Items" },
    { "materials", "Materials" },
    { "offerings", "Offerings" },
    { "valuables", "Valuables" },
    { "genma_notes", "Genma Notes" },
}

local UI_KEYS = {
    all = true,
    items = true,
    materials = true,
    offerings = true,
    valuables = true,
    genma_notes = true,
}

local ENGINE_TO_UI = {
    equipable = "items",
    growth_material = "materials",
    medicine_bag_material = "materials",
    tribute = "offerings",
    important = "valuables",
    picture_book = "genma_notes",
}

local AMOUNT_OPTIONS = {
    { 1, "1" },
    { 5, "5" },
    { 10, "10" },
    { 50, "50" },
    { 99, "99" },
}

local items = {}
local visible = { items = {}, labels = {} }
local cat_options = { { "all", "All" } }
local cat_seq = {}
local cat_fixed = {}
local seq_to_enum = {}
local fixed_to_seq = {}
local fixed_to_enum = {}

local state = {
    ready = false,
    named = false,
    name_tries = 0,
    category = "all",
    selected = 0,
    amount = 1,
    drop = { open = false, filter = "" },
}

function Give.bind(deps)
    deps = deps or {}
    try_call = deps.try_call
    try_field = deps.try_field
    try_any = deps.try_any
    try_static = deps.try_static
    is_managed = deps.is_managed
    enum_value = deps.enum_value
    get_item_helper = deps.get_item_helper
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

local function strip_markup(name)
    if type(name) ~= "string" then
        return ""
    end
    local text = name
        :gsub("</?%s*[Cc][Oo][Ll][Oo][Rr][^>]*>", "")
        :gsub("</?%s*[%w_]+[^>]*>", "")
        :gsub("%s+", " ")
        :gsub("^%s+", "")
        :gsub("%s+$", "")
    return text
end

local function is_rejected_name(name)
    local text = strip_markup(name)
    if text == "" then
        return false
    end
    if text:find("#Rejected#", 1, true) then
        return true
    end
    if text:find("ItemData", 1, true) then
        return true
    end
    return false
end

local function is_placeholder_name(name)
    local text = strip_markup(name)
    if text == "" then
        return true
    end
    if is_rejected_name(text) then
        return true
    end
    if text == "No Name" or text == "None" or text == "INVALID" then
        return true
    end
    if text:find("アイテム名が設定されていません", 1, true) then
        return true
    end
    local lower = text:lower()
    if lower:find("item name is not set", 1, true) then
        return true
    end
    return false
end

local function lookup_name(item_id)
    item_id = serial_int(item_id) or item_id
    if type(item_id) ~= "number" or item_id == 0 then
        return nil
    end
    local name = strip_markup(managed_string(try_static("app.ItemUtil", { "getItemName" }, item_id)))
    if name ~= "" and not is_placeholder_name(name) then
        return name
    end
    local data = try_static("app.ItemUtil", { "getData" }, item_id)
    local guid = try_any(data, { "get_NameGuid" }) or try_field(data, "_NameGuid")
    name = strip_markup(guid_text(guid))
    if name ~= "" and not is_placeholder_name(name) then
        return name
    end
    return nil
end

local function item_name(item_id, fixed_id)
    return lookup_name(item_id) or lookup_name(fixed_id)
end

local function pretty_enum_name(enum_name)
    if type(enum_name) ~= "string" then
        return "Item"
    end
    local label = enum_name
        :gsub("^PLGROWTH_", "Growth ")
        :gsub("^CONSUME_", "Consume ")
        :gsub("^COLLECTION_", "Collection ")
        :gsub("^PLSKILL_", "Skill ")
        :gsub("^SWORDSKIN_", "Sword Skin ")
        :gsub("^BODYSKIN_", "Clothing Skin ")
        :gsub("^CLOAKSKIN_", "Haori Skin ")
        :gsub("^GAUNTLETSKIN_", "Gauntlet Skin ")
        :gsub("^NPCSKIN_", "NPC Skin ")
        :gsub("^DLC_SWORDSKIN_", "Sword Skin DLC ")
        :gsub("^DLC_CLOAKSKIN_", "Haori Skin DLC ")
        :gsub("^DLC_BODYSKIN_", "Clothing Skin DLC ")
        :gsub("^DLC_GAUNTLETSKIN_", "Gauntlet Skin DLC ")
        :gsub("^DLC_NPCSKIN_", "NPC Skin DLC ")
        :gsub("^ENEMYBOOK_", "Enemy Book ")
        :gsub("^TREASUREMAP_", "Treasure Map ")
        :gsub("^MEDICINE_BAG", "Medicine Bag")
        :gsub("^STAGE", "Stage ")
        :gsub("_", " ")
    return label
end

local function category_from_enum_name(name)
    if type(name) ~= "string" then
        return nil
    end
    if name:find("^VIRTUAL_") then
        return "skip"
    end
    if name:find("^ENEMYBOOK_") then
        return "picture_book"
    end
    if name:find("SKIN") or name:find("^DLC_") then
        return "appearance_change"
    end
    if name:find("^MEDICINE_BAG") or name == "MEDICINE" then
        return "skip"
    end
    if name:find("^PLGROWTH_") or name:find("^PLSKILL_") then
        return "growth_material"
    end
    if name:find("^CONSUME_") then
        return "equipable"
    end
    if name:find("^COLLECTION_") then
        return "tribute"
    end
    if name:find("^STAGE") or name:find("^TREASUREMAP") or name:find("^event_") then
        return "important"
    end
    return nil
end

local function enum_entries(type_name)
    local td = sdk.find_type_definition(type_name)
    if not td then
        return {}
    end
    local ok, fields = pcall(function()
        return td:get_fields()
    end)
    if not ok or not fields then
        return {}
    end
    local out = {}
    for _, field in ipairs(fields) do
        local name = field.get_name and field:get_name()
        if type(name) == "string" and name ~= "value__" then
            local ok_val, value = pcall(function()
                return field:get_data(nil)
            end)
            if ok_val and type(value) == "number" then
                table.insert(out, { name = name, id = value })
            end
        end
    end
    table.sort(out, function(a, b)
        return a.name < b.name
    end)
    return out
end

local function map_category(dest, type_name, name, key)
    local value = enum_value(type_name, name)
    if type(value) == "number" then
        dest[value] = key
    end
end

local function ui_category(item_or_key)
    local key = item_or_key
    if type(item_or_key) == "table" then
        key = item_or_key.category
    end
    return ENGINE_TO_UI[key]
end

local function is_omitted_cat(category)
    return category == "skip" or (category ~= nil and ENGINE_TO_UI[category] == nil)
end

local function build_category_maps()
    cat_options = { { "all", "All" } }
    cat_seq = {}
    cat_fixed = {}
    for _, row in ipairs(UI_CAT) do
        table.insert(cat_options, row)
    end
    local order = {
        "EQUIPABLE",
        "IMPORTANT",
        "TRIBUTE",
        "GROWTH_MATERIAL",
        "MEDICINE_BAG_MATERIAL",
        "PICTURE_BOOK",
    }
    for _, name in ipairs(order) do
        local key = name:lower()
        map_category(cat_seq, "app.ItemEnum.CATEGORY", name, key)
        map_category(cat_fixed, "app.ItemEnum.CATEGORY_Fixed", name, key)
    end
    for name, _ in pairs(CAT_SKIP) do
        map_category(cat_seq, "app.ItemEnum.CATEGORY", name, "skip")
        map_category(cat_fixed, "app.ItemEnum.CATEGORY_Fixed", name, "skip")
    end
    for name, _ in pairs(CAT_OMIT) do
        map_category(cat_seq, "app.ItemEnum.CATEGORY", name, "skip")
        map_category(cat_fixed, "app.ItemEnum.CATEGORY_Fixed", name, "skip")
    end
end

-- ItemData._Category is CATEGORY_Serializable: _Value / get_Value is CATEGORY_Fixed.
-- EQUIPABLE_Fixed=0 and IMPORTANT_Fixed=1 collide with sequential INVALID/EQUIPABLE.
-- Resolve Fixed first, then sequential 0-10.
local function category_from_int(value)
    if type(value) ~= "number" then
        return nil
    end
    if cat_fixed[value] then
        return cat_fixed[value]
    end
    if value >= 0 and value <= 10 then
        return cat_seq[value]
    end
    return nil
end

local function category_key(value)
    if type(value) == "number" then
        return category_from_int(value)
    end
    if not is_managed(value) then
        return nil
    end
    local fixed = try_any(value, { "get_FixedValue" })
        or try_field(value, "_Value")
        or try_any(value, { "get_Value" })
    local key = category_from_int(fixed)
    if key then
        return key
    end
    return category_from_int(try_field(value, "value__"))
end

local function find_item(id)
    for _, item in ipairs(items) do
        if item.id == id then
            return item
        end
    end
    return nil
end

local function item_kind(item)
    if type(item.id) == "number" and (fixed_to_seq[item.id] or item.id < 0 or item.id > 1000) then
        return "hash"
    end
    return "seq"
end

local function item_id(value)
    if type(value) == "number" then
        return value
    end
    if not is_managed(value) then
        return nil
    end
    local seq = try_any(value, { "get_Value" }) or try_field(value, "value__")
    if type(seq) == "number" then
        return seq
    end
    return serial_int(value)
end

local function resolve_enum(id, fixed)
    if type(id) == "number" and seq_to_enum[id] then
        return seq_to_enum[id]
    end
    if type(fixed) == "number" and fixed_to_enum[fixed] then
        return fixed_to_enum[fixed]
    end
    if type(id) == "number" and fixed_to_enum[id] then
        return fixed_to_enum[id]
    end
    return nil
end

local function catalog_remove(id)
    for i, item in ipairs(items) do
        if item.id == id then
            table.remove(items, i)
            return
        end
    end
end

local function catalog_add(id, label, category, max_count, named, fixed, enum_name)
    id = item_id(id) or id
    if type(id) ~= "number" then
        return
    end
    if is_omitted_cat(category) then
        catalog_remove(id)
        return
    end
    enum_name = enum_name or resolve_enum(id, fixed)
    local item = find_item(id)
    if item then
        -- Master table wins over enum-name guesses.
        if category then
            item.category = category
        end
        if type(max_count) == "number" and max_count > 0 then
            item.max_count = max_count
        end
        if type(fixed) == "number" then
            item.fixed = fixed
        end
        if enum_name and not item.enum_name then
            item.enum_name = enum_name
        end
        if label and (named or not item.named) then
            item.label = label
            if named then
                item.named = true
            end
        end
        return
    end
    table.insert(items, {
        id = id,
        fixed = (type(fixed) == "number") and fixed or nil,
        label = label or ("Item " .. tostring(id)),
        category = category,
        max_count = (type(max_count) == "number" and max_count > 0) and max_count or nil,
        named = named == true,
        enum_name = enum_name,
    })
end

local function fill_from_enum()
    -- Enum sequential IDs are kept for name maps. Grant uses ID_Fixed.
    seq_to_enum = {}
    fixed_to_seq = {}
    fixed_to_enum = {}
    local fixed_by_name = {}
    for _, entry in ipairs(enum_entries("app.ItemEnum.ID_Fixed")) do
        fixed_by_name[entry.name] = entry.id
        fixed_to_enum[entry.id] = entry.name
    end
    local invalid = enum_value("app.ItemEnum.ID", "INVALID")
    for _, entry in ipairs(enum_entries("app.ItemEnum.ID")) do
        seq_to_enum[entry.id] = entry.name
        local fixed = fixed_by_name[entry.name]
        if type(fixed) == "number" then
            fixed_to_seq[fixed] = entry.id
        end
        if entry.id ~= invalid then
            local category = category_from_enum_name(entry.name)
            catalog_add(entry.id, pretty_enum_name(entry.name), category, nil, false, fixed, entry.name)
        end
    end
end

local function get_item_master()
    local setting = get_various_setting()
    local master = try_any(setting, { "get_ItemData" }) or try_field(setting, "_ItemData")
    if is_managed(master) then
        return master
    end
    return nil
end

local function fill_from_table()
    local master = get_item_master()
    local list = try_call(master, "getValues")
        or try_any(master, { "get_Values" })
        or try_field(master, "_Values")
    local base = try_field(master, "_BaseItemData") or try_any(master, { "get_BaseItemData" })
    if not is_managed(list) then
        list = try_call(base, "getValues")
            or try_any(base, { "get_Values" })
            or try_field(base, "_Values")
    end
    local named = 0
    local function ingest(row)
        local id = item_id(try_any(row, { "get_Id" }) or try_field(row, "_Id"))
        local category = category_key(try_any(row, { "get_Category" }) or try_field(row, "_Category"))
        if not id or category == "skip" then
            return
        end
        local max_count = serial_int(try_any(row, { "get_MaxCountInit" }) or try_field(row, "_MaxCountInit"))
        local name = item_name(id)
        if not name then
            local guid = try_any(row, { "get_NameGuid" }) or try_field(row, "_NameGuid")
            name = guid_text(guid)
        end
        if is_rejected_name(name) then
            return
        end
        name = strip_markup(name)
        if is_placeholder_name(name) then
            name = nil
        end
        catalog_add(id, name, category, max_count, name ~= nil)
        local item = find_item(id)
        if item then
            local stock = serial_int(try_any(row, { "get_StockCount" }) or try_field(row, "_StockCount"))
            if type(stock) == "number" then
                item.stock = stock
            end
            local sort_id = serial_int(try_any(row, { "get_SortId" }) or try_field(row, "_SortId"))
            if type(sort_id) == "number" then
                item.sort_id = sort_id
            end
        end
        if name then
            named = named + 1
        end
    end
    if is_managed(list) then
        foreach_managed(list, ingest)
    else
        local n = try_call(master, "getDataNum") or try_call(base, "getDataNum")
        if type(n) == "number" then
            for i = 0, n - 1 do
                ingest(try_call(master, "getDataByIndex", i) or try_call(base, "getDataByIndex", i))
            end
        end
    end
    return named
end

-- Skins / books / keys often have MaxCountInit 1. addItem is for stacks.
local UNIQUE_CAT = {
    appearance_change = true,
}

local function is_unique_enum(enum_name)
    if type(enum_name) ~= "string" then
        return false
    end
    if enum_name:find("SKIN", 1, true) or enum_name:find("^DLC_") then
        return true
    end
    return false
end

local function is_stackable(item)
    if not item then
        return false
    end
    -- addItem / getItemCountOfId use ID_Fixed. Sequential enum ids return
    -- added=amount and 0->0. Keep the hash row only.
    if item_kind(item) ~= "hash" then
        return false
    end
    if item.category == "medicine_bag" then
        return false
    end
    if UNIQUE_CAT[item.category] or is_unique_enum(item.enum_name) then
        return false
    end
    local max = item.max_count
    return type(max) == "number" and max > 1
end

-- Hash rows the pause Items tab can show, plus Genma Notes.
local function is_listable(item)
    if not item then
        return false
    end
    if item_kind(item) ~= "hash" then
        return false
    end
    if not ui_category(item) then
        return false
    end
    if is_rejected_name(item.label) or is_placeholder_name(item.label) then
        return false
    end
    return true
end

local function item_less(a, b)
    local sa = type(a.sort_id) == "number" and a.sort_id or 999999
    local sb = type(b.sort_id) == "number" and b.sort_id or 999999
    if sa ~= sb then
        return sa < sb
    end
    return tostring(a.label or "") < tostring(b.label or "")
end

-- addItem runs execSpecialItemObtainEffect → activateAndEquipSkill.
-- That AVs in the skill-tree cache if the node is not ready.
local function is_skill_obtain(item)
    if not item then
        return false
    end
    if item.category == "growth_material" then
        return true
    end
    local name = item.enum_name
    if type(name) == "string" and (name:find("^PLSKILL_", 1) or name:find("^PLGROWTH_", 1)) then
        return true
    end
    return false
end

local function is_story_item(item)
    if not item then
        return false
    end
    if item.category == "important" then
        return true
    end
    local name = item.enum_name
    if type(name) == "string" then
        if name:find("^STAGE") or name:find("^TREASUREMAP") or name:find("^event_") then
            return true
        end
    end
    local label = strip_markup(item.label)
    if label:find("Key", 1, true) then
        return true
    end
    return false
end

local function is_bulk_safe(item)
    return is_stackable(item) and not is_skill_obtain(item) and not is_story_item(item)
end

local function category_label()
    for _, opt in ipairs(cat_options) do
        if opt[1] == state.category then
            return opt[2]
        end
    end
    return "Category"
end

local function row_probe_text(item)
    local label = strip_markup(item.label)
    local kind = "seq"
    if type(item.id) == "number" and (item.id < 0 or item.id > 1000) then
        kind = "hash"
    end
    if type(item.id) == "number" and fixed_to_seq[item.id] then
        kind = "hash"
    end
    return string.format(
        "%s | id=%s kind=%s fixed=%s seq=%s cat=%s enum=%s max=%s stock=%s named=%s",
        label,
        tostring(item.id),
        kind,
        tostring(item.fixed),
        tostring(fixed_to_seq[item.id] or item.id),
        tostring(item.category),
        tostring(item.enum_name or resolve_enum(item.id, item.fixed) or ""),
        tostring(item.max_count),
        tostring(item.stock),
        tostring(item.named)
    )
end

local function probe_duplicates()
    if state.dup_probed then
        return
    end
    state.dup_probed = true
    local keep = 0
    local skip_max = 0
    local skip_cat = 0
    local ui = { items = 0, materials = 0, offerings = 0, valuables = 0, genma_notes = 0 }
    for _, item in ipairs(items) do
        local key = ui_category(item)
        if is_listable(item) then
            keep = keep + 1
            if ui[key] then
                ui[key] = ui[key] + 1
            end
        elseif UNIQUE_CAT[item.category] or is_unique_enum(item.enum_name) then
            skip_cat = skip_cat + 1
        else
            skip_max = skip_max + 1
        end
    end
    log.info(string.format(
        "[onimusha] give-ui keep=%d items=%d mats=%d offer=%d val=%d notes=%d skip_unique=%d skip_other=%d rows=%d",
        keep,
        ui.items,
        ui.materials,
        ui.offerings,
        ui.valuables,
        ui.genma_notes,
        skip_cat,
        skip_max,
        #items
    ))
end

local function probe_shown(filter)
    filter = type(filter) == "string" and filter or ""
    local key = tostring(state.category) .. "|" .. filter:lower() .. "|" .. tostring(#visible.items)
    if state.drop._probe_key == key then
        return
    end
    state.drop._probe_key = key
    local needle = filter:lower()
    local n = 0
    for _, item in ipairs(visible.items) do
        local label = strip_markup(item.label)
        if needle == "" or label:lower():find(needle, 1, true) then
            n = n + 1
            log.info("[onimusha] give-row " .. row_probe_text(item))
        end
    end
    log.info(string.format("[onimusha] give-shown n=%d filter=%q cat=%s", n, filter, tostring(state.category)))
end

local function pouch_level(enum_name)
    if type(enum_name) ~= "string" then
        return nil
    end
    return enum_name:match("LV0*(%d+)$")
end

local function disambiguate_labels()
    local by_label = {}
    for _, item in ipairs(items) do
        local label = strip_markup(item.label)
        if label ~= "" then
            by_label[label] = by_label[label] or {}
            table.insert(by_label[label], item)
        end
    end
    for label, group in pairs(by_label) do
        if #group < 2 then
            -- only one row, nothing to split
        else
            local seen = {}
            local unique = 0
            for _, item in ipairs(group) do
                local key = item.enum_name or tostring(item.id)
                if not seen[key] then
                    seen[key] = true
                    unique = unique + 1
                end
            end
            if unique > 1 then
                for _, item in ipairs(group) do
                    local lv = pouch_level(item.enum_name)
                    if lv then
                        item.label = label .. " Lv" .. lv
                    end
                end
            end
        end
    end
end

local function refresh_visible()
    visible.items = {}
    visible.labels = {}
    for _, item in ipairs(items) do
        local ui_cat = ui_category(item)
        if ui_cat
            and (state.category == "all" or ui_cat == state.category)
            and is_listable(item)
        then
            table.insert(visible.items, item)
            table.insert(visible.labels, strip_markup(item.label))
        end
    end
    if state.selected > #visible.items then
        state.selected = 0
    end
end

local function named_count()
    local n = 0
    for _, item in ipairs(items) do
        if item.named then
            n = n + 1
        end
    end
    return n
end

local function refresh_names()
    local before = named_count()
    for _, item in ipairs(items) do
        if item.named and is_rejected_name(item.label) then
            item.named = false
        end
        if not item.named then
            local name = item_name(item.id, item.fixed)
            if name then
                item.label = name
                item.named = true
            end
        end
    end
    fill_from_table()
    local after = named_count()
    if after > before then
        disambiguate_labels()
        table.sort(items, item_less)
    end
    refresh_visible()
    state.name_tries = (state.name_tries or 0) + 1
    if after == #items or state.name_tries > 90 then
        state.named = true
        probe_duplicates()
    end
end

local function build_catalog()
    items = {}
    build_category_maps()
    fill_from_enum()
    fill_from_table()
    disambiguate_labels()
    table.sort(items, item_less)
    refresh_visible()
end

local function ensure_catalog()
    if not state.ready or #items == 0 then
        build_catalog()
        state.ready = #items > 0
    end
    if not state.named then
        refresh_names()
    end
end

local function find_method_arity(td, name, arity)
    if not td or not td.get_methods then
        return nil
    end
    local methods = td:get_methods()
    if not methods then
        return nil
    end
    for _, method in ipairs(methods) do
        if method.get_name and method:get_name() == name then
            local n = method.get_num_params and method:get_num_params()
            if n == arity then
                return method
            end
        end
    end
    return nil
end

local function helper_method(helper, signatures, ...)
    local td = sdk.find_type_definition("app.SaveDataHelper_Item")
    if not td or not helper then
        return nil
    end
    local n = select("#", ...)
    local a, b, c, d, e = ...
    for _, sig in ipairs(signatures) do
        local method = td:get_method(sig)
        if not method and type(sig) == "string" then
            local name, arity = sig:match("^([%w_]+)#(%d+)$")
            if name and arity then
                method = find_method_arity(td, name, tonumber(arity))
            end
        end
        if method then
            local ok, result = pcall(function()
                if n >= 5 then
                    return method:call(helper, a, b, c, d, e)
                end
                if n >= 4 then
                    return method:call(helper, a, b, c, d)
                end
                if n >= 3 then
                    return method:call(helper, a, b, c)
                end
                if n >= 2 then
                    return method:call(helper, a, b)
                end
                if n >= 1 then
                    return method:call(helper, a)
                end
                return method:call(helper)
            end)
            if ok then
                return result
            end
        end
    end
    return nil
end

local function item_count(helper, id)
    if type(id) ~= "number" then
        return nil
    end
    local n = helper_method(helper, {
        "getItemCountOfId(System.Int32)",
        "getItemCountOfId",
    }, id)
    if type(n) == "number" then
        return n
    end
    return try_call(helper, "getItemCountOfId", id)
end

local function extra_param()
    local ok, obj = pcall(function()
        return sdk.create_instance("app.ItemUtil.cIdAmountPair.cAdditionalParam")
    end)
    if ok and obj then
        return obj
    end
    return nil
end

local function try_box(helper, id, amount)
    return helper_method(helper, {
        "addItemToBox(System.Int32, System.UInt32)",
        "addItemToBox#2",
        "addItemToBox",
    }, id, amount)
end

-- Inventory count only. Does not run obtain / skill / objective.
local function try_add_num(helper, id, amount)
    local data = helper_method(helper, {
        "getItem(System.Int32)",
        "getItem#1",
        "getItem",
    }, id)
    if not is_managed(data) then
        return nil
    end
    return helper_method(helper, {
        "addItemNum(app.SaveDataHelper_Item.cItemData, System.UInt32)",
        "addItemNum#2",
        "addItemNum",
    }, data, amount)
end

local function count_grew(before, after)
    return type(before) == "number" and type(after) == "number" and after > before
end

local function try_add(helper, id, amount, notify)
    -- Family addItem is 5 args. REF invoke requires every param, including optionals.
    if notify == nil then
        notify = true
    end
    local extra = extra_param()
    local added = nil
    for _, force in ipairs({ true, false }) do
        added = helper_method(helper, {
            "addItem(System.Int32, System.UInt32, System.Boolean, System.Boolean, app.ItemUtil.cIdAmountPair.cAdditionalParam)",
            "addItem#5",
        }, id, amount, notify, force, extra)
        if type(added) == "number" and added > 0 then
            return added
        end
    end
    helper_method(helper, {
        "addItemHasObtainNum(System.Int32, System.UInt32)",
        "addItemHasObtainNum#2",
    }, id, amount)
    added = helper_method(helper, {
        "addItem(System.Int32, System.UInt32, System.Boolean, System.Boolean, app.ItemUtil.cIdAmountPair.cAdditionalParam)",
        "addItem#5",
    }, id, amount, false, true, extra)
    if type(added) ~= "number" or added <= 0 then
        added = try_box(helper, id, amount)
    end
    return added
end

local function give_item(item, amount, notify)
    if not item then
        return false, "no item"
    end
    if item_kind(item) ~= "hash" then
        return false, "not hash"
    end
    local helper = get_item_helper and get_item_helper()
    if not is_managed(helper) then
        return false, "no item helper"
    end
    amount = tonumber(amount) or 1
    if amount < 1 then
        amount = 1
    end
    if item.max_count and item.max_count > 0 and amount > item.max_count then
        amount = item.max_count
    end

    local id = item.id
    local before = item_count(helper, id)
    local added = try_add_num(helper, id, amount)
    local after = item_count(helper, id)
    -- New stacks have no cItemData yet. addItem creates the slot.
    -- Skip addItem for skill books — that AVs in activateAndEquipSkill.
    if not count_grew(before, after) and not is_skill_obtain(item) then
        added = try_add(helper, id, amount, notify)
        after = item_count(helper, id)
    end
    if not count_grew(before, after) and is_skill_obtain(item) then
        added = try_box(helper, id, amount)
        after = item_count(helper, id)
    end

    if item.category == "medicine_bag" then
        helper_method(helper, {
            "addDirectMedicineBag(System.Int32, System.Boolean)",
            "addDirectMedicineBag",
        }, id, notify == true)
    end

    after = item_count(helper, id)
    return count_grew(before, after), before, after, added, amount
end

local function give_selected()
    local item = visible.items[state.selected]
    if not item then
        log_action("give failed: no item")
        return
    end
    local amount = tonumber(state.amount) or 1
    local ok, before, after, added, used = give_item(item, amount, true)
    if type(before) == "number" and type(after) == "number" then
        log_action(
            "give "
                .. tostring(item.label)
                .. " x"
                .. tostring(used)
                .. " "
                .. tostring(before)
                .. "->"
                .. tostring(after)
                .. " added="
                .. tostring(added)
        )
        return
    end
    if not ok then
        log_action("give failed: addItem " .. tostring(item.label) .. " id=" .. tostring(item.id))
        return
    end
    log_action("give " .. tostring(item.label) .. " x" .. tostring(used) .. " id=" .. tostring(item.id))
end

local bulk = {
    active = false,
    queue = {},
    index = 0,
    ok = 0,
    fail = 0,
    label = "",
}

local function start_give_category()
    if state.category ~= "picture_book" then
        log_action("give all blocked: picture book only")
        return
    end
    bulk.queue = {}
    local skipped = 0
    for _, item in ipairs(visible.items) do
        if is_bulk_safe(item) then
            table.insert(bulk.queue, item)
        else
            skipped = skipped + 1
        end
    end
    bulk.index = 0
    bulk.ok = 0
    bulk.fail = 0
    bulk.label = category_label()
    bulk.active = #bulk.queue > 0
    if not bulk.active then
        log_action("give all " .. bulk.label .. " failed: empty list skip=" .. tostring(skipped))
        return
    end
    log_action("give all " .. bulk.label .. " start n=" .. tostring(#bulk.queue) .. " skip=" .. tostring(skipped))
end

function Give.busy()
    return bulk.active == true
end

function Give.tick()
    if not bulk.active then
        return
    end
    bulk.index = bulk.index + 1
    local item = bulk.queue[bulk.index]
    if not item then
        bulk.active = false
        log_action(string.format(
            "give all %s done ok=%s fail=%s",
            bulk.label,
            tostring(bulk.ok),
            tostring(bulk.fail)
        ))
        return
    end
    log_action(string.format(
        "give all %s %d/%d %s id=%s",
        bulk.label,
        bulk.index,
        #bulk.queue,
        tostring(item.label),
        tostring(item.id)
    ))
    local call_ok, ok, before, after, added = pcall(give_item, item, 1, false)
    if not call_ok then
        bulk.fail = bulk.fail + 1
        log_action("give all lua-fail " .. tostring(item.label) .. " " .. tostring(ok))
        return
    end
    if ok then
        bulk.ok = bulk.ok + 1
        if type(before) == "number" and type(after) == "number" then
            log_action(string.format(
                "give all ok %s %s->%s added=%s",
                tostring(item.label),
                tostring(before),
                tostring(after),
                tostring(added)
            ))
        end
        return
    end
    bulk.fail = bulk.fail + 1
    log_action("give all miss " .. tostring(item.label) .. " id=" .. tostring(item.id))
end

function Give.draw(ui)
    local catalog_ok, catalog_err = pcall(ensure_catalog)
    if not catalog_ok then
        ui.muted("Item list failed: " .. tostring(catalog_err))
        return
    end
    ui.muted("Best effort. Most items can be added. Some will not add if they have story requirements.")
    if #items == 0 then
        ui.muted("Waiting for item list.")
        return
    end

    if not UI_KEYS[state.category] then
        state.category = "all"
        state.selected = 0
        refresh_visible()
    end
    local cat_changed = ui.bind_combo("Category", state, "category", cat_options)
    if cat_changed then
        state.selected = 0
        state.amount = 1
        state.drop.open = false
        state.drop.filter = ""
        refresh_visible()
    end

    if #visible.labels == 0 then
        if not state.named then
            ui.muted("Waiting for item list.")
        else
            ui.muted("No items in this category.")
        end
        return
    end

    ui.label("Item")
    if state.drop.open then
        probe_shown(state.drop.filter)
    end
    local pick = visible.items[state.selected]
    local caption = pick and pick.label or "Pick..."
    local sel = ui.filter_dropdown("give_item", caption, visible.labels, state.selected, state.drop, {
        header = "Items",
        placeholder = "Pick...",
        height = 240,
    })
    if sel ~= state.selected then
        state.selected = sel
        state.amount = 1
        pick = visible.items[state.selected]
    end

    ui.bind_combo("Amount", state, "amount", AMOUNT_OPTIONS)

    if pick then
        if ui.button("Give " .. pick.label) then
            local amount = tonumber(state.amount) or 1
            local warn = "Best effort. Writes the save."
            if is_story_item(pick) then
                warn = "Story / key item. May not add if the story is not ready. Can skip objectives if it does."
            end
            ui.confirm({
                title = "Give item?",
                lines = {
                    "Give " .. pick.label .. " x" .. tostring(amount) .. "?",
                    warn,
                },
                yes = "Give",
                no = "Cancel",
                on_yes = function()
                    state.amount = amount
                    give_selected()
                end,
            })
        end
    else
        ui.muted("Pick an item, then Give.")
    end

    if bulk.active then
        imgui.spacing()
        ui.muted(string.format(
            "Give all %s %d/%d  ok=%d  fail=%d",
            bulk.label,
            bulk.index,
            #bulk.queue,
            bulk.ok,
            bulk.fail
        ))
    end
end

function Give.reset()
    bulk.active = false
    bulk.queue = {}
    bulk.index = 0
    bulk.ok = 0
    bulk.fail = 0
    bulk.label = ""
    state.ready = false
    state.named = false
    state.name_tries = 0
    state.drop.open = false
    state.drop.filter = ""
    state.drop._probe_key = nil
    state.dup_probed = false
    items = {}
    refresh_visible()
end

_G.OnimushaGive = Give
return Give
