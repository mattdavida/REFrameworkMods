-- Free Smithy Crafts + Unlock All Armor.
-- Primitive arrays use write_dword at object+0x20. No smithy method hooks.
-- Do not invent EquipRecipeData. Do not Clear/rebuild unlock on layered.

local FreeTree = _G.MHFreeTree or {}
_G.MHFreeTree = FreeTree

FreeTree.free = false
FreeTree.unlock = false

local GUI = "snow.gui.fsm.smithy.GuiSmithyFsmManager"
local CTRL = "snow.gui.fsm.smithy.GuiSmithy.PlayerArmorSeriesListControl"
local MAKING = "snow.data.PlEquipMakingData"
local RECIPE = "snow.data.EquipRecipeData"
local SERIES = "snow.data.ArmorProductSeriesData"
local ITEM_FLAG_NONE = 67108864 -- ContentsIdSystem.ItemId.I_Unclassified_None
local FORGE_LIST = 0
local LAYERED_STATE = 4

local last_log_slots = -1
local last_recipe_unlock = -1
local unlock_session = false
local forge_seen = false
local lists_zeroed = false
local last_filter = -999
local last_sel_key = 0
local ticks = 0
local hooked = false
local methods = {}
local offset_cache = {}

local PARAM_FIELDS = {
    "_PlWeaponProductUserDataParam",
    "_PlWeaponProcessUserDataParam",
    "_PlWeaponChangeUserDataParam",
    "_PlArmorProductUserDataParam",
    "_PlOverwearProductUserDataParam",
    "_PlOverwearWeaponProductUserDataParam",
}

local function is_managed(obj)
    return obj ~= nil and type(obj) == "userdata"
end

local function bind(type_name, signature)
    local td = sdk.find_type_definition(type_name)
    if not td then
        return nil
    end
    local method = nil
    pcall(function()
        method = td:get_method(signature)
    end)
    return method
end

local function call(method, obj, ...)
    if not method or not is_managed(obj) then
        return nil
    end
    local n = select("#", ...)
    local a, b, c = ...
    local ok, result = pcall(function()
        if n >= 3 then
            return method:call(obj, a, b, c)
        end
        if n >= 2 then
            return method:call(obj, a, b)
        end
        if n >= 1 then
            return method:call(obj, a)
        end
        return method:call(obj)
    end)
    if ok then
        return result
    end
    return nil
end

local function field(obj, name)
    if not is_managed(obj) or type(name) ~= "string" then
        return nil
    end
    local ok, value = pcall(function()
        return obj:get_field(name)
    end)
    if ok then
        return value
    end
    return nil
end

local function type_full(obj)
    if not is_managed(obj) then
        return nil
    end
    local ok, name = pcall(function()
        return obj:get_type_definition():get_full_name()
    end)
    if ok then
        return name
    end
    return nil
end

local function is_type(obj, full)
    return type_full(obj) == full
end

local function as_int(value)
    if type(value) == "number" then
        return math.floor(value)
    end
    if type(value) == "boolean" then
        return value and 1 or 0
    end
    return nil
end

local function field_offset(obj, name)
    if not is_managed(obj) or type(name) ~= "string" then
        return nil
    end
    local td = nil
    pcall(function()
        td = obj:get_type_definition()
    end)
    if not td then
        return nil
    end
    local key = nil
    pcall(function()
        key = td:get_full_name() .. "\0" .. name
    end)
    if key and offset_cache[key] ~= nil then
        if offset_cache[key] == false then
            return nil
        end
        return offset_cache[key]
    end
    local cur = td
    while cur do
        local found = nil
        pcall(function()
            found = cur:get_field(name)
        end)
        if not found then
            local fields = nil
            pcall(function()
                fields = cur:get_fields()
            end)
            if fields then
                for i = 1, #fields do
                    local fname = nil
                    pcall(function()
                        fname = fields[i]:get_name()
                    end)
                    if fname == name then
                        found = fields[i]
                        break
                    end
                end
            end
        end
        if found then
            local off = nil
            pcall(function()
                off = found:get_offset_from_base()
            end)
            if type(off) == "number" then
                if key then
                    offset_cache[key] = off
                end
                return off
            end
        end
        local parent = nil
        pcall(function()
            parent = cur:get_parent_type()
        end)
        cur = parent
    end
    if key then
        offset_cache[key] = false
    end
    return nil
