-- MH Rise QOL trainer on RefShell.
-- Cheats stay off unless the lobby is solo (no other human hunters).
-- Gameplay (bars, smithy, zenny/pts) stays on in any session.
-- Do not call PlayerData.get__vital / set__vital / setVital / resetVital.
-- God Mode: read _vitalMax, write _vitalKeep and _r_Vital (ints). Never write max.

local RefShell = _G.RefShell
if not RefShell then
    local ok, mod = pcall(require, "refshell")
    if ok then
        RefShell = mod
    end
end

if not RefShell then
    log.error("[mhrise] refshell missing — run npm run bundle (inlines ../../REFrameworkRefShell)")
    return
end

local HealthBars = _G.MHHealthBars
if not HealthBars then
    local ok, mod = pcall(require, "healthbars")
    if ok then
        HealthBars = mod
    end
end

local FreeTree = _G.MHFreeTree
if not FreeTree then
    local ok, mod = pcall(require, "freetree")
    if ok then
        FreeTree = mod
    end
end

local COL_OK = 0xFF6EE66E
local COL_WAIT = 0xFF66C8E6
local COL_BAD = 0xFF6666FF

local DIST_OPTIONS = {
    { 25,  "25m" },
    { 40,  "40m" },
    { 55,  "55m" },
    { 80,  "80m" },
    { 120, "120m" },
    { 200, "200m" },
    { 0,   "No limit" },
}

-- Labels are 1x/2x/3x. Real sizes stay in the 1.5–2.5 band so 3x is the max.
local SCALE_OPTIONS = {
    { 1.5, "1x" },
    { 2.0, "2x" },
    { 2.5, "3x" },
}

local DAMAGE_OPTIONS = {
    { 1.0,  "1x" },
    { 1.5,  "1.5x" },
    { 2.0,  "2x" },
    { 3.0,  "3x" },
    { 5.0,  "5x" },
    { 10.0, "10x" },
    { 99.0, "99x" },
    { 200.0, "200x" },
}

local SPEED_OPTIONS = {
    { 1.0,  "1x" },
    { 1.5,  "1.5x" },
    { 2.0,  "2x" },
    { 3.0,  "3x" },
    { 5.0,  "5x" },
    { 10.0, "10x" },
}

local features = {
    god_mode = false,
    always_reserve = false,
    inf_items = false,
    inf_wire = false,
    inf_stamina = false,
    always_sharp = false,
    more_damage = false,
    more_damage_mult = 2.0,
    move_fast = false,
    move_fast_mult = 2.0,
    bow_range = false,
    free_tree = false, -- persist key for Free Smithy Crafts (freetree.lua)
    unlock_armor = false, -- persist key for Unlock All Armor (freetree.lua)
    health_bars = true,
    health_bars_dist = 0,
    health_bars_hp_text = true,
    health_bars_show_dist = true,
    health_bars_scale = 1.5,
    health_bars_zako = false,
}

local menu

-- QuestManager.Status. Ready/Reset/Return is the load/unload window.
local QSTATUS = {
    None = 0,
    Ready = 1,
    Play = 2,
    Success = 3,
    Failed = 4,
    Reset = 5,
    SuccessSub = 6,
    Return = 7,
}

-- Wait this many frames after the hunter is playable before any writes.
-- DeviceContext is still coming up on Play and on Return-to-town.
local SAFE_FRAMES = 60

-- Quest end / fade / remount. None (0) and Play (2) are the only quiet states.
local QSTATUS_BUSY = {
    [1] = true,
    [3] = true,
    [4] = true,
    [5] = true,
    [6] = true,
    [7] = true,
}

-- Green HoT ticks per frame when God Mode is on and Play. Load AVs.
local HEAL_TICKS = 8
local VITALIZER_HOLD = 60.0

-- PlayerUserDataBowArrow._MaxRange is 25m. Stretch to horizon and keep
-- the crit / gravity windows so far shots are not 0.2x after 15m.
local BOW_RANGE = 120.0
local BOW_RANGE_FIELDS = {
    "_MaxRange",
    "_CriticalEndRange",
    "_UpperCriticalEndRange",
    "_GravityEffectiveRange",
}

local runtime = {
    last_log = "(none)",
    hooked = false,
    atk = nil,
    atk_base = nil,
    atk_written = nil,
    elem = nil,
    elem_base = nil,
    elem_written = nil,
    elem2_base = nil,
    elem2_written = nil,
    playable = false,
    safe_streak = 0,
    qstatus = nil,
    last_addr = nil,
    quest_play = false,
    master_addr = nil,
    via = "—",
    hp = nil,
    max_hp = nil,
    r_vital = nil,
    green = nil,
    vitalizer = nil,
    stamina = nil,
    max_stamina = nil,
    stamina_cap = nil,
    sharp = nil,
    sharp_max = nil,
    sharp_lv = nil,
    zenny = nil,
    zenny_max = nil,
    pts = nil,
    pts_max = nil,
    wire_extra = nil,
    wire_recast = nil,
    wire_ready = nil,
    cheats_enabled = false,
    give = {
        items = nil,
        selected = 0,
        pick = { open = false, filter = "" },
    },
    party = {
        enabled = false,
        label = "Disabled",
        detail = "Checking lobby…",
        humans = 0,
    },
    wire_pin = nil,
    bow_range_saved = nil,
    speed_was_on = false,
}

-- World extras live on ItemPouch._WireJumpInsectInventoryList.
-- The two built-in charges always recast via HunterWireGauge, not ItemInventoryData.sub.

local SHARP_LV = {
    [0] = "Red",
    [1] = "Orange",
    [2] = "Yellow",
    [3] = "Green",
    [4] = "Blue",
    [5] = "White",
    [6] = "Purple",
}

local function log_action(text)
    runtime.last_log = text
    local L = RefShell and RefShell.Log
    if L and L.info then
        L.info("mhrise", text)
        return
    end
    log.info("[mhrise] " .. text)
end

local function give_notice(text, kind)
    log_action(text)
    if menu and menu.toast then
        local ms = 2400
        if kind == "danger" or kind == "warning" then
            ms = 2000
        end
        menu:toast(text, kind or "success", ms)
    end
end

local function is_managed(obj)
    return obj ~= nil and type(obj) == "userdata"
end

local function is_a(obj, type_full)
    if not is_managed(obj) or type(type_full) ~= "string" then
        return false
    end
    local ok, yes = pcall(function()
        local td = obj:get_type_definition()
        return td ~= nil and td:is_a(type_full) == true
    end)
    return ok and yes
end

local function type_name(obj)
    local name = nil
    pcall(function()
        name = obj:get_type_definition():get_name()
    end)
    return name
end

local function obj_addr(obj)
    if not is_managed(obj) then
        return nil
    end
    local ok, addr = pcall(function()
        return obj:get_address()
    end)
    if ok and type(addr) == "number" and addr ~= 0 then
        return addr
    end
    return nil
end

local function try_field(obj, name)
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

local function try_set_field(obj, name, value)
    if not is_managed(obj) or type(name) ~= "string" or value == nil then
        return false
    end
    local ok = pcall(function()
        obj:set_field(name, value)
    end)
    return ok == true
end

local function as_number(value)
    if type(value) == "number" then
        return value
    end
    return nil
end

local method_cache = {}

local function bind_sig(type_name, signature)
    if type(type_name) ~= "string" or type(signature) ~= "string" then
        return nil
    end
    local key = type_name .. "\0" .. signature
    local cached = method_cache[key]
    if cached ~= nil then
        if cached == false then
            return nil
        end
        return cached
    end
    local method = nil
    pcall(function()
        local td = sdk.find_type_definition(type_name)
        method = td and td:get_method(signature)
    end)
    method_cache[key] = method or false
    return method
end