end

local function write_i32_field(obj, name, value)
    local off = field_offset(obj, name)
    if off == nil then
        return false
    end
    local ok = pcall(function()
        obj:write_dword(off, value)
    end)
    return ok == true
end

local function read_dword(obj, off)
    if not is_managed(obj) or type(off) ~= "number" then
        return nil
    end
    local ok, value = pcall(function()
        return obj:read_dword(off)
    end)
    if ok and type(value) == "number" then
        return value
    end
    return nil
end

local function write_dword(obj, off, value)
    if not is_managed(obj) then
        return false
    end
    local ok = pcall(function()
        obj:write_dword(off, value)
    end)
    return ok == true
end

local function arr_len(arr)
    if not is_managed(arr) then
        return 0
    end
    local n = as_int(call(methods.arr_len, arr))
    if n then
        return n
    end
    n = as_int(field(arr, "_n"))
    return n or 0
end

local function arr_get(arr, i)
    if not is_managed(arr) then
        return nil
    end
    local item = call(methods.arr_get, arr, i)
    if is_managed(item) then
        return item
    end
    local ok, el = pcall(function()
        return arr:get_element(i)
    end)
    if ok and is_managed(el) then
        return el
    end
    return nil
end

local function list_count(list)
    if not is_managed(list) then
        return 0
    end
    local n = as_int(field(list, "_size"))
    if n then
        return n
    end
    n = as_int(call(methods.list_count, list))
    return n or 0
end

local function list_item(list, i)
    if not is_managed(list) then
        return nil
    end
    local item = call(methods.list_item, list, i)
    if is_managed(item) then
        return item
    end
    return arr_get(list, i)
end

local function list_add(list, item)
    if not is_managed(list) or not is_managed(item) then
        return false
    end
    local before = list_count(list)
    if methods.list_add then
        call(methods.list_add, list, item)
    else
        pcall(function()
            list:call("Add", item)
        end)
    end
    return list_count(list) > before
end

local function zero_u32_array(arr)
    if not is_managed(arr) then
        return 0
    end
    local n = arr_len(arr)
    if n <= 0 then
        return 0
    end
    local changed = 0
    for i = 0, n - 1 do
        local off = 0x20 + i * 4
        local cur = read_dword(arr, off)
        if cur ~= nil and cur ~= 0 then
            if write_dword(arr, off, 0) then
                changed = changed + 1
            end
        end
    end
    return changed
end

local function bind_methods()
    methods.is_open = bind(GUI, "isOpenSmithy()")
    methods.menu_state = bind(GUI, "get_SmithyArmorCreateMenuState()")
    methods.armor_ctrl = bind(GUI, "getArmorSeriesListCtrl()")
    methods.sel_weapon = bind(GUI, "getSelectedWeaponMakingData()")
    methods.sel_ow_weapon = bind(GUI, "getSelectedOverwearWeaponMakingData()")
    methods.sel_armor = bind(CTRL, "getSelectedArmorProductMakingData()")
    methods.sel_ow_armor = bind(CTRL, "getSelectedOverwearProductMakingData()")
    methods.making_product = bind(MAKING, "get_ProductRecipe()")
    methods.making_process = bind(MAKING, "get_ProcessRecipe()")
    methods.making_change = bind(MAKING, "get_ChangeRecipe()")
    methods.exists_recipe = bind(MAKING, "existsProductRecipe()")
    methods.get_product = bind(MAKING, "getProductRecipe()")
    methods.recipe_value = bind(RECIPE, "set_Value(System.UInt32)")
    methods.recipe_cat = bind(RECIPE, "get_CategoryData()")
    methods.cat_num = bind("snow.data.EquipRecipeData.RecipeItemCategoryData", "set_Num(System.UInt32)")
        or bind("snow.data.RecipeItemCategoryData", "set_Num(System.UInt32)")
    methods.series_making = bind(SERIES, "get_EquipMakingDataList()")
    methods.series_collab = bind(SERIES, "get_IsCollabo()")
    methods.series_group = bind(SERIES, "get_DifficultyGroup()")
    methods.arr_len = bind("System.Array", "get_Length()")
    methods.arr_get = bind("System.Array", "GetValue(System.Int32)")
    methods.list_count = bind("System.Collections.Generic.List`1", "get_Count()")
        or bind("System.Collections.ICollection", "get_Count()")
    methods.list_item = bind("System.Collections.Generic.List`1", "get_Item(System.Int32)")
    methods.list_add = bind("System.Collections.Generic.List`1", "Add(System.Object)")
    return methods.is_open ~= nil
end

local function zero_recipe(recipe)
    if not is_type(recipe, RECIPE) then
        return 0
    end
    write_i32_field(recipe, "<Value>k__BackingField", 0)
    write_i32_field(recipe, "_Value", 0)
    write_i32_field(recipe, "Value", 0)
    pcall(function()
        recipe:set_field("<Value>k__BackingField", 0)
    end)
    pcall(function()
        recipe:set_field("Value", 0)
    end)
    call(methods.recipe_value, recipe, 0)
    local slots = 0
    local items = field(recipe, "ItemDataList")
    if is_managed(items) then
        slots = slots + zero_u32_array(field(items, "ItemNum"))
    end
    local cat = call(methods.recipe_cat, recipe)
    if not is_managed(cat) then
        cat = field(recipe, "<CategoryData>k__BackingField")
    end
    if is_managed(cat) then
        write_i32_field(cat, "<Num>k__BackingField", 0)
        call(methods.cat_num, cat, 0)
    end
    for i = 1, #PARAM_FIELDS do
        local param = field(recipe, PARAM_FIELDS[i])
        if is_managed(param) then
            slots = slots + zero_u32_array(field(param, "_ItemNum"))
            write_i32_field(param, "_MaterialCategoryNum", 0)
        end
    end
    return slots
end

local function zero_making(making)
    if not is_type(making, MAKING) then
        return 0
    end
    local slots = 0
    slots = slots + zero_recipe(call(methods.making_product, making))
    slots = slots + zero_recipe(call(methods.making_process, making))
    slots = slots + zero_recipe(call(methods.making_change, making))
    return slots
end

local function zero_making_array(arr)
    if not is_managed(arr) then
        return 0
    end
    local n = arr_len(arr)
    local slots = 0
    for i = 0, n - 1 do
        slots = slots + zero_making(arr_get(arr, i))
    end
    return slots
end

local function zero_list(list)
    if not is_managed(list) then
        return 0
    end
    local n = list_count(list)
    local slots = 0
    for i = 0, n - 1 do
        slots = slots + zero_making(list_item(list, i))
    end
    return slots
end

local function zero_series(series)
    if not is_type(series, SERIES) then
        return 0
    end
    local making = call(methods.series_making, series)
    if not is_managed(making) then
        making = field(series, "<EquipMakingDataList>k__BackingField")
    end
    return zero_making_array(making)
end

local function zero_series_list(list)
    if not is_managed(list) then
        return 0
    end
    local n = list_count(list)
    local slots = 0
    for i = 0, n - 1 do
        slots = slots + zero_series(list_item(list, i))
    end
    return slots
end

local function is_forge_armor_list(gui)
    if not is_managed(gui) then
        return false
    end
    if as_int(call(methods.menu_state, gui)) == LAYERED_STATE then
        return false
    end
    local ctrl = call(methods.armor_ctrl, gui)
    if not is_managed(ctrl) then
        return false
    end
    return as_int(field(ctrl, "_ArmorSeriesListType")) == FORGE_LIST
end