local function invoke_method(method, obj, ...)
    if not method or not is_managed(obj) then
        return nil, false
    end
    local n = select("#", ...)
    local a, b, c, d = ...
    local ok, result = pcall(function()
        if n >= 4 then
            return method:call(obj, a, b, c, d)
        end
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
        return result, true
    end
    return nil, false
end

local function call_decl(type_name, obj, signature, ...)
    return invoke_method(bind_sig(type_name, signature), obj, ...)
end

-- Resolve the exact TDB signature, then invoke. Bare obj:call(name) can
-- pick an overload with the wrong arity and AV (pcall does not catch that).
local function call_sig(obj, signature, ...)
    if not is_managed(obj) or type(signature) ~= "string" then
        return nil, false
    end
    local method = nil
    pcall(function()
        local td = obj:get_type_definition()
        method = td and td:get_method(signature)
    end)
    if method then
        return invoke_method(method, obj, ...)
    end
    for _, type_name in ipairs({
        "snow.player.PlayerQuestBase",
        "snow.player.PlayerLobbyBase",
        "snow.player.PlayerBase",
        "snow.player.PlayerManager",
    }) do
        method = bind_sig(type_name, signature)
        if method then
            return invoke_method(method, obj, ...)
        end
    end
    return nil, false
end

local function max_of(...)
    local best = nil
    for i = 1, select("#", ...) do
        local value = select(i, ...)
        if type(value) == "number" and value > 0 and (best == nil or value > best) then
            best = value
        end
    end
    return best
end

local function array_item(arr, index)
    if not is_managed(arr) then
        return nil
    end
    local item
    local ok = pcall(function()
        item = arr:get_element(index)
    end)
    if ok and is_managed(item) then
        return item
    end
    ok = pcall(function()
        item = arr[index]
    end)
    if ok and is_managed(item) then
        return item
    end
    return nil
end

local function player_manager()
    local pm
    pcall(function()
        pm = sdk.get_managed_singleton("snow.player.PlayerManager")
    end)
    if is_managed(pm) then
        return pm
    end
    return nil
end

local function data_manager()
    local dm
    pcall(function()
        dm = sdk.get_managed_singleton("snow.data.DataManager")
    end)
    if is_managed(dm) then
        return dm
    end
    return nil
end

local function hand_money()
    local dm = data_manager()
    local money = call_decl("snow.data.DataManager", dm, "get_HandMoney()")
    if is_a(money, "snow.data.HandMoney") then
        return money
    end
    money = try_field(dm, "_HandMoney")
    if is_a(money, "snow.data.HandMoney") then
        return money
    end
    return nil
end

local function money_cap(money)
    return as_number(try_field(money, "MaxValue")) or 99999999
end

local function village_point()
    local dm = data_manager()
    local pts = call_decl("snow.data.DataManager", dm, "get_VillagePointData()")
    if is_a(pts, "snow.data.VillagePoint") then
        return pts
    end
    pts = try_field(dm, "<VillagePointData>k__BackingField")
    if is_a(pts, "snow.data.VillagePoint") then
        return pts
    end
    pts = try_field(dm, "_VillagePointData")
    if is_a(pts, "snow.data.VillagePoint") then
        return pts
    end
    return nil
end

local function pts_cap(pts)
    return as_number(try_field(pts, "MaxValue")) or 99999999
end

local function call_static(type_name, signature, ...)
    local method = bind_sig(type_name, signature)
    if not method then
        return nil, false
    end
    local n = select("#", ...)
    local a = ...
    local ok, result = pcall(function()
        if n >= 1 then
            return method:call(nil, a)
        end
        return method:call(nil)
    end)
    if ok then
        return result, true
    end
    return nil, false
end

-- Same as Wilds: via.Application.set_GlobalSpeed. Dog ride is a combat
-- state machine — this is the speed fix that actually lands.
local function apply_play_speed(want)
    local scale = 1.0
    if want then
        scale = tonumber(features.move_fast_mult) or 2.0
        if scale < 0.25 then
            scale = 0.25
        elseif scale > 10 then
            scale = 10
        end
        runtime.speed_was_on = true
    elseif runtime.speed_was_on then
        runtime.speed_was_on = false
        scale = 1.0
    else
        return
    end
    call_static("via.Application", "set_GlobalSpeed(System.Single)", scale)
end

local function fill_pts()
    local pts = village_point()
    if not pts then
        log_action("pts: no VillagePoint")
        return false
    end
    local cap = pts_cap(pts)
    if try_set_field(pts, "_Point", cap) then
        runtime.pts = cap
        runtime.pts_max = cap
        log_action(string.format("pts max %d", cap))
        return true
    end
    log_action("pts max failed")
    return false
end

local function add_pts(amount)
    local pts = village_point()
    if not pts then
        log_action("pts: no VillagePoint")
        return false
    end
    local _, ok = call_static("snow.data.VillagePoint", "addPoint(System.UInt32)", amount)
    local now = as_number(try_field(pts, "_Point"))
    if not ok then
        local cur = now or 0
        local cap = pts_cap(pts)
        now = cur + amount
        if now > cap then
            now = cap
        end
        ok = try_set_field(pts, "_Point", now)
    end
    if ok then
        runtime.pts = now
        runtime.pts_max = pts_cap(pts)
        log_action(string.format("pts +%d -> %s", amount, now and tostring(now) or "?"))
        return true
    end
    log_action("pts add failed")
    return false
end

local function fill_zenny()
    local money = hand_money()
    if not money then
        log_action("zenny: no HandMoney")
        return false
    end
    local cap = money_cap(money)
    if try_set_field(money, "_Value", cap) then
        runtime.zenny = cap
        runtime.zenny_max = cap
        log_action(string.format("zenny max %d", cap))
        return true
    end
    log_action("zenny max failed")
    return false
end

local function add_zenny(amount)
    local money = hand_money()
    if not money then
        log_action("zenny: no HandMoney")
        return false
    end
    local _, ok = call_decl("snow.data.HandMoney", money, "addMoney(System.Int32)", amount)
    local now = as_number(try_field(money, "_Value"))
    if not ok then
        local cur = now or 0
        local cap = money_cap(money)
        now = cur + amount
        if now > cap then
            now = cap
        end
        ok = try_set_field(money, "_Value", now)
    end
    if ok then
        runtime.zenny = now
        runtime.zenny_max = money_cap(money)
        log_action(string.format("zenny +%d -> %s", amount, now and tostring(now) or "?"))
        return true
    end
    log_action("zenny add failed")
    return false
end

local function item_pouch()
    local pouch = call_static("snow.data.DataManager", "get_ItemPouch()")
    if is_a(pouch, "snow.data.ItemPouch") then
        return pouch
    end
    return nil
end

local function array_len(arr)
    if not is_managed(arr) then
        return 0
    end
    local n
    pcall(function()
        n = arr:get_size()
    end)
    if type(n) == "number" and n >= 0 then
        return n
    end
    return as_number(try_field(arr, "_size")) or 0
end

local function list_len(list)
    if not is_managed(list) then
        return 0
    end
    local n = as_number((call_sig(list, "get_Count()")))
    if type(n) == "number" then
        return n
    end
    n = as_number(try_field(list, "_size"))
    if type(n) == "number" then
        return n
    end
    return array_len(list)
end

local function list_item(list, index)
    if not is_managed(list) then
        return nil
    end
    local item = select(1, call_sig(list, "get_Item(System.Int32)", index))
    if is_managed(item) then
        return item
    end
    return array_item(try_field(list, "_items"), index)
end

local ARMOR_NONE = 201326592 -- DataDef.PlArmorId.A_None
local ARMOR_PARTS = {
    { 0, "Head" },
    { 1, "Chest" },
    { 2, "Arms" },
    { 3, "Waist" },
    { 4, "Legs" },
}

local function as_id(value)
    local n = as_number(value)
    if n then
        return n
    end
    if not is_managed(value) then
        return nil
    end
    n = as_number(try_field(value, "value__"))
    if n then
        return n
    end
    local ok, boxed = pcall(function()
        return sdk.to_int64(value)
    end)
    if ok then
        return as_number(boxed)
    end
    return nil
end

local function display_ok(name)
    if type(name) ~= "string" then
        return false
    end
    local trimmed = name:gsub("^%s+", ""):gsub("%s+$", "")
    if trimmed == "" or trimmed == "None" then
        return false
    end
    if trimmed:find("#Rejected#", 1, true) then
        return false
    end
    return true
end

local function armor_id_module()
    local cidm
    pcall(function()
        cidm = sdk.get_managed_singleton("snow.data.ContentsIdDataManager")
    end)
    local mod
    if is_managed(cidm) then
        mod = select(1, call_decl(
            "snow.data.ContentsIdDataManager",
            cidm,
            "get_PlArmorIdDataModule()"
        ))
    end
    if not is_managed(mod) then
        mod = select(1, call_static(
            "snow.data.ContentsIdDataManager",
            "get_PlArmorIdDataModule()"
        ))
    end
    return mod
end

local function armor_series_list()
    local mod = armor_id_module()
    if not is_managed(mod) then
        return nil
    end
    local list = select(1, call_decl(
        "snow.data.contentsIdDataManager.PlArmorIdDataModule",
        mod,
        "get_ArmorSeriesDataList()"
    ))
    if not is_managed(list) then
        list = try_field(mod, "<ArmorSeriesDataList>k__BackingField")
    end
    if is_managed(list) then
        return list
    end
    return nil
end

local function equip_box()
    local box = select(1, call_static("snow.data.DataManager", "getEquipBox()"))
    if is_a(box, "snow.data.EquipBox") then
        return box
    end
    local dm = data_manager()
    if is_managed(dm) then
        box = select(1, call_decl("snow.data.DataManager", dm, "getEquipBox()"))
        if is_a(box, "snow.data.EquipBox") then
            return box
        end
    end
    return nil
end

local function armor_piece_id(series, part)
    local id = as_id(select(1, call_decl(
        "snow.data.ArmorSeriesData",
        series,
        "getArmorId(snow.data.ArmorData.PartsTypes)",
        part
    )))
    if id and id ~= 0 and id ~= ARMOR_NONE then
        return id
    end
    local data = select(1, call_decl(
        "snow.data.ArmorSeriesData",
        series,
        "getArmorData(snow.data.ArmorData.PartsTypes, System.Boolean)",
        part,
        false
    ))
    if not is_managed(data) then
        data = select(1, call_decl(
            "snow.data.ArmorSeriesData",
            series,
            "getArmorData(snow.data.ArmorData.PartsTypes)",
            part
        ))
    end
    if not is_managed(data) then
        return nil
    end
    id = as_id(try_field(data, "<RefId>k__BackingField"))
    if not id then
        id = as_id(select(1, call_decl("snow.data.ArmorData", data, "get_RefId()")))
    end
    if id and id ~= 0 and id ~= ARMOR_NONE then
        return id, data
    end
    return nil
end

local function armor_piece_name(series, part, data)
    if not is_managed(data) then
        data = select(1, call_decl(
            "snow.data.ArmorSeriesData",
            series,
            "getArmorData(snow.data.ArmorData.PartsTypes, System.Boolean)",
            part,
            false
        ))
    end
    if not is_managed(data) then
        return nil
    end
    local name = select(1, call_decl("snow.data.ArmorData", data, "getName()"))
    if display_ok(name) then
        return name, data
    end
    return nil, data
end

local function build_armor_catalog()
    local list = armor_series_list()
    if not is_managed(list) then
        return nil
    end
    local n = array_len(list)
    if n <= 0 then
        return nil
    end
    local items = {}
    for i = 0, n - 1 do
        local series = array_item(list, i)
        if is_managed(series) then
            local series_name = select(1, call_decl(
                "snow.data.ArmorSeriesData",
                series,
                "get_SeriesName()"
            ))
            if display_ok(series_name) then
                local gender_ok = select(1, call_decl(
                    "snow.data.ArmorSeriesData",
                    series,
                    "enableGender()"
                ))
                if gender_ok ~= false then
                    for _, part in ipairs(ARMOR_PARTS) do
                        local id, data = armor_piece_id(series, part[1])
                        if id then
                            local piece_name = armor_piece_name(series, part[1], data)
                            if piece_name then
                                items[#items + 1] = {
                                    kind = "armor",
                                    id = id,
                                    name = piece_name,
                                    series = series_name,
                                    series_index = i,
                                    part = part[1],
                                    part_name = part[2],
                                    label = string.format("%s — %s (%s)", series_name, piece_name, part[2]),
                                }
                            end
                        end
                    end
                end
            end
        end
    end
    if #items == 0 then
        return nil
    end
    return items
end

local function give_catalog()
    local give = runtime.give
    if give.items then
        return give.items
    end
    local items = build_armor_catalog()
    give.items = items
    give.selected = 0
    return items
end

local function grant_armor(entry)
    if type(entry) ~= "table" or type(entry.id) ~= "number" then
        return false, "no armor id"
    end
    local box = equip_box()
    if not is_a(box, "snow.data.EquipBox") then
        return false, "no EquipBox"
    end
    local added = select(1, call_decl(
        "snow.data.EquipBox",
        box,
        "tryAddGameItem(snow.data.DataDef.PlArmorId)",
        entry.id
    ))
    if not is_managed(added) then
        added = select(1, call_decl(
            "snow.data.EquipBox",
            box,
            "tryAddGameItem(snow.data.DataDef.PlArmorId, snow.data.EquipmentInventoryData)",
            entry.id,
            nil
        ))
    end
    if is_managed(added) then
        return true, nil
    end
    return false, "box full or rejected"
end

local function grant_entry(entry)
    if type(entry) ~= "table" then
        return false, "nothing selected"
    end
    return grant_armor(entry)
end

local function give_selected()
    if not runtime.cheats_enabled then
        give_notice("Give is solo only", "warning")
        return
    end
    local items = give_catalog()
    local entry = items and items[runtime.give.selected]
    local ok, err = grant_entry(entry)
    if ok then
        give_notice("Added to Item Box: " .. tostring(entry.name), "success")
        return
    end
    give_notice("Give failed — " .. tostring(err or "?"), "danger")
end

local function give_selected_set()
    if not runtime.cheats_enabled then
        give_notice("Give is solo only", "warning")
        return
    end
    local items = give_catalog()
    local entry = items and items[runtime.give.selected]
    if type(entry) ~= "table" then
        give_notice("Give failed — nothing selected", "warning")
        return
    end
    local ok_n = 0
    local fail = nil
    for i = 1, #items do
        local row = items[i]
        if row.series_index == entry.series_index then
            local ok, err = grant_entry(row)
            if ok then
                ok_n = ok_n + 1
            else
                fail = err
            end
        end
    end
    if ok_n > 0 then
        give_notice(string.format("Added %d %s pieces to Item Box", ok_n, tostring(entry.series)), "success")
        return
    end
    give_notice("Give set failed — " .. tostring(fail or "?"), "danger")
end

local function slot_count(slot)
    local n = as_number((call_decl("snow.data.ItemInventoryData", slot, "get_Count()")))
    if type(n) == "number" then
        return n
    end
    n = as_number((call_sig(slot, "get_Count()")))
    if type(n) == "number" then
        return n
    end
    local ic = try_field(slot, "_ItemCount")
    return as_number(try_field(ic, "_Num")) or as_number(try_field(ic, "Count"))
end

local function set_slot_count(slot, count)
    local _, ok = call_decl("snow.data.ItemInventoryData", slot, "set_Count(System.UInt32)", count)
    if ok then
        return true
    end
    _, ok = call_sig(slot, "set_Count(System.UInt32)", count)
    if ok then
        return true
    end
    local ic = try_field(slot, "_ItemCount")
    return try_set_field(ic, "_Num", count) or try_set_field(ic, "Count", count)
end

local function wire_extra_count()
    local n = as_number((call_static("snow.data.ItemPouch", "getWireJumpInsectItemNum()")))
    if type(n) == "number" then
        return n
    end
    local list = try_field(item_pouch(), "_WireJumpInsectInventoryList")
    local total = 0
    for i = 0, list_len(list) - 1 do
        total = total + (slot_count(list_item(list, i)) or 0)
    end
    return total
end

local function read_wirebugs(hunter)
    local gauges = try_field(hunter, "_HunterWireGauge")
    local recast = 0
    local ready = 0
    for i = 0, array_len(gauges) - 1 do
        local gauge = array_item(gauges, i)
        if is_managed(gauge) then
            ready = ready + 1
            local t = as_number(try_field(gauge, "_RecastTimer")) or 0
            if t > recast then
                recast = t
            end
        end
    end
    runtime.wire_ready = ready > 0 and ready or nil
    runtime.wire_recast = ready > 0 and recast or nil
    runtime.wire_extra = wire_extra_count()
end

local function hold_wirebugs(hunter)
    if not is_managed(hunter) then
        return
    end
    local gauges = try_field(hunter, "_HunterWireGauge")
    local len = array_len(gauges)
    if len < 1 then
        len = 3
    end
    for i = 0, len - 1 do
        local gauge = array_item(gauges, i)
        if is_managed(gauge) then
            try_set_field(gauge, "_RecastTimer", 0.0)
            try_set_field(gauge, "_RecoverWaitTimer", 0.0)
        end
    end
    try_set_field(hunter, "_HunterWireRecastDelayFlag", false)

    local list = try_field(item_pouch(), "_WireJumpInsectInventoryList")
    local extras = 0
    for i = 0, list_len(list) - 1 do
        local slot = list_item(list, i)
        local count = slot_count(slot)
        if type(count) == "number" and count > 0 then
            if type(runtime.wire_pin) ~= "number" or count > runtime.wire_pin then
                runtime.wire_pin = count
            end
            if count < runtime.wire_pin then
                set_slot_count(slot, runtime.wire_pin)
                extras = extras + runtime.wire_pin
            else
                extras = extras + count
            end
        end
    end
    if extras > 0 then
        runtime.wire_extra = extras
    end
end

local function master_hunter()
    local pm = player_manager()
    local hunter = call_sig(pm, "findMasterPlayer()")
    if is_managed(hunter) then
        return hunter
    end
    return nil
end

local function master_data()
    local pm = player_manager()
    local arr = call_sig(pm, "get_PlayerData()")
    local data = array_item(arr, 0)
    if is_a(data, "snow.player.PlayerData") then
        return data
    end
    return nil
end

local function hunter_ready(hunter)
    return is_a(hunter, "snow.player.PlayerLobbyBase")
        or is_a(hunter, "snow.player.PlayerQuestBase")
end

local function quest_manager()
    local qm
    pcall(function()
        qm = sdk.get_managed_singleton("snow.QuestManager")
    end)
    if is_managed(qm) then
        return qm
    end
    return nil
end

local function lobby_manager()
    local lm
    pcall(function()
        lm = sdk.get_managed_singleton("snow.LobbyManager")
    end)
    if is_managed(lm) then
        return lm
    end
    return nil
end

local function hunter_info_name(info)
    if not is_managed(info) then
        return nil
    end
    local name = try_field(info, "_name")
    if type(name) == "string" and name ~= "" then
        return name
    end
    local got = call_decl("snow.LobbyManager.HunterInfo", info, "get_Name()")
    if type(got) == "string" and got ~= "" then
        return got
    end
    if is_managed(name) then
        local text
        pcall(function()
            text = name:to_string()
        end)
        if type(text) == "string" and text ~= "" and not text:find("userdata") then
            return text
        end
    end
    return nil
end

local function count_hunter_infos(container)
    if not is_managed(container) then
        return nil
    end
    local n = array_len(container)
    if n <= 0 then
        n = as_number((call_sig(container, "get_Count()"))) or 0
    end
    if n <= 0 then
        return 0
    end
    if n > 8 then
        n = 8
    end
    local humans = 0
    for i = 0, n - 1 do
        local info = array_item(container, i)
        if not info then
            info = select(1, call_sig(container, "get_Item(System.Int32)", i))
        end
        if hunter_info_name(info) then
            humans = humans + 1
        end
    end
    return humans
end

-- Fail closed. Health bars ignore this; only writes / skip-hooks check it.
local function party_status()
    if not master_hunter() then
        return {
            enabled = false,
            label = "Disabled",
            detail = "Not in the field",
            humans = 0,
        }
    end

    local lm = lobby_manager()
    if not lm then
        return {
            enabled = false,
            label = "Disabled",
            detail = "Waiting for LobbyManager",
            humans = 0,
        }
    end

    local enumerated = false
    local humans = 0

    local function consider(n)
        if type(n) ~= "number" then
            return
        end
        enumerated = true
        if n > humans then
            humans = n
        end
    end

    consider(count_hunter_infos(
        select(1, call_decl("snow.LobbyManager", lm, "getLobbyHunterInfoList()"))
    ))

    -- Quest/area counts are fallback only. getQuestPlayerCount can sit at
    -- party capacity in some menus — do not let that override a real list.
    if not enumerated then
        local quest_n = as_number((call_decl("snow.LobbyManager", lm, "getQuestPlayerCount()")))
        if quest_n and quest_n > 0 then
            consider(quest_n)
        end
        consider(count_hunter_infos(
            select(1, call_decl("snow.LobbyManager", lm, "getSameAreaHunterInfoList()"))
        ))
        local slot_n = 0
        for i = 0, 3 do
            local info = select(1, call_decl(
                "snow.LobbyManager",
                lm,
                "getLobbyHunterInfo(snow.player.PlayerIndex)",
                i
            ))
            if hunter_info_name(info) then
                slot_n = slot_n + 1
            end
        end
        if slot_n > 0 then
            consider(slot_n)
        end
    end

    if not enumerated then
        return {
            enabled = false,
            label = "Disabled",
            detail = "Could not read lobby — fail closed",
            humans = 0,
        }
    end

    if humans <= 0 then
        humans = 1
    end

    if humans <= 1 then
        return {
            enabled = true,
            label = "Enabled",
            detail = "Solo — no other hunters in lobby",
            humans = humans,
        }
    end

    return {
        enabled = false,
        label = "Disabled",
        detail = string.format("Lobby has %d hunters", humans),
        humans = humans,
    }
end

local function enum_int(value)
    local n = as_number(value)
    if n then
        return n
    end
    if not is_managed(value) then
        return nil
    end
    local got
    pcall(function()
        if value.get_value then
            got = value:get_value()
        end
        if got == nil then
            got = value:get_field("value__")
        end
    end)
    return as_number(got)
end

-- Field only. Do not call isPlayQuest() during load — same DeviceContext window.
local function quest_status()
    return enum_int(try_field(quest_manager(), "_QuestStatus"))
end

-- True while the quest is mounting, ending, fading, or tearing down.
local function scene_busy(hunter)
    local status = quest_status()
    local in_quest = is_a(hunter, "snow.player.PlayerQuestBase")
    if status ~= nil and QSTATUS_BUSY[status] then
        return true
    end
    if in_quest and status ~= QSTATUS.Play then
        return true
    end
    if status == QSTATUS.Play and not in_quest then
        return true
    end
    return false
end

local function update_playable(hunter, data)
    local status = quest_status()
    local addr = obj_addr(hunter)
    local in_quest = is_a(hunter, "snow.player.PlayerQuestBase")
    if status ~= runtime.qstatus or addr ~= runtime.last_addr then
        runtime.safe_streak = 0
        runtime.stamina_cap = nil
        runtime.atk_base = nil
        runtime.atk_written = nil
        runtime.elem_base = nil
        runtime.elem_written = nil
        runtime.elem2_base = nil
        runtime.elem2_written = nil
    end
    runtime.qstatus = status
    runtime.last_addr = addr
    runtime.quest_play = in_quest and status == QSTATUS.Play

    local ready = hunter_ready(hunter)
        and is_a(data, "snow.player.PlayerData")
        and not scene_busy(hunter)
    if ready then
        runtime.safe_streak = (runtime.safe_streak or 0) + 1
    else
        runtime.safe_streak = 0
    end
    runtime.playable = runtime.safe_streak >= SAFE_FRAMES
    if runtime.playable then
        runtime.master_addr = addr
    else
        runtime.master_addr = nil
    end
    return runtime.playable
end

local function read_vital(data)
    return as_number(try_field(data, "_vitalKeep")),
        as_number(try_field(data, "_vitalMax")),
        as_number(try_field(data, "_r_Vital"))
end

-- Always Reserve Health: pin red only. Do not write _vitalMax (resizes the bar).
-- Do not write _VitalF or call calcHealVital — green is still unsolved.
local function hold_reserve(data)
    local max_hp = as_number(try_field(data, "_vitalMax"))
    if not max_hp or max_hp <= 0 then
        return false
    end
    local keep_ok = try_set_field(data, "_vitalKeep", max_hp)
    local red_ok = try_set_field(data, "_r_Vital", max_hp)
    return keep_ok or red_ok
end

-- God Mode (green experiment). Does not pin red — that is Always Reserve.
-- Load-gated by the caller. calcHealVital / _VitalF writes AVs during load.
local DRAIN_TIMERS = {
    "_PoisonDamageTimer",
    "_FireDamageTimer",
    "_BleedingMoveDamageInterval",
    "_SymbiosisSkillDamageTimer",
    "_EquipSkill225SlipDamageTimer",
    "_WaterSlipDamageTimer",
    "_EnemySlipDamageTimer_Onibi",
    "_DamageEnemyFireSlipTimer",
    "_DamageMagmaGroundSlipTimer",
    "_BubbleDamageTimer",
    "_MysteryDebuffDamageTimer",
    "_VirusOnsetTerritoryDamageTimer",
}

local DRAIN_FLAGS = {
    "_IsDuringSlipDamage",
    "_IsEnemySlipDamage_Onibi",
    "_IsEnemySlipDamage_Virus",
    "_IsWaterSlipDamage",
}

local function suppress_drain(hunter, data)
    if is_managed(data) then
        try_set_field(data, "_bleedingDamageStockVital", 0)
    end
    if not is_managed(hunter) then
        return
    end
    for _, name in ipairs(DRAIN_TIMERS) do
        try_set_field(hunter, name, 0)
    end
    for _, name in ipairs(DRAIN_FLAGS) do
        try_set_field(hunter, name, false)
    end
end

local function hold_green(hunter, data)
    -- Quest Play only. Town / Return still reports a hunter and AVs.
    if not runtime.quest_play or not runtime.playable then
        return false
    end
    suppress_drain(hunter, data)
    local max_hp = as_number(try_field(data, "_vitalMax"))
    if not max_hp or max_hp <= 0 then
        return false
    end
    try_set_field(data, "_VitalizerTimer", VITALIZER_HOLD)
    if not is_a(hunter, "snow.player.PlayerQuestBase") then
        return false
    end
    local green_ok = try_set_field(hunter, "_VitalF", max_hp)
    local green = as_number(try_field(hunter, "_VitalF")) or 0
    if green < max_hp - 0.25 then
        for _ = 1, HEAL_TICKS do
            call_decl("snow.player.PlayerQuestBase", hunter, "calcHealVital()")
        end
        try_set_field(data, "_VitalizerTimer", VITALIZER_HOLD)
        green_ok = try_set_field(hunter, "_VitalF", max_hp) or green_ok
    end
    return green_ok
end

local function read_stamina(data)
    return as_number(try_field(data, "_stamina")), as_number(try_field(data, "_staminaMax"))
end

-- Quest fatigue shrinks _staminaMax (HUD tank + Status number). Pin to the
-- biggest official cap, not the already-drained field.
local function stamina_target(hunter, data)
    local item, tent, init, lobby
    -- Quest getters only while Play. Lobby getters only on a hub hunter.
    -- PlayerQuestBase is_a LobbyBase, so do not run both.
    if runtime.quest_play and runtime.playable then
        item = as_number(call_decl("snow.player.PlayerQuestBase", hunter, "getItemStaminaMax()"))
        tent = as_number(call_decl("snow.player.PlayerQuestBase", hunter, "getTentExitStaminaMax()"))
        init = as_number(call_decl("snow.player.PlayerQuestBase", hunter, "getInitStaminaMax()"))
    elseif runtime.playable
        and is_a(hunter, "snow.player.PlayerLobbyBase")
        and not is_a(hunter, "snow.player.PlayerQuestBase")
    then
        init = as_number(call_decl("snow.player.PlayerLobbyBase", hunter, "getInitStaminaMax()"))
        lobby = as_number(call_decl("snow.player.PlayerLobbyBase", hunter, "getStaminaMax()"))
    end
    local field = as_number(try_field(data, "_staminaMax"))
    local best = max_of(item, tent, init, lobby, field, runtime.stamina_cap)
    if best then
        runtime.stamina_cap = best
    end
    return best
end

local function refill_stamina(hunter, data)
    if not is_managed(data) then
        return false
    end
    local target = stamina_target(hunter, data)
    if not target or target <= 0 then
        return false
    end

    -- Field pin first. Official stamina methods stay behind playable.
    try_set_field(data, "_staminaMaxDownIntervalTimer", 999999.0)
    local max_ok = try_set_field(data, "_staminaMax", target)
    local cur_ok = try_set_field(data, "_stamina", target)

    -- Hub: field pin only. resetStamina AVs on town remount.
    if not runtime.quest_play then
        return max_ok or cur_ok
    end
    if is_a(hunter, "snow.player.PlayerQuestBase") then
        local cur_max = as_number(try_field(data, "_staminaMax")) or 0
        local need_max = target - cur_max
        if need_max > 1 then
            call_decl(
                "snow.player.PlayerQuestBase",
                hunter,
                "calcStaminaMax(System.Single, System.Boolean)",
                need_max,
                true
            )
        end
        call_decl("snow.player.PlayerQuestBase", hunter, "setTentExitStamina()")
        local after = as_number(try_field(data, "_stamina")) or 0
        if after < target - 1 then
            call_decl(
                "snow.player.PlayerQuestBase",
                hunter,
                "calcStamina(System.Single, System.Boolean, System.Single)",
                target - after,
                true,
                1.0
            )
        end
        try_set_field(data, "_staminaMax", target)
        try_set_field(data, "_stamina", target)
    end

    return max_ok or cur_ok
end

local function read_sharpness(hunter)
    if not is_a(hunter, "snow.player.PlayerBase") then
        return nil, nil, nil
    end
    local cur = as_number(call_sig(hunter, "get_SharpnessGauge()"))
    local max_g = as_number(call_sig(hunter, "get_SharpnessGaugeMax()"))
    local lv = as_number(call_sig(hunter, "get_SharpnessLv()"))
    return cur, max_g, lv
end

-- Official PlayerBase setter. Do not write set_SharpnessGaugeMax (resizes the bar).
local function hold_sharpness(hunter)
    if not is_a(hunter, "snow.player.PlayerBase") then
        return false
    end
    local max_g = as_number(call_sig(hunter, "get_SharpnessGaugeMax()"))
    if not max_g or max_g <= 0 then
        return false
    end
    local _, ok = call_sig(hunter, "setSharpness(System.Int32)", max_g)
    return ok
end

local function restore_bow_range()
    local saved = runtime.bow_range_saved
    if not saved then
        return
    end
    for _, row in pairs(saved) do
        local obj = row.obj
        if is_managed(obj) and row.values then
            for field, value in pairs(row.values) do
                try_set_field(obj, field, value)
            end
        end
    end
    runtime.bow_range_saved = nil
end

local function pin_bow_arrow(arrow)
    if not is_a(arrow, "snow.player.PlayerUserDataBowArrow") then
        return false
    end
    local addr = obj_addr(arrow)
    if not addr then
        return false
    end
    if not runtime.bow_range_saved then
        runtime.bow_range_saved = {}
    end
    local row = runtime.bow_range_saved[addr]
    if not row then
        row = { obj = arrow, values = {} }
        runtime.bow_range_saved[addr] = row
    else
        row.obj = arrow
    end
    local wrote = false
    for _, field in ipairs(BOW_RANGE_FIELDS) do
        local cur = as_number(try_field(arrow, field))
        if type(cur) == "number" then
            if row.values[field] == nil then
                row.values[field] = cur
            end
            if math.abs(cur - BOW_RANGE) > 0.05 then
                try_set_field(arrow, field, BOW_RANGE)
            end
            wrote = true
        end
    end
    return wrote
end

local function hold_bow_range(hunter)
    if not is_a(hunter, "snow.player.Bow") then
        return false
    end
    local arr = try_field(hunter, "_PlayerUserDataArrow")
    if not is_managed(arr) then
        return false
    end
    local n = array_len(arr)
    if n <= 0 then
        n = as_number((call_sig(arr, "get_Count()"))) or 0
    end
    if n <= 0 then
        return pin_bow_arrow(arr)
    end
    if n > 16 then
        n = 16
    end
    local wrote = false
    for i = 0, n - 1 do
        local arrow = array_item(arr, i)
        if not arrow then
            arrow = select(1, call_sig(arr, "get_Item(System.Int32)", i))
        end
        if pin_bow_arrow(arrow) then
            wrote = true
        end
    end
    return wrote
end

local function hook_skip_master_damage(signature)
    local method = bind_sig("snow.player.PlayerQuestBase", signature)
    if not method then
        return
    end
    local skip = false
    pcall(sdk.hook, method, function(args)
        skip = false
        if not runtime.cheats_enabled or not features.god_mode or not runtime.quest_play or not runtime.playable or not runtime.master_addr then
            return
        end
        local obj
        pcall(function()
            obj = sdk.to_managed_object(args[2])
        end)
        if obj_addr(obj) == runtime.master_addr then
            skip = true
            return sdk.PreHookResult.SKIP_ORIGINAL
        end
    end, function(retval)
        if skip then
            return sdk.to_ptr(0)
        end
        return retval
    end)
end

-- More Damage: pin PlayerData._Attack after calcTotalAttack.
local function damage_scale()
    if not runtime.cheats_enabled or not features.more_damage then
        return 1.0
    end
    local n = tonumber(features.more_damage_mult)
    if not n or n <= 0 then
        return 1.0
    end
    return n
end

local function pin_scaled(data, field, base_key, written_key, raw, scale)
    if type(raw) ~= "number" then
        return nil
    end
    if scale == 1.0 then
        local base = runtime[base_key]
        local written = runtime[written_key]
        if type(base) == "number" and type(written) == "number" and math.abs(raw - written) < 0.51 then
            try_set_field(data, field, base)
        end
        runtime[base_key] = nil
        runtime[written_key] = nil
        return base or raw
    end
    local base = runtime[base_key]
    local written = runtime[written_key]
    if type(base) ~= "number" or (type(written) == "number" and math.abs(raw - written) > 0.51) then
        base = raw
        runtime[base_key] = raw
    end
    local target = base * scale
    if try_set_field(data, field, target) then
        runtime[written_key] = target
        return target
    end
    return raw
end

local function hold_attack(data)
    if not is_managed(data) then
        return
    end
    local scale = damage_scale()
    runtime.atk = pin_scaled(
        data,
        "_Attack",
        "atk_base",
        "atk_written",
        as_number(try_field(data, "_Attack")),
        scale
    )
    runtime.elem = pin_scaled(
        data,
        "_ElementAttack",
        "elem_base",
        "elem_written",
        as_number(try_field(data, "_ElementAttack")),
        scale
    )
    local elem2 = as_number(try_field(data, "_ElementAttack2nd"))
    if type(elem2) == "number" and elem2 > 0 then
        pin_scaled(data, "_ElementAttack2nd", "elem2_base", "elem2_written", elem2, scale)
    end
end

local function install_attack_hooks()
    if runtime.attack_hooks then
        return
    end
    local method = bind_sig("snow.player.PlayerBase", "calcTotalAttack()")
    if not method then
        log_action("more damage: calcTotalAttack missing")
        return
    end
    runtime.attack_hooks = true
    local pending = nil
    pcall(sdk.hook, method, function(args)
        pending = nil
        pcall(function()
            pending = sdk.to_managed_object(args[2])
        end)
    end, function(retval)
        if runtime.playable and obj_addr(pending) == runtime.master_addr then
            runtime.atk_written = nil
            runtime.elem_written = nil
            runtime.elem2_written = nil
            hold_attack(master_data())
        end
        pending = nil
        return retval
    end)
end

local function install_god_hooks()
    if runtime.god_hooks then
        return
    end
    runtime.god_hooks = true
    hook_skip_master_damage(
        "damageVital(System.Single, System.Boolean, System.Boolean, System.Boolean, System.Boolean, System.Boolean)"
    )
    hook_skip_master_damage("damageVitalSlip(System.Single)")
    hook_skip_master_damage("damageVitalDebuffFire(System.Single)")
    hook_skip_master_damage("damageVitalVirus(System.Single)")
    hook_skip_master_damage("damageVitalMysteryDebuff(System.Single)")
end

-- Field pouch (0–6, 196608) and item box (65536, smith materials).
-- Do not skip equip/deco/otomo boxes — those swaps are not item spend.
local function is_spend_inv(inv_type)
    if type(inv_type) ~= "number" then
        return false
    end
    inv_type = inv_type & 0xFFFFFFFF
    return inv_type <= 6 or inv_type == 196608 or inv_type == 65536
end

local function slot_is_spend(slot)
    if not is_managed(slot) then
        return false
    end
    local t = as_number((call_decl("snow.data.InventoryData", slot, "getInventoryType()")))
    if t == nil then
        t = as_number((call_sig(slot, "getInventoryType()")))
    end
    return is_spend_inv(t)
end

local function consume_ok()
    return runtime.cheats_enabled and features.inf_items and runtime.playable
end

-- notifyConsumeItem is a UI ping after the fact. The count drop is
-- DataManager.consumeItem / tryConsumeItem and ItemPouch.tryConsumeItem
-- (Onimusha subItem). Skip those; return the requested count so use still fires.
-- Town/smith stay infinite. Skip only playable + pouch/box slots.
local function hook_skip_consume(type_name, signature, opts)
    opts = opts or {}
    local method = bind_sig(type_name, signature)
    if not method then
        return
    end
    local skip = false
    local ret_n = 0
    pcall(sdk.hook, method, function(args)
        skip = false
        if not consume_ok() then
            return
        end
        if opts.pouch_this then
            local slot
            pcall(function()
                slot = sdk.to_managed_object(args[2])
            end)
            if not slot_is_spend(slot) then
                return
            end
        end
        if type(opts.pouch_arg) == "number" then
            local raw
            pcall(function()
                raw = sdk.to_int64(args[opts.pouch_arg])
            end)
            if not is_spend_inv(raw) then
                return
            end
        end
        skip = true
        local ret_from_arg = opts.ret_from_arg
        if type(ret_from_arg) == "number" then
            local raw
            pcall(function()
                raw = sdk.to_int64(args[ret_from_arg])
            end)
            if type(raw) == "number" then
                ret_n = raw & 0xFFFFFFFF
            else
                ret_n = 1
            end
        end
        return sdk.PreHookResult.SKIP_ORIGINAL
    end, function(retval)
        if skip and type(opts.ret_from_arg) == "number" then
            return sdk.to_ptr(ret_n)
        end
        return retval
    end)
end

local function as_i32(raw)
    if type(raw) ~= "number" then
        return nil
    end
    raw = raw & 0xFFFFFFFF
    if raw >= 0x80000000 then
        return raw - 0x100000000
    end
    return raw
end

local function hook_skip_negative_add(type_name, signature, arg_i)
    local method = bind_sig(type_name, signature)
    if not method then
        return
    end
    local skip = false
    pcall(sdk.hook, method, function(args)
        skip = false
        if not consume_ok() then
            return
        end
        local raw
        pcall(function()
            raw = sdk.to_int64(args[arg_i])
        end)
        local n = as_i32(raw)
        if n == nil or n >= 0 then
            return
        end
        if type_name == "snow.data.ItemInventoryData" then
            local slot
            pcall(function()
                slot = sdk.to_managed_object(args[2])
            end)
            if not slot_is_spend(slot) then
                return
            end
        end
        skip = true
        return sdk.PreHookResult.SKIP_ORIGINAL
    end, function(retval)
        return retval
    end)
end

local function install_item_hooks()
    if runtime.item_hooks then
        return
    end
    runtime.item_hooks = true
    hook_skip_consume(
        "snow.data.DataManager",
        "consumeItem(snow.data.ContentsIdSystem.ItemId, System.UInt32)"
    )
    hook_skip_consume(
        "snow.data.DataManager",
        "consumeItemFromPouch(snow.data.ContentsIdSystem.ItemId, System.UInt32)",
        { ret_from_arg = 3 }
    )
    hook_skip_consume(
        "snow.data.DataManager",
        "tryConsumeItem(snow.data.ContentsIdSystem.ItemId, snow.data.InventoryData.InventoryType, System.UInt32)",
        { ret_from_arg = 5, pouch_arg = 4 }
    )
    hook_skip_consume(
        "snow.data.ItemPouch",
        "tryConsumeItem(snow.data.ItemInventoryData)"
    )
    -- Actual stack drop. Use never went through DataManager.consumeItem.
    hook_skip_consume(
        "snow.data.ItemInventoryData",
        "sub(System.UInt32, System.Boolean)",
        { pouch_this = true }
    )
    hook_skip_consume(
        "snow.data.ItemInventoryData",
        "sub(System.UInt32)",
        { pouch_this = true }
    )
    hook_skip_negative_add("snow.data.ItemInventoryData", "add(System.Int32)", 3)
    hook_skip_negative_add("snow.data.ItemCount", "add(System.Int32)", 3)
end

local function refresh_status(hunter, data)
    runtime.hooked = hunter_ready(hunter)
    if runtime.hooked then
        runtime.via = type_name(hunter) or "hunter"
    else
        runtime.via = "—"
    end
    runtime.hp, runtime.max_hp, runtime.r_vital = read_vital(data)
    runtime.vitalizer = as_number(try_field(data, "_VitalizerTimer"))
    runtime.stamina, runtime.max_stamina = read_stamina(data)
    local money = hand_money()
    runtime.zenny = as_number(try_field(money, "_Value"))
    runtime.zenny_max = money and money_cap(money) or nil
    local pts = village_point()
    runtime.pts = as_number(try_field(pts, "_Point"))
    runtime.pts_max = pts and pts_cap(pts) or nil
    runtime.atk = as_number(try_field(data, "_Attack"))
    runtime.elem = as_number(try_field(data, "_ElementAttack"))
    read_wirebugs(hunter)
    -- Method reads wait for playable. get_VitalF AVs outside quest Play.
    if runtime.quest_play and runtime.playable then
        runtime.green = as_number(try_field(hunter, "_VitalF"))
        runtime.sharp, runtime.sharp_max, runtime.sharp_lv = read_sharpness(hunter)
    elseif runtime.playable then
        runtime.green = nil
        runtime.sharp, runtime.sharp_max, runtime.sharp_lv = read_sharpness(hunter)
    else
        runtime.green = nil
        runtime.sharp, runtime.sharp_max, runtime.sharp_lv = nil, nil, nil
    end
end

menu = RefShell.create({
    id = "mhrise",
    title = "MH RISE QOL",
    toggle_vk = 0xC0,
    dock = "right",
    width = 400,
    height = 720,
    start_open = false,
    persist = features,
    host = true,
    lock_camera = true,
    lock_cursor = true,
    show_logs = false,
})

menu:add_tab("Cheats", function(ui)
    ui.section("Status", function()
        local party = runtime.party
        imgui.text("Cheats:")
        imgui.same_line()
        imgui.text_colored(party.label, party.enabled and COL_OK or COL_BAD)
        ui.muted(party.detail)
        ui.kv("Lobby", string.format("%d hunter%s", party.humans, party.humans == 1 and "" or "s"))
        imgui.text("Hunter:")
        imgui.same_line()
        local label = "Waiting"
        local color = COL_WAIT
        if runtime.playable then
            label = runtime.via
            color = COL_OK
        elseif runtime.hooked then
            label = "Loading"
        end
        imgui.text_colored(label, color)
        if runtime.hp and runtime.max_hp then
            ui.kv("HP", string.format("%.0f keep / %.0f max", runtime.hp, runtime.max_hp))
        else
            ui.kv("HP", "—")
        end
        if runtime.r_vital then
            ui.kv("r_Vital", string.format("%.0f", runtime.r_vital))
        end
        if runtime.green then
            ui.kv("Green", string.format("%.1f", runtime.green))
        end
        if runtime.vitalizer then
            ui.kv("Vitalizer", string.format("%.1f", runtime.vitalizer))
        end
        if runtime.stamina and runtime.max_stamina then
            ui.kv("Stamina", string.format("%.0f / %.0f", runtime.stamina, runtime.max_stamina))
        else
            ui.kv("Stamina", "—")
        end
        if runtime.sharp and runtime.sharp_max then
            local lv = SHARP_LV[runtime.sharp_lv] or tostring(runtime.sharp_lv or "?")
            ui.kv("Sharpness", string.format("%.0f / %.0f (%s)", runtime.sharp, runtime.sharp_max, lv))
        else
            ui.kv("Sharpness", "—")
        end
        if runtime.zenny then
            ui.kv("Zenny", string.format("%d / %s", runtime.zenny, runtime.zenny_max or "?"))
        else
            ui.kv("Zenny", "—")
        end
        if runtime.pts then
            ui.kv("Pts", string.format("%d / %s", runtime.pts, runtime.pts_max or "?"))
        else
            ui.kv("Pts", "—")
        end
        if runtime.wire_ready or runtime.wire_extra then
            ui.kv("Wirebugs", string.format(
                "%s ready, extras %s, recast %.1f",
                tostring(runtime.wire_ready or 0),
                tostring(runtime.wire_extra or 0),
                runtime.wire_recast or 0
            ))
        end
        if runtime.cheats_enabled and features.more_damage then
            ui.kv("Damage", string.format("%.1fx", tonumber(features.more_damage_mult) or 2.0))
        end
        if runtime.cheats_enabled and features.bow_range then
            ui.kv("Bow range", string.format("%.0fm", BOW_RANGE))
        end
        if runtime.cheats_enabled and features.move_fast then
            ui.kv("Play Speed", string.format("%.1fx", tonumber(features.move_fast_mult) or 2.0))
        end
        if runtime.atk then
            local base = runtime.atk_base
            if type(base) == "number" then
                ui.kv("Attack", string.format("%.0f (base %.0f)", runtime.atk, base))
            else
                ui.kv("Attack", string.format("%.0f", runtime.atk))
            end
        end
        ui.kv("Last action", runtime.last_log)
        ui.muted("~ toggles this menu (rebind on Settings). Look input pauses while it is open.")
    end, false)

    ui.section("Cheats", function()
        ui.bind_toggle("Always Reserve Health", features, "always_reserve")
        ui.bind_toggle("Infinite Items", features, "inf_items")
        if features.inf_items then
            ui.muted("Playable pouch and box only. Town smith is Free Smithy Crafts on Gameplay.")
        end
        ui.bind_toggle("Infinite Wirebugs", features, "inf_wire")
        ui.bind_toggle("God Mode", features, "god_mode")
        ui.bind_toggle("Infinite Stamina", features, "inf_stamina")
        ui.bind_toggle("Always Sharp", features, "always_sharp")
        ui.bind_toggle("Bow Range", features, "bow_range")
        if features.bow_range then
            ui.muted("Bow only. Arrows stay in the crit window to 120m.")
        end
        ui.bind_toggle("More Damage", features, "more_damage")
        ui.bind_combo("Damage", features, "more_damage_mult", DAMAGE_OPTIONS)
        ui.bind_toggle("Move Fast", features, "move_fast")
        ui.bind_combo("Play Speed", features, "move_fast_mult", SPEED_OPTIONS)
        if not runtime.party.enabled then
            ui.muted("Solo only. The toggles are ignored while others are in the lobby.")
        elseif not runtime.hooked then
            ui.muted("Waiting for hunter.")
        elseif not runtime.playable then
            ui.muted("Cheats paused until the quest is in Play.")
        end
    end, true)
end)

menu:add_tab("Give", function(ui)
    ui.muted("Puts armor in the Item Box. Forge crafts stay on Gameplay. Solo only.")
    ui.section("Armor", function()
        local items = give_catalog()
        if type(items) ~= "table" or #items == 0 then
            ui.muted("Catalog empty. Enter town / smithy once, then Refresh.")
            ui.actions({
                { "Refresh list", function()
                    runtime.give.items = nil
                    give_catalog()
                end },
            }, 1)
            return
        end
        local labels = {}
        for i = 1, #items do
            labels[i] = items[i].label
        end
        local selected = runtime.give.selected or 0
        local pick, changed = ui.filter_dropdown(
            "give_armor",
            nil,
            labels,
            selected,
            runtime.give.pick,
            {
                header = string.format("Armor  %d", #items),
                placeholder = "Pick armor…",
                filter_placeholder = "name or set…",
                height = 260,
            }
        )
        if changed and type(pick) == "number" then
            runtime.give.selected = pick
            selected = pick
        end
        local entry = items[selected]
        if entry then
            ui.kv("Set", entry.series)
            ui.kv("Piece", entry.name)
            ui.kv("Part", entry.part_name)
        else
            ui.muted("Pick a piece, then Give. Open the Item Box to equip.")
        end
        if not runtime.cheats_enabled then
            ui.muted("Solo only. Giving is ignored while others are in the lobby.")
        end
        ui.actions({
            { "Give piece", give_selected },
            { "Give set", give_selected_set },
        }, 2)
        ui.actions({
            { "Refresh list", function()
                runtime.give.items = nil
                runtime.give.selected = 0
                give_catalog()
            end },
        }, 1)
    end, true)
end)

menu:add_tab("Gameplay", function(ui)
    ui.muted("This tab stays on in any session. Combat cheats do not.")
    ui.section("Health Bars", function()
        ui.bind_toggle("Health Bars", features, "health_bars")
        ui.bind_toggle("Show HP text", features, "health_bars_hp_text")
        ui.bind_toggle("Show distance", features, "health_bars_show_dist")
        ui.bind_toggle("Small monsters", features, "health_bars_zako")
        ui.muted("Bosses always. Small monsters stay off unless you turn them on — rampages will flood otherwise.")
        ui.bind_combo("Draw distance", features, "health_bars_dist", DIST_OPTIONS)
        ui.bind_combo("Bar scale", features, "health_bars_scale", SCALE_OPTIONS)
        ui.muted("Bosses 2x red. Small monsters 1x teal. Scale multiplies both. Draw distance is the combo above.")
    end, true)
    ui.section("Smithy", function()
        ui.bind_toggle("Free Smithy Crafts", features, "free_tree")
        if features.free_tree then
            ui.muted("Weapon tree, weapon list, upgrade list, forge armor, and layered armor. Materials, category pts, and zenny go to 0. Don't mash Confirm.")
        end
        ui.bind_toggle("Unlock All Armor", features, "unlock_armor")
        if features.unlock_armor then
            ui.muted("Lists every forgeable set on Low / High / Master / Special. Gift / arena / leftover rows with no cookbook recipe are hidden — those go to the Item Box when earned, they are not smithy crafts. Switch tabs if a rank looks empty.")
        end
    end, true)
    ui.section("Quick Actions", function()
        ui.actions({
            { "Max Zenny", function()
                fill_zenny()
            end },
            { "+10k Zenny", function()
                add_zenny(10000)
            end },
            { "Max Pts", function()
                fill_pts()
            end },
            { "+1k Pts", function()
                add_pts(1000)
            end },
        }, 2)
    end, true)
end)

local function sync_health_bars()
    if not HealthBars then
        return
    end
    local want = features.health_bars ~= false
    local was = HealthBars.enabled and true or false
    HealthBars.enabled = want
    if want and not was and HealthBars.kick then
        HealthBars.kick()
    end
    HealthBars.show_zako = features.health_bars_zako and true or false
    local dist = features.health_bars_dist
    if type(dist) == "number" then
        HealthBars.max_draw_dist = dist
    end
    HealthBars.show_hp_text = features.health_bars_hp_text ~= false
    HealthBars.show_dist = features.health_bars_show_dist ~= false
    -- Bars only read EnemyManager. Do not pause them on the cheat playable
    -- gate — that wipe hid bars until you re-toggled at quest start.
    if HealthBars.paused then
        HealthBars.paused = false
        if HealthBars.kick then
            HealthBars.kick()
        end
    end
    local scale = features.health_bars_scale
    if type(scale) == "number" then
        if scale > 2.5 then
            scale = 2.5
            features.health_bars_scale = 2.5
            menu.dirty = true
        elseif scale < 1.5 then
            scale = 1.5
            features.health_bars_scale = 1.5
            menu.dirty = true
        end
        HealthBars.scale = scale
    end
end

local function sync_free_tree()
    if not FreeTree then
        return
    end
    FreeTree.free = features.free_tree and true or false
    FreeTree.unlock = features.unlock_armor and true or false
end

re.on_frame(function()
    local ok, err = pcall(function()
        local hunter = master_hunter()
        local data = master_data()
        runtime.party = party_status()
        runtime.cheats_enabled = runtime.party.enabled
        update_playable(hunter, data)
        refresh_status(hunter, data)
        sync_health_bars()
        sync_free_tree()
        apply_play_speed(runtime.cheats_enabled and runtime.playable and features.move_fast)
        if not runtime.playable then
            if not features.inf_stamina then
                runtime.stamina_cap = nil
            end
            if runtime.atk_base then
                hold_attack(data)
            end
            restore_bow_range()
            return
        end
        if runtime.cheats_enabled and features.always_reserve then
            hold_reserve(data)
        end
        if runtime.cheats_enabled and features.god_mode then
            hold_green(hunter, data)
        end
        if runtime.cheats_enabled and features.inf_stamina then
            refill_stamina(hunter, data)
        else
            runtime.stamina_cap = nil
        end
        if runtime.cheats_enabled and features.always_sharp then
            hold_sharpness(hunter)
        end
        if runtime.cheats_enabled and features.bow_range then
            hold_bow_range(hunter)
        else
            restore_bow_range()
        end
        if runtime.cheats_enabled and features.inf_wire then
            hold_wirebugs(hunter)
        else
            runtime.wire_pin = nil
        end
        if features.more_damage or runtime.atk_base then
            hold_attack(data)
        end
    end)
    if not ok then
        log_action("frame error: " .. tostring(err))
    end
end)

install_god_hooks()
install_item_hooks()
install_attack_hooks()
menu:bind()

if menu.cfg.toggle_vk == 0x75 or menu.cfg.toggle_vk == 0x2D then
    menu.cfg.toggle_vk = 0xC0
    menu.dirty = true
end

apply_play_speed(false)
call_static("via.Application", "set_GlobalSpeed(System.Single)", 1.0)