local function series_has_product_recipe(series)
    if not is_managed(series) then
        return false
    end
    local making = call(methods.series_making, series)
    if not is_managed(making) then
        making = field(series, "<EquipMakingDataList>k__BackingField")
    end
    if not is_managed(making) then
        return false
    end
    local n = arr_len(making)
    for p = 0, n - 1 do
        local piece = arr_get(making, p)
        if is_managed(piece) then
            if call(methods.exists_recipe, piece) == true then
                return true
            end
            if is_managed(call(methods.get_product, piece)) then
                return true
            end
            if is_managed(call(methods.making_product, piece)) then
                return true
            end
        end
    end
    return false
end

-- GroupFilter: Lower=0 Upper=1 Collabo=2 MR=3
-- DifficultyGroup: Lower=0 Upper=1 Master=2 Error=3
local function armor_bucket(series)
    if call(methods.series_collab, series) == true then
        return 2
    end
    local group = as_int(call(methods.series_group, series))
    if group == 0 then
        return 0
    end
    if group == 1 then
        return 1
    end
    if group == 2 then
        return 3
    end
    return -1
end

local function unlock_armor_recipes(all)
    if last_recipe_unlock > 0 or not is_managed(all) then
        return 0
    end
    local n = arr_len(all)
    local cleared = 0
    for i = 0, n - 1 do
        local series = arr_get(all, i)
        local making = call(methods.series_making, series)
        if is_managed(making) then
            local slots = arr_len(making)
            for p = 0, slots - 1 do
                local piece = arr_get(making, p)
                local recipe = call(methods.get_product, piece)
                if not is_managed(recipe) then
                    recipe = call(methods.making_product, piece)
                end
                if is_managed(recipe) then
                    local param = field(recipe, "_PlArmorProductUserDataParam")
                    if is_managed(param) then
                        write_i32_field(param, "_ItemFlag", ITEM_FLAG_NONE)
                        write_i32_field(param, "_ProgressFlag", 0)
                        write_i32_field(param, "_EnemyFlag", 0)
                        cleared = cleared + 1
                    end
                end
            end
        end
    end
    return cleared
end

local function ensure_armor_tabs(gui)
    if not is_managed(gui) then
        return
    end
    local cur = field(gui, "<SmithyArmorCreateTabList>k__BackingField")
    if arr_len(cur) == 4 then
        write_dword(cur, 0x20, 0)
        write_dword(cur, 0x24, 1)
        write_dword(cur, 0x28, 2)
        write_dword(cur, 0x2C, 3)
    end
end

local function obj_key(obj)
    if not is_managed(obj) then
        return 0
    end
    local addr = 0
    pcall(function()
        addr = obj:get_address()
    end)
    if type(addr) == "number" then
        return addr
    end
    return 0
end

local function unlock_armor(gui)
    if unlock_session then
        return
    end
    unlock_session = true

    local ctrl = call(methods.armor_ctrl, gui)
    if not is_managed(ctrl) then
        return
    end
    local data = field(ctrl, "_SmithyArmorData")
    if not is_managed(data) then
        return
    end
    local all = field(data, "<AllArmorProductSeriesDataList>k__BackingField")
    local buckets = field(data, "<ArmorProductSeriesDataList>k__BackingField")
    if not is_managed(all) or not is_managed(buckets) then
        return
    end

    local lists = {}
    for i = 0, 3 do
        lists[i] = arr_get(buckets, i) or list_item(buckets, i)
    end

    local n = arr_len(all)
    local added = 0
    local counts = { [0] = 0, [1] = 0, [2] = 0, [3] = 0 }
    for i = 0, n - 1 do
        local series = arr_get(all, i)
        if is_type(series, SERIES) and series_has_product_recipe(series) then
            local bucket = armor_bucket(series)
            if bucket >= 0 and is_managed(lists[bucket]) then
                if list_add(lists[bucket], series) then
                    counts[bucket] = counts[bucket] + 1
                    added = added + 1
                end
            end
        end
    end

    local recipes = unlock_armor_recipes(all)
    if recipes > 0 then
        last_recipe_unlock = recipes
        log.info("[UnlockArmor] cleared " .. recipes .. " recipe unlock flags")
    end
    ensure_armor_tabs(gui)
    log.info(string.format(
        "[UnlockArmor] added %d series (low %d high %d special %d mr %d)",
        added, counts[0], counts[1], counts[2], counts[3]
    ))
end

local function zero_selected(gui, forge_armor)
    local slots = 0
    local weapon = call(methods.sel_weapon, gui)
    local ow_weapon = call(methods.sel_ow_weapon, gui)
    local ctrl = call(methods.armor_ctrl, gui)
    local armor = nil
    local ow_armor = nil
    if is_managed(ctrl) then
        if forge_armor then
            armor = call(methods.sel_armor, ctrl)
        end
        ow_armor = call(methods.sel_ow_armor, ctrl)
    end
    slots = slots + zero_making(weapon)
    slots = slots + zero_making(ow_weapon)
    slots = slots + zero_making(armor)
    slots = slots + zero_making(ow_armor)
    return slots, obj_key(weapon) + obj_key(ow_weapon) + obj_key(armor) + obj_key(ow_armor)
end

local function zero_visible(gui, forge_armor)
    local slots = 0
    slots = slots + zero_list(field(gui, "_WeaponSortProductList"))
    slots = slots + zero_list(field(gui, "_WeaponSortProcessList"))
    slots = slots + zero_list(field(gui, "_OverwearWeaponProductList"))
    local ctrl = call(methods.armor_ctrl, gui)
    if is_managed(ctrl) then
        if forge_armor then
            slots = slots + zero_series_list(field(ctrl, "_ArmorProductSeriesList"))
        end
        slots = slots + zero_making(call(methods.sel_ow_armor, ctrl))
    end
    return slots
end

local function apply()
    if not FreeTree.free and not FreeTree.unlock then
        return
    end
    local gui = nil
    pcall(function()
        gui = sdk.get_managed_singleton(GUI)
    end)
    if not is_managed(gui) then
        return
    end
    if call(methods.is_open, gui) ~= true then
        last_log_slots = -1
        unlock_session = false
        forge_seen = false
        lists_zeroed = false
        last_filter = -999
        last_sel_key = 0
        return
    end
    local forge_armor = is_forge_armor_list(gui)
    if not forge_armor then
        forge_seen = false
    elseif FreeTree.unlock and not unlock_session then
        if forge_seen then
            unlock_armor(gui)
        else
            forge_seen = true
        end
    end
    if not FreeTree.free then
        return
    end

    local slots, sel_key = zero_selected(gui, forge_armor)
    local ctrl = call(methods.armor_ctrl, gui)
    local filter = as_int(field(ctrl, "_ArmorGroupFiltered")) or -1
    if not lists_zeroed then
        lists_zeroed = true
        last_filter = filter
        last_sel_key = sel_key
        slots = slots + zero_visible(gui, forge_armor)
    elseif filter ~= last_filter then
        last_filter = filter
        if forge_armor then
            slots = slots + zero_series_list(field(ctrl, "_ArmorProductSeriesList"))
        end
    elseif sel_key ~= last_sel_key then
        last_sel_key = sel_key
    end

    if slots > 0 and slots ~= last_log_slots then
        last_log_slots = slots
        log.info("[FreeSmithyCrafts] zeroed " .. slots .. " material slots")
    end
end

local function tick()
    ticks = ticks + 1
    if not FreeTree.free and not FreeTree.unlock then
        return
    end
    if (ticks % 8) ~= 1 then
        return
    end
    if not methods.is_open then
        local ok, ready = pcall(bind_methods)
        if not (ok and ready) then
            return
        end
    end
    local ok, err = pcall(apply)
    if not ok then
        log.error("[FreeSmithyCrafts] " .. tostring(err))
    end
end

function FreeTree.install()
    if hooked then
        return
    end
    hooked = true
    re.on_application_entry("LockScene", tick)
    log.info("[FreeSmithyCrafts] loaded")
end

FreeTree.install()
return FreeTree
