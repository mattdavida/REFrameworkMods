-- main.lua
-- MH Wilds QOL trainer on RefShell.
-- Cheats stay off unless the party is solo (no other human hunters).

local RefShell = _G.RefShell
if not RefShell then
    local ok, mod = pcall(require, "refshell")
    if ok then
        RefShell = mod
    end
end

if not RefShell then
    log.error("[mhwilds] refshell missing — run npm run bundle (inlines ../../REFrameworkRefShell)")
    return
end

local HealthBars = _G.MHHealthBars
if not HealthBars then
    local ok, mod = pcall(require, "healthbars")
    if ok then
        HealthBars = mod
    end
end

local COL_OK = 0xFF6EE66E
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

local SPEED_OPTIONS = {
    { 1.0,  "1x" },
    { 1.5,  "1.5x" },
    { 2.0,  "2x" },
    { 3.0,  "3x" },
    { 5.0,  "5x" },
    { 10.0, "10x" },
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

local features = {
    god_mode = false,
    inf_stamina = false,
    inf_items = false,
    free_craft = false,
    free_smithy = false,
    unlock_armor = false,
    unlock_palico = false,
    unlock_weapons = false,
    always_sharp = false,
    more_damage = false,
    more_damage_mult = 2.0,
    move_fast = false,
    move_fast_mult = 2.0,
    move_fast_vk = 0,
    health_bars = true,
    health_bars_vk = 0,
    health_bars_dist = 0,
    health_bars_hp_text = true,
    health_bars_show_dist = true,
    health_bars_scale = 1.5,
    health_bars_zako = false,
}

local KIREAJI_NAME = {
    [0] = "Red",
    [1] = "Orange",
    [2] = "Yellow",
    [3] = "Green",
    [4] = "Blue",
    [5] = "White",
    [6] = "Purple",
}

local menu
local try_call

local runtime = {
    last_log = "(none)",
    cheats_enabled = false,
    god_was_on = false,
    stamina_was_on = false,
    items_was_on = false,
    craft_was_on = false,
    crafting = false,
    smithy_was_on = false,
    smithy_paying = false,
    unlock_was_on = false,
    unlock_palico_was_on = false,
    unlock_weapon_was_on = false,
    weapon_gui_open = false,
    weapon_gui = nil,
    weapon_tick = 0,
    weapon_building = false,
    speed_was_on = false,
    mf_key_down = false,
    mf_vk = nil,
    hp = nil,
    max_hp = nil,
    stamina = nil,
    max_stamina = nil,
    sharpness = nil,
    zenny = nil,
    points = nil,
    party = {
        enabled = false,
        label = "Disabled",
        detail = "Checking party…",
        humans = 0,
    },
    hb_key_down = false,
    hb_vk = nil,
}

local function log_action(text)
    runtime.last_log = text
    log.info("[mhwilds] " .. text)
end

try_call = function(obj, names, ...)
    if not obj then
        return nil, false
    end
    for _, name in ipairs(names) do
        local a, b = ...
        local ok, result = pcall(function()
            if b ~= nil then
                return obj:call(name, a, b)
            end
            if a ~= nil then
                return obj:call(name, a)
            end
            return obj:call(name)
        end)
        if ok then
            return result, true
        end
    end
    return nil, false
end

local function try_static(type_name, names, ...)
    local td = sdk.find_type_definition(type_name)
    if not td then
        return nil, false
    end
    local a, b = ...
    for _, name in ipairs(names) do
        local method = td:get_method(name)
        if method then
            local ok, result = pcall(function()
                if b ~= nil then
                    return method:call(nil, a, b)
                end
                if a ~= nil then
                    return method:call(nil, a)
                end
                return method:call(nil)
            end)
            if ok then
                return result, true
            end
        end
    end
    return nil, false
end

local function is_managed(obj)
    return obj ~= nil and type(obj) == "userdata"
end

local function flag_true(obj, names)
    local value = try_call(obj, names)
    return value == true
end

local function is_human_hunter(info)
    if not is_managed(info) then
        return false
    end
    if flag_true(info, {
            "get_IsNpc",
            "get_IsNPC",
            "get_IsAI",
            "get_IsBot",
            "get_IsSupport",
            "get_IsSupportHunter",
            "get_IsOtomo",
        }) then
        return false
    end

    local chara = try_call(info, { "get_Character", "get_Hunter" })
    if is_managed(chara) and flag_true(chara, {
            "get_IsNpc",
            "get_IsNPC",
            "get_IsAI",
            "get_IsBot",
            "get_IsSupportHunter",
            "get_IsAIHunter",
        }) then
        return false
    end

    return true
end

local function collect_players(pm)
    local list = {}
    local seen = {}
    local enumerated = false

    local function add(info)
        if not is_managed(info) then
            return
        end
        local addr = info.get_address and info:get_address() or tostring(info)
        if seen[addr] then
            return
        end
        seen[addr] = true
        list[#list + 1] = info
    end

    add(try_call(pm, { "getMasterPlayer", "get_MasterPlayer" }))

    for i = 0, 3 do
        local info, ok = try_call(pm, { "getPlayer", "get_Player" }, i)
        if ok then
            enumerated = true
            add(info)
        end
    end

    local arr, arr_ok = try_call(pm, { "get_PlayerList", "getPlayerList", "get_Players" })
    if arr_ok and is_managed(arr) then
        local n = try_call(arr, { "get_Count", "get_Length", "get_size" })
        if type(n) == "number" then
            enumerated = true
            for i = 0, n - 1 do
                add(try_call(arr, { "get_Item" }, i))
            end
        end
    end

    return list, enumerated
end

local function party_status()
    local pm = sdk.get_managed_singleton("app.PlayerManager")
    if not pm then
        return {
            enabled = false,
            label = "Disabled",
            detail = "Waiting for PlayerManager",
            humans = 0,
        }
    end

    local master, have_master = try_call(pm, { "getMasterPlayer", "get_MasterPlayer" })
    if not have_master or not is_managed(master) then
        return {
            enabled = false,
            label = "Disabled",
            detail = "Not in the field",
            humans = 0,
        }
    end

    local players, enumerated = collect_players(pm)
    local humans = 0
    for _, info in ipairs(players) do
        if is_human_hunter(info) then
            humans = humans + 1
        end
    end

    if not enumerated then
        return {
            enabled = false,
            label = "Disabled",
            detail = "Could not read party list — fail closed",
            humans = humans,
        }
    end

    if humans <= 1 then
        return {
            enabled = true,
            label = "Enabled",
            detail = "Solo — no other hunters in party",
            humans = humans,
        }
    end

    return {
        enabled = false,
        label = "Disabled",
        detail = string.format("Party has %d hunters", humans),
        humans = humans,
    }
end

local function get_master_info()
    local pm = sdk.get_managed_singleton("app.PlayerManager")
    local info = try_call(pm, { "getMasterPlayer", "get_MasterPlayer" })
    if is_managed(info) then
        return info
    end
    return nil
end

-- app.cPlayerManageInfo -> app.HunterCharacter -> app.cHunterHealth -> app.cHealthManager
local function get_hunter_character(info)
    info = info or get_master_info()
    local chara = try_call(info, { "get_Character", "get_Hunter" })
    if is_managed(chara) then
        return chara
    end
    return nil
end

local function get_hunter_health(chara)
    chara = chara or get_hunter_character()
    local hh = try_call(chara, { "get_HunterHealth" })
    if is_managed(hh) then
        return hh
    end
    return nil
end

local function get_health_mgr(hh)
    hh = hh or get_hunter_health()
    local mgr = try_call(hh, { "get_HealthMgr", "get_HealthManager" })
    if is_managed(mgr) then
        return mgr
    end
    local chara = get_hunter_character()
    mgr = try_call(chara, { "get_HealthManager" })
    if is_managed(mgr) then
        return mgr
    end
    return nil
end

local function read_hp()
    local mgr = get_health_mgr()
    if not mgr then
        return nil, nil
    end
    local hp = try_call(mgr, { "get_Health" })
    local max_hp = try_call(mgr, { "get_MaxHealth" })
    if type(hp) == "number" and type(max_hp) == "number" then
        return hp, max_hp
    end
    return nil, nil
end

local function set_no_damage(on)
    local hh = get_hunter_health()
    if not hh then
        return false
    end
    try_call(hh, { "set_IsNoDamage" }, on and true or false)
    pcall(function()
        hh:set_field("_IsNoDamage", on and true or false)
    end)
    return true
end

local function refill_health()
    local hh = get_hunter_health()
    local mgr = get_health_mgr(hh)
    if not mgr then
        return false
    end
    local max_hp = try_call(mgr, { "get_MaxHealth" })
    if type(max_hp) ~= "number" then
        return false
    end
    try_call(hh, { "setHealth" }, max_hp)
    try_call(mgr, { "set_Health" }, max_hp)
    return true
end

-- app.HunterCharacter.get_HunterStamina -> app.cHunterStamina
local function get_hunter_stamina(chara)
    chara = chara or get_hunter_character()
    local st = try_call(chara, { "get_HunterStamina" })
    if is_managed(st) then
        return st
    end
    return nil
end

local function read_stamina()
    local st = get_hunter_stamina()
    if not st then
        return nil, nil
    end
    local cur = try_call(st, { "get_Stamina", "get_StaminaTotal" })
    local max_st = try_call(st, { "get_MaxStamina", "get_StaminaLimit", "get_MaxStaminaTotal" })
    if type(cur) == "number" and type(max_st) == "number" then
        return cur, max_st
    end
    return nil, nil
end

local function set_stamina_no_use(on)
    local st = get_hunter_stamina()
    if not st then
        return false
    end
    try_call(st, { "set_IsStaminaNoUse" }, on and true or false)
    try_call(st, { "set_IsStopAutoReduceMaxStamina" }, on and true or false)
    pcall(function()
        st:set_field("_IsStaminaNoUse", on and true or false)
        st:set_field("_IsStopAutoReduceMaxStamina", on and true or false)
    end)
    return true
end

local function refill_stamina()
    local st = get_hunter_stamina()
    if not st then
        return false
    end
    try_call(st, { "requestHealStamina" })
    local max_st = try_call(st, { "get_MaxStamina", "get_StaminaLimit", "get_MaxStaminaTotal" })
    if type(max_st) == "number" then
        try_call(st, { "setStamina" }, max_st)
    end
    return true
end

local function apply_inf_stamina(want)
    if want then
        set_stamina_no_use(true)
        refill_stamina()
        runtime.stamina_was_on = true
    elseif runtime.stamina_was_on then
        set_stamina_no_use(false)
        runtime.stamina_was_on = false
    end
end

-- HunterCharacter.get_WeaponHandling -> cHunterWeaponHandlingBase.get_Kireaji -> cWeaponKireaji
local function get_kireaji(chara)
    chara = chara or get_hunter_character()
    local handling = try_call(chara, { "get_WeaponHandling" })
    local kireaji = try_call(handling, { "get_Kireaji" })
    if is_managed(kireaji) then
        return kireaji
    end
    return nil
end

local function kireaji_label(type_id)
    if type(type_id) ~= "number" then
        return nil
    end
    return KIREAJI_NAME[type_id] or tostring(type_id)
end

local function read_sharpness()
    local kireaji = get_kireaji()
    if not kireaji then
        return nil
    end
    local cur = try_call(kireaji, { "get_CurrentType" })
    local max_t = try_call(kireaji, { "get_MaxKireajiType" })
    local at_max = try_call(kireaji, { "get_IsMaxKireaji" })
    local cur_name = kireaji_label(cur)
    if not cur_name then
        return nil
    end
    local max_name = kireaji_label(max_t)
    if max_name then
        return string.format("%s / %s%s", cur_name, max_name, at_max == true and " (max)" or "")
    end
    return cur_name
end

local function refill_sharpness()
    local kireaji = get_kireaji()
    if not kireaji then
        return false
    end
    try_call(kireaji, { "resetKireaji" })
    local max_t = try_call(kireaji, { "get_MaxKireajiType" })
    if type(max_t) == "number" and max_t >= 0 and max_t <= 6 then
        try_call(kireaji, { "setKireajiType" }, max_t)
    end
    try_call(kireaji, { "healKireaji" }, 9999)
    return true
end

local function apply_always_sharp(want)
    if want then
        refill_sharpness()
    end
end

local function apply_inf_items(want)
    if want then
        local first = not runtime.items_was_on
        runtime.items_was_on = true
        if first then
            log_action("infinite items on")
        end
    elseif runtime.items_was_on then
        runtime.items_was_on = false
        log_action("infinite items off")
    end
end

local function apply_free_craft(want)
    if want then
        local first = not runtime.craft_was_on
        runtime.craft_was_on = true
        if first then
            log_action("free craft on")
        end
    elseif runtime.craft_was_on then
        runtime.craft_was_on = false
        runtime.crafting = false
        log_action("free craft off")
    end
end

local function apply_free_smithy(want)
    if want then
        local first = not runtime.smithy_was_on
        runtime.smithy_was_on = true
        if first then
            log_action("free smithy on")
        end
    elseif runtime.smithy_was_on then
        runtime.smithy_was_on = false
        runtime.smithy_paying = false
        log_action("free smithy off")
    end
end

local refresh_armor_unlock
local refresh_palico_unlock
local find_weapon_gui

local function apply_unlock_armor(want)
    if want then
        local first = not runtime.unlock_was_on
        runtime.unlock_was_on = true
        if first then
            log_action("unlock armor on")
            if refresh_armor_unlock then
                refresh_armor_unlock()
            end
        end
    elseif runtime.unlock_was_on then
        runtime.unlock_was_on = false
        log_action("unlock armor off")
    end
end

local function apply_unlock_palico(want)
    if want then
        local first = not runtime.unlock_palico_was_on
        runtime.unlock_palico_was_on = true
        if first then
            log_action("unlock palico on")
            if refresh_palico_unlock then
                refresh_palico_unlock()
            end
        end
    elseif runtime.unlock_palico_was_on then
        runtime.unlock_palico_was_on = false
        log_action("unlock palico off")
    end
end

-- Rise FreeTree: tick while smithy is up, never rebuild lists, never touch arrays.
-- Wilds crash was the same: setRecipeData / updateCurrentEquipData / checkStoryFlag
-- during structureDispRecipeList grows _DispRecipeLists and dies.
-- IsOpen stays false on this page; parent smithy owns open. Use IsVisible + a recipe.
local function apply_unlock_weapons(want)
    if not want then
        if runtime.unlock_weapon_was_on then
            runtime.unlock_weapon_was_on = false
            runtime.weapon_gui_open = false
            runtime.weapon_gui = nil
            runtime.weapon_tick = 0
            runtime.weapon_building = false
            log_action("unlock weapons off")
        end
        return
    end
    local first = not runtime.unlock_weapon_was_on
    runtime.unlock_weapon_was_on = true
    if first then
        log_action("unlock weapons on")
    end
    runtime.weapon_tick = (runtime.weapon_tick or 0) + 1
    if (runtime.weapon_tick % 8) ~= 1 then
        return
    end
    local gui = runtime.weapon_gui
    if not is_managed(gui) and find_weapon_gui then
        runtime.weapon_gui = find_weapon_gui()
        gui = runtime.weapon_gui
    end
    local showing = false
    if is_managed(gui) then
        local ok = pcall(function()
            showing = gui:call("get_IsVisible") == true
                and is_managed(gui:get_field("_CurrentRecipe"))
        end)
        if not ok then
            runtime.weapon_gui = nil
        end
    end
    runtime.weapon_gui_open = showing
end

-- Rise consumeItem: field use must still fire; only the stack drop is skipped.
-- Wilds analog is ItemUtil.useItem. changeItemNum is also sell/craft/dialogue,
-- so skip that only for a negative pouch delta.
local function consume_ok()
    return runtime.cheats_enabled and features.inf_items
end

local function craft_ok()
    return runtime.cheats_enabled and features.free_craft
end

local function smithy_ok()
    return runtime.cheats_enabled and features.free_smithy
end

local function unlock_ok()
    return runtime.cheats_enabled and features.unlock_armor
end

local function unlock_palico_ok()
    return runtime.cheats_enabled and features.unlock_palico
end

local function unlock_weapon_ok()
    return runtime.cheats_enabled
        and features.unlock_weapons
        and runtime.weapon_gui_open
        and not runtime.weapon_building
end

local function skip_pouch_spend()
    return consume_ok() or runtime.crafting
end

local function recipe_type_name(ptr)
    local obj
    pcall(function()
        obj = sdk.to_managed_object(ptr)
    end)
    if not obj then
        return nil
    end
    local name
    pcall(function()
        name = obj:get_type_definition():get_full_name()
    end)
    return name
end

-- Unlock All Armor stays hunter-only. Free Smithy covers weapons, hunter armor, Palico.
local function is_armor_smithy(ptr)
    local name = recipe_type_name(ptr)
    return name == "app.EquipDef.ArmorRecipeInfo"
        or name == "app.EquipDef.ArmorUpgradeRecipeInfo"
end

local function is_palico_smithy(ptr)
    return recipe_type_name(ptr) == "app.EquipDef.OtEquipRecipeInfo"
end

local function is_weapon_smithy(ptr)
    local obj
    pcall(function()
        obj = sdk.to_managed_object(ptr)
    end)
    if not obj then
        return false
    end
    local is_w
    pcall(function()
        is_w = obj:get_field("_IsWeapon")
    end)
    return is_w == true
end

local function is_smithy_recipe(ptr)
    return is_armor_smithy(ptr) or is_weapon_smithy(ptr) or is_palico_smithy(ptr)
end

local function as_i16(raw)
    if type(raw) ~= "number" then
        return nil
    end
    raw = raw & 0xFFFF
    if raw >= 0x8000 then
        return raw - 0x10000
    end
    return raw
end

local function enum_value(type_name, field)
    local td = sdk.find_type_definition(type_name)
    local f = td and td:get_field(field)
    if not f then
        return nil
    end
    local ok, value = pcall(function()
        return f:get_data(nil)
    end)
    if ok and type(value) == "number" then
        return value
    end
    return nil
end

local STOCK_POUCH = enum_value("app.ItemUtil.STOCK_TYPE", "POUCH")

do
    local item_td = sdk.find_type_definition("app.ItemUtil")
    local use_item = item_td and (
        item_td:get_method("useItem(app.ItemDef.ID, System.Int16, System.Boolean)")
        or item_td:get_method("useItem")
    )
    if use_item then
        sdk.hook(use_item, function()
            if consume_ok() then
                return sdk.PreHookResult.SKIP_ORIGINAL
            end
        end, function(retval)
            return retval
        end)
        log.info("[mhwilds] hooked ItemUtil.useItem")
    else
        log.error("[mhwilds] ItemUtil.useItem missing")
    end

    local change_num = item_td and (
        item_td:get_method("changeItemNum(app.ItemDef.ID, System.Int16, app.ItemUtil.STOCK_TYPE)")
        or item_td:get_method("changeItemNum")
    )
    if change_num then
        sdk.hook(change_num, function(args)
            local n = nil
            local stock = nil
            pcall(function()
                n = as_i16(sdk.to_int64(args[3]))
                stock = sdk.to_int64(args[4])
            end)
            if type(stock) == "number" then
                stock = stock & 0xFFFFFFFF
            end
            if n == nil or n >= 0 then
                return
            end
            -- Smithy pay is box (and sometimes pouch). Scoped to FacilityTradeInfo.pay.
            if runtime.smithy_paying then
                return sdk.PreHookResult.SKIP_ORIGINAL
            end
            if not skip_pouch_spend() then
                return
            end
            if STOCK_POUCH == nil or stock ~= STOCK_POUCH then
                return
            end
            return sdk.PreHookResult.SKIP_ORIGINAL
        end, function(retval)
            return retval
        end)
        log.info("[mhwilds] hooked ItemUtil.changeItemNum")
    else
        log.error("[mhwilds] ItemUtil.changeItemNum missing")
    end
end

do
    local recipe_td = sdk.find_type_definition("app.ItemRecipeUtil")
    local enable_type = enum_value("app.ItemRecipeUtil.CRAFT_ENABLE_TYPE", "ENABLE") or 0

    local function hook_craft_enable(method)
        if not method then
            return
        end
        sdk.hook(method, function()
        end, function(retval)
            if craft_ok() then
                return sdk.to_ptr(1)
            end
            return retval
        end)
    end

    if recipe_td then
        hook_craft_enable(recipe_td:get_method(
            "isCraftEnable(app.ItemDef.ID, app.ItemUtil.STOCK_TYPE, System.Boolean)"
        ))
        hook_craft_enable(recipe_td:get_method(
            "isCraftEnable(app.ItemDef.ID, app.ItemUtil.STOCK_TYPE, System.Boolean, System.Int32)"
        ))

        local info_m = recipe_td:get_method(
            "getEnableCraftInfo(app.user_data.cItemRecipe.cData, app.ItemUtil.STOCK_TYPE, app.ItemDef.ID, System.Int16)"
        )
        if info_m then
            sdk.hook(info_m, function()
            end, function(retval)
                if craft_ok() then
                    local info
                    pcall(function()
                        info = sdk.to_managed_object(retval)
                    end)
                    if info then
                        pcall(function()
                            info:set_field("EnableType", enable_type)
                        end)
                        local n = nil
                        pcall(function()
                            n = info:get_field("EnableCount")
                        end)
                        if type(n) ~= "number" or n < 1 then
                            pcall(function()
                                info:set_field("EnableCount", 99)
                            end)
                        end
                    end
                end
                return retval
            end)
        end

        local craft_m = recipe_td:get_method(
            "craft(app.user_data.cItemRecipe.cData, app.ItemUtil.STOCK_TYPE, System.Int16)"
        )
        if craft_m then
            sdk.hook(craft_m, function()
                runtime.crafting = craft_ok()
            end, function(retval)
                runtime.crafting = false
                return retval
            end)
        end
        log.info("[mhwilds] hooked ItemRecipeUtil craft checks")
    else
        log.error("[mhwilds] ItemRecipeUtil missing")
    end
end

-- Smithy armor + weapon tree + Palico (CREATE / UPGRADE). Shared Excel rows stay intact.
-- FacilityTradeInfo.isEnoughItem is the cost gate (same role as isCraftEnable).
-- pay() still runs so the forge callback fires; spend is skipped for that window.
-- WeaponRecipeInfo.tradeConditions (need previous weapon) is left to vanilla.
do
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

    local checking = false

    local function hook_trade_bool(method)
        if not method then
            return
        end
        sdk.hook(method, function(args)
            checking = smithy_ok() and is_smithy_recipe(args[2])
        end, function(retval)
            if checking then
                return sdk.to_ptr(1)
            end
            return retval
        end)
    end

    local function hook_pay(method)
        if not method then
            return
        end
        sdk.hook(method, function(args)
            runtime.smithy_paying = smithy_ok() and is_smithy_recipe(args[2])
        end, function(retval)
            runtime.smithy_paying = false
            return retval
        end)
    end

    local trade_td = sdk.find_type_definition("app.FacilityDef.FacilityTradeInfo")
    if trade_td then
        hook_trade_bool(trade_td:get_method("isEnoughItem()"))
        hook_trade_bool(trade_td:get_method("isEnoughItem(app.ItemDef.ID, System.Int32)"))
        hook_trade_bool(trade_td:get_method("isEnoughMoney()"))
        hook_trade_bool(trade_td:get_method("canTrade()"))
        hook_pay(trade_td:get_method("pay(System.Action)"))
        hook_pay(trade_td:get_method("pay(app.ItemUtil.STOCK_TYPE, System.Action)"))
        log.info("[mhwilds] hooked FacilityTradeInfo smithy")
    else
        log.error("[mhwilds] FacilityTradeInfo missing")
    end

    local function hook_wallet_spend(type_name, signature)
        local td = sdk.find_type_definition(type_name)
        local method = td and td:get_method(signature)
        if not method then
            return false
        end
        sdk.hook(method, function(args)
            if not runtime.smithy_paying then
                return
            end
            local n
            pcall(function()
                n = as_i32(sdk.to_int64(args[2]))
            end)
            if n ~= nil and n < 0 then
                return sdk.PreHookResult.SKIP_ORIGINAL
            end
        end, function(retval)
            return retval
        end)
        return true
    end

    if hook_wallet_spend("app.BasicParamUtil", "addMoney(System.Int32, System.Boolean)") then
        log.info("[mhwilds] hooked BasicParamUtil.addMoney")
    else
        log.error("[mhwilds] BasicParamUtil.addMoney missing")
    end
    hook_wallet_spend("app.BasicParamUtil", "addPoint(System.Int32, System.Boolean)")
end

-- Unlock All Armor / Weapons. Rise stuffed series into tab buckets and cleared flags.
-- Wilds analog: isOpenRecipe is the visibility gate (key item / story / hunt / HR).
-- Weapon ????? names are the same gate. Tree column locks use checkStoryFlag.
-- Armor tabs are MissionUtil.STORYLV_TYPE (MAIN / EX / EX_CLEAR).
do
    local STORY_MAIN = enum_value("app.MissionUtil.STORYLV_TYPE", "MAIN")
    local STORY_EX = enum_value("app.MissionUtil.STORYLV_TYPE", "EX")
    local STORY_EX_CLEAR = enum_value("app.MissionUtil.STORYLV_TYPE", "EX_CLEAR")

    local function type_name(obj)
        if not is_managed(obj) then
            return nil
        end
        local name
        pcall(function()
            name = obj:get_type_definition():get_full_name()
        end)
        return name
    end

    local function list_count(list)
        if not is_managed(list) then
            return 0
        end
        local n
        pcall(function()
            n = list:get_field("_size")
        end)
        if type(n) == "number" then
            return n
        end
        return 0
    end

    local function list_item(list, index)
        if not is_managed(list) then
            return nil
        end
        local item
        pcall(function()
            item = list:call("get_Item", index)
        end)
        if is_managed(item) then
            return item
        end
        local items
        pcall(function()
            items = list:get_field("_items")
        end)
        if is_managed(items) then
            pcall(function()
                item = items:get_element(index)
            end)
        end
        return item
    end

    local function find_input_gui(want)
        local gm = sdk.get_managed_singleton("app.GUIManager")
        if not is_managed(gm) then
            return nil
        end
        local list
        pcall(function()
            list = gm:get_field("_InputGUI")
        end)
        local n = list_count(list)
        for i = 0, n - 1 do
            local gui = list_item(list, i)
            if type_name(gui) == want then
                return gui
            end
        end
        return nil
    end

    local function arr_len(arr)
        if not is_managed(arr) then
            return 0
        end
        local n
        pcall(function()
            n = arr:get_size()
        end)
        if type(n) == "number" then
            return n
        end
        return 0
    end

    local function list_has(list, value)
        if not is_managed(list) or value == nil then
            return false
        end
        local ok, yes = pcall(function()
            return list:call("Contains", value)
        end)
        return ok and yes == true
    end

    local function ensure_armor_tabs(cat)
        if not is_managed(cat) then
            return
        end
        local list
        pcall(function()
            list = cat:get_field("CategoryList")
        end)
        if not is_managed(list) then
            return
        end
        local texts
        pcall(function()
            texts = cat:get_field("_CategoryTabTextIds")
        end)
        local max_tabs = arr_len(texts)
        if max_tabs < 1 then
            max_tabs = 3
        end
        local levels = { STORY_MAIN, STORY_EX, STORY_EX_CLEAR }
        local added = false
        for i = 1, math.min(#levels, max_tabs) do
            local lv = levels[i]
            if lv ~= nil and not list_has(list, lv) then
                local ok = pcall(function()
                    list:call("Add", lv)
                end)
                if ok then
                    added = true
                end
            end
        end
        if added then
            pcall(function()
                cat:call("changeTabVisible", true)
            end)
        end
    end

    local function refresh_list(gui)
        if not is_managed(gui) then
            return
        end
        local cat
        pcall(function()
            cat = gui:call("get__Category")
        end)
        ensure_armor_tabs(cat)
        local alist
        pcall(function()
            alist = gui:call("get__ArmorList")
        end)
        if is_managed(alist) then
            pcall(function()
                alist:call("setupArmorSeries")
            end)
        end
    end

    refresh_armor_unlock = function()
        if not unlock_ok() then
            return
        end
        refresh_list(find_input_gui("app.GUI080100"))
    end

    local function refresh_palico_list(gui)
        if not is_managed(gui) then
            return
        end
        local cat
        pcall(function()
            cat = gui:call("get_Category")
        end)
        ensure_armor_tabs(cat)
        local slist
        pcall(function()
            slist = gui:call("get_EquipSeriesList")
        end)
        if is_managed(slist) then
            pcall(function()
                slist:call("setupRowInfo")
            end)
        end
    end

    refresh_palico_unlock = function()
        if not unlock_palico_ok() then
            return
        end
        refresh_palico_list(find_input_gui("app.GUI080107"))
    end

    find_weapon_gui = function()
        return find_input_gui("app.GUI080101")
    end

    local checking = false

    local function hook_unlock_bool(method, ok_fn)
        if not method then
            return
        end
        sdk.hook(method, function()
            checking = ok_fn()
        end, function(retval)
            if checking then
                return sdk.to_ptr(1)
            end
            return retval
        end)
    end

    local recipe_base = sdk.find_type_definition("app.EquipDef.EquipRecipeInfoBase")
    if recipe_base then
        local open_m = recipe_base:get_method("isOpenRecipe()")
        if open_m then
            sdk.hook(open_m, function(args)
                checking = (unlock_ok() and is_armor_smithy(args[2]))
                    or (unlock_palico_ok() and is_palico_smithy(args[2]))
                    or (unlock_weapon_ok() and is_weapon_smithy(args[2]))
            end, function(retval)
                if checking then
                    return sdk.to_ptr(1)
                end
                return retval
            end)
        end
        log.info("[mhwilds] hooked EquipRecipeInfoBase.isOpenRecipe")
    else
        log.error("[mhwilds] EquipRecipeInfoBase missing")
    end

    local armor_info = sdk.find_type_definition("app.EquipDef.ArmorRecipeInfo")
    if armor_info then
        hook_unlock_bool(armor_info:get_method("tradeConditions()"), unlock_ok)
    end

    local otomo_info = sdk.find_type_definition("app.EquipDef.OtEquipRecipeInfo")
    if otomo_info then
        hook_unlock_bool(otomo_info:get_method("tradeConditions()"), unlock_palico_ok)
    end

    -- Do not hook WeaponRecipeInfo.tradeConditions (field hitch).
    -- Do not hook checkStoryFlag or call structureDispRecipeList / setRecipeData
    -- / updateCurrentEquipData. Those rebuild _DispRecipeLists and crash the
    -- same way Rise did when unlock wrote into smithy arrays.
    -- Fence the first tree build so isOpenRecipe stays vanilla until a recipe exists.

    local wep_gui = sdk.find_type_definition("app.GUI080101")
    local build_m = wep_gui and wep_gui:get_method("structureDispRecipeList()")
    if build_m then
        sdk.hook(build_m, function()
            runtime.weapon_building = true
        end, function(retval)
            runtime.weapon_building = false
            return retval
        end)
        log.info("[mhwilds] hooked GUI080101.structureDispRecipeList fence")
    end

    -- Do not hook isVisibleItem. That hides slots with no piece (earrings).
    -- Forcing it on draws the unknown icon with every badge stacked.

    local function hook_category_open(method)
        if not method then
            return
        end
        sdk.hook(method, function(args)
            if not unlock_ok() then
                return
            end
            local cat
            pcall(function()
                cat = sdk.to_managed_object(args[2])
            end)
            ensure_armor_tabs(cat)
        end, function(retval)
            if unlock_ok() then
                refresh_armor_unlock()
            end
            return retval
        end)
    end

    local cat_td = sdk.find_type_definition("app.GUI080100Category")
    if cat_td then
        hook_category_open(cat_td:get_method("init()"))
        hook_category_open(cat_td:get_method("onOpen()"))
        log.info("[mhwilds] hooked GUI080100Category armor tabs")
    else
        log.error("[mhwilds] GUI080100Category missing")
    end

    local function hook_palico_category_open(method)
        if not method then
            return
        end
        sdk.hook(method, function(args)
            if not unlock_palico_ok() then
                return
            end
            local cat
            pcall(function()
                cat = sdk.to_managed_object(args[2])
            end)
            ensure_armor_tabs(cat)
        end, function(retval)
            if unlock_palico_ok() then
                refresh_palico_unlock()
            end
            return retval
        end)
    end

    local otomo_cat = sdk.find_type_definition("app.GUI080107Category")
    if otomo_cat then
        hook_palico_category_open(otomo_cat:get_method("init()"))
        hook_palico_category_open(otomo_cat:get_method("onOpen()"))
        log.info("[mhwilds] hooked GUI080107Category palico tabs")
    else
        log.error("[mhwilds] GUI080107Category missing")
    end

    -- Do not hook GUI080101 onOpen/onClose. IsOpen stays false while the
    -- tree is up, so onOpen can latch weapon_gui_open in the field.
end

local function as_float(value)
    local n = tonumber(value)
    if not n then
        return 1.0
    end
    return n
end

-- Outgoing monster HP only. Hunter incoming damage is a different path.
local function damage_scale()
    if not runtime.cheats_enabled or not features.more_damage then
        return 1.0
    end
    local n = as_float(features.more_damage_mult)
    if n <= 0 then
        return 1.0
    end
    return n
end

local stock_td = sdk.find_type_definition("app.cEnemyStockDamage")
local calc_apply = stock_td and (
    stock_td:get_method("calcApplyDamage()")
    or stock_td:get_method("calcApplyDamage")
)
if calc_apply then
    sdk.hook(calc_apply, function()
    end, function(retval)
        local scale = damage_scale()
        if scale == 1.0 then
            return retval
        end
        local value = sdk.to_float(retval)
        if type(value) ~= "number" or value <= 0 then
            return retval
        end
        return sdk.float_to_ptr(value * scale)
    end)
    log.info("[mhwilds] hooked cEnemyStockDamage.calcApplyDamage")
else
    log.error("[mhwilds] cEnemyStockDamage.calcApplyDamage not found")
end

-- Wallet is via.rds.Mandrake on cBasicParam — use addMoney / getMoney, never the field.
local function get_basic_param()
    local sdm = sdk.get_managed_singleton("app.SaveDataManager")
    local param = try_call(sdm, { "getBasicParam", "get_BasicParam", "getCurrentBasicParam" })
    if is_managed(param) then
        return param
    end
    local user = try_call(sdm, {
        "get_UserSaveData",
        "getUserSaveData",
        "getCurrentUserSaveData",
        "get_CurrentUserSaveData",
    })
    param = try_call(user, { "get_BasicData", "getBasicData", "get_BasicParam", "getBasicParam" })
    if is_managed(param) then
        return param
    end
    if is_managed(user) then
        local ok, field = pcall(function()
            return user:get_field("_BasicData")
        end)
        if ok and is_managed(field) then
            return field
        end
    end
    return nil
end

local function read_zenny()
    local n, ok = try_static("app.BasicParamUtil", { "getMoney" })
    if ok and type(n) == "number" then
        return n
    end
    n = try_call(get_basic_param(), { "getMoney" })
    if type(n) == "number" then
        return n
    end
    return nil
end

local function add_zenny(amount)
    amount = amount or 10000
    if not runtime.cheats_enabled then
        return false, "solo only"
    end

    local before = read_zenny()
    local added = false

    local _, static_ok = try_static(
        "app.BasicParamUtil",
        { "addMoney(System.Int32, System.Boolean)", "addMoney" },
        amount,
        false
    )
    added = static_ok

    if not added then
        local _, inst_ok = try_call(
            get_basic_param(),
            { "addMoney(System.Int32, System.Boolean)", "addMoney" },
            amount,
            false
        )
        added = inst_ok
    end

    local after = read_zenny()
    if not added then
        return false, "addMoney failed"
    end
    if before ~= nil and after ~= nil and after == before then
        return false, string.format("zenny unchanged (%d)", after)
    end
    return true, string.format("zenny %s -> %s", tostring(before), tostring(after))
end

local function read_points()
    local n, ok = try_static("app.BasicParamUtil", { "getPoint" })
    if ok and type(n) == "number" then
        return n
    end
    n = try_call(get_basic_param(), { "getPoint" })
    if type(n) == "number" then
        return n
    end
    return nil
end

local function add_points(amount)
    amount = amount or 1000
    if not runtime.cheats_enabled then
        return false, "solo only"
    end

    local before = read_points()
    local added = false

    local _, static_ok = try_static(
        "app.BasicParamUtil",
        { "addPoint(System.Int32, System.Boolean)", "addPoint" },
        amount,
        false
    )
    added = static_ok

    if not added then
        local _, inst_ok = try_call(
            get_basic_param(),
            { "addPoint(System.Int32, System.Boolean)", "addPoint" },
            amount,
            false
        )
        added = inst_ok
    end

    local after = read_points()
    if not added then
        return false, "addPoint failed"
    end
    if before ~= nil and after ~= nil and after == before then
        return false, string.format("pts unchanged (%d)", after)
    end
    return true, string.format("pts %s -> %s", tostring(before), tostring(after))
end

-- Shared wallet cooldown. addMoney / addPoint are not safe to spam.
local WALLET_COOLDOWN_MS = 1000

local function wallet_ready()
    return os.clock() >= (runtime.wallet_ready_at or 0)
end

local function run_wallet(add_fn)
    if not wallet_ready() then
        if menu and menu.toast then
            menu:toast("Wait — don't spam wallet adds", "warning", WALLET_COOLDOWN_MS)
        end
        return
    end
    runtime.wallet_ready_at = os.clock() + (WALLET_COOLDOWN_MS / 1000)
    local _, msg = add_fn()
    log_action(msg)
end

local set_global_speed = nil
do
    local app_td = sdk.find_type_definition("via.Application")
    set_global_speed = app_td and app_td:get_method("set_GlobalSpeed")
end

local function apply_play_speed(want)
    local scale = 1.0
    if want then
        scale = as_float(features.move_fast_mult)
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
    if set_global_speed then
        pcall(function()
            set_global_speed:call(nil, scale)
        end)
    end
end

local function apply_god_mode(want)
    if want then
        set_no_damage(true)
        refill_health()
        runtime.god_was_on = true
    elseif runtime.god_was_on then
        set_no_damage(false)
        runtime.god_was_on = false
    end
end

-- Pause-menu Return to Title. Does not re-fire quest clear (that can skip
-- or double rewards). Relies on the last auto-save, same as quitting the game.
local function return_to_title()
    features.move_fast = false
    apply_play_speed(false)
    if set_global_speed then
        pcall(function()
            set_global_speed:call(nil, 1.0)
        end)
    end

    local _, ok = try_static("app.cGUICommonMenu_ReturnTitle", {
        "executeReturntitle",
        "executeReturntitle()",
    })
    if ok then
        log_action("return to title")
        if menu then
            menu:set_open(false)
        end
        return true
    end
    log_action("return to title failed")
    return false
end

menu = RefShell.create({
    id = "mhwilds",
    title = "MH WILDS QOL",
    toggle_vk = 0xC0,
    dock = "right",
    width = 400,
    height = 860,
    start_open = false,
    persist = features,
    host = true,
    lock_camera = true,
    lock_cursor = true,
    show_logs = false,
})

menu.extra_keybinds = function(ui)
    ui.bind_hotkey("Health Bars", features, "health_bars_vk")
    ui.bind_hotkey("Move Fast", features, "move_fast_vk")
    ui.muted("Health Bars and Move Fast are optional. Leave None and use the Gameplay toggles. Function keys are used by the game.")
end

menu:add_tab("Hunter", function(ui)
    local party = runtime.party
    ui.section("Status", function()
        imgui.text("Cheats:")
        imgui.same_line()
        imgui.text_colored(party.label, party.enabled and COL_OK or COL_BAD)
        ui.muted(party.detail)
        ui.kv("Party", string.format("%d hunter%s", party.humans, party.humans == 1 and "" or "s"))
        if runtime.hp and runtime.max_hp then
            ui.kv("HP", string.format("%.0f / %.0f", runtime.hp, runtime.max_hp))
        else
            ui.kv("HP", "—")
        end
        if runtime.stamina and runtime.max_stamina then
            ui.kv("Stamina", string.format("%.0f / %.0f", runtime.stamina, runtime.max_stamina))
        else
            ui.kv("Stamina", "—")
        end
        ui.kv("Sharpness", runtime.sharpness or "—")
        if type(runtime.zenny) == "number" then
            ui.kv("Zenny", string.format("%d", runtime.zenny))
        else
            ui.kv("Zenny", "—")
        end
        if type(runtime.points) == "number" then
            ui.kv("Pts", string.format("%d", runtime.points))
        else
            ui.kv("Pts", "—")
        end
        if runtime.cheats_enabled and features.more_damage then
            ui.kv("Damage", string.format("%.1fx", as_float(features.more_damage_mult)))
        else
            ui.kv("Damage", "off")
        end
        if runtime.cheats_enabled and features.move_fast then
            ui.kv("Play Speed", string.format("%.1fx", as_float(features.move_fast_mult)))
        else
            ui.kv("Play Speed", "off")
        end
        ui.kv("Last action", runtime.last_log)
        ui.muted("~ anytime. Look input pauses while the menu is open.")
    end, true)

    ui.section("Cheats", function()
        ui.bind_toggle("God Mode", features, "god_mode")
        ui.bind_toggle("Infinite Stamina", features, "inf_stamina")
        ui.bind_toggle("Infinite Items", features, "inf_items")
        if features.inf_items then
            ui.muted("Pouch use only. Sell, craft, and ammo still consume.")
        end
        ui.bind_toggle("Free Craft", features, "free_craft")
        if features.free_craft then
            ui.muted("Item recipe list. Missing mats still craft. Materials stay in the pouch.")
        end
        ui.bind_toggle("Always Sharp", features, "always_sharp")
        ui.bind_toggle("More Damage", features, "more_damage")
        ui.bind_combo("Damage", features, "more_damage_mult", DAMAGE_OPTIONS)
        if party.enabled then
            ui.muted("No damage, stamina use, or sharpness loss while on. More Damage scales hits on monsters.")
        else
            ui.muted("Solo only. The toggles are ignored while others are in the party.")
        end
    end, true)

    ui.section("Quick Actions", function()
        ui.actions({
            { "+10000 Zenny", function()
                run_wallet(function()
                    return add_zenny(10000)
                end)
            end },
            { "+999999999 Zenny", function()
                run_wallet(function()
                    return add_zenny(999999999)
                end)
            end },
            { "+1000 Pts", function()
                run_wallet(function()
                    return add_points(1000)
                end)
            end },
            { "+999999999 Pts", function()
                run_wallet(function()
                    return add_points(999999999)
                end)
            end },
        }, 2)
        if party.enabled then
            ui.muted("Wallet add. HUD may wait until pause.")
        else
            ui.muted("Solo only.")
        end
    end, true)
end)

menu:add_tab("Gameplay", function(ui)
    local party = runtime.party
    ui.section("Health Bars", function()
        ui.bind_toggle("Health Bars", features, "health_bars")
        ui.bind_toggle("Show HP text", features, "health_bars_hp_text")
        ui.bind_toggle("Show distance", features, "health_bars_show_dist")
        ui.bind_toggle("Small monsters", features, "health_bars_zako")
        ui.muted("Bosses always. Small monsters stay off unless you turn them on — packs will flood otherwise.")
        ui.bind_combo("Draw distance", features, "health_bars_dist", DIST_OPTIONS)
        ui.bind_combo("Bar scale", features, "health_bars_scale", SCALE_OPTIONS)
        ui.muted("Bosses 2x red. Small monsters 1x teal. Scale multiplies both. Draw distance is the combo above.")
    end, true)

    ui.section("Play Speed", function()
        ui.bind_toggle("Move Fast", features, "move_fast")
        ui.bind_combo("Play Speed", features, "move_fast_mult", SPEED_OPTIONS)
        if party.enabled then
            ui.muted("Speeds locked walks and talk.")
        else
            ui.muted("Solo only. Ignored while others are in the party.")
        end
    end, true)

    ui.section("Recovery", function()
        ui.actions({
            { "Return to Title", function()
                if return_to_title() then
                    menu:toast("Returning to title…", "success", 1200)
                else
                    menu:toast("Return to title failed", "warning", 1200)
                end
            end },
        }, 1)
        ui.muted("If a post-quest menu never opens, this is the pause-menu Return to Title. Turns Move Fast off first. Does not re-clear the quest.")
    end, true)
end)

menu:add_tab("Smithy", function(ui)
    local party = runtime.party
    ui.section("Crafts", function()
        ui.bind_toggle("Free Smithy Crafts", features, "free_smithy")
        if features.free_smithy then
            ui.muted("Weapon tree, hunter armor, Palico sets, and special upgrade. Missing mats still forge. Materials and zenny stay.")
        else
            ui.muted("Forge without spending materials or zenny.")
        end
    end, true)

    ui.section("Unlock", function()
        ui.bind_toggle("Unlock All Armor", features, "unlock_armor")
        if features.unlock_armor then
            ui.muted("Shows every forgeable series. Reopen the armor list or switch rank tab if a row is missing.")
        else
            ui.muted("Show locked hunter armor. Wilds tabs are Low / High rank (MAIN / EX), not Rise Master / Special.")
        end
        ui.bind_toggle("Unlock All Palico Armor", features, "unlock_palico")
        if features.unlock_palico then
            ui.muted("Shows every forgeable Palico series. Switch Low / High if a row is missing.")
        else
            ui.muted("Show locked Palico sets. Same Low / High tabs as hunter armor.")
        end
        ui.bind_toggle("Unlock All Weapons", features, "unlock_weapons")
        if features.unlock_weapons then
            ui.muted("Reveals hidden names (?????) on nodes already on the tree. Does not inject locked story columns.")
        else
            ui.muted("Show hidden weapon names on the existing tree.")
        end
    end, true)

    if not party.enabled then
        ui.muted("Solo only. Ignored while others are in the party.")
    end
end)

local function poll_health_bars_hotkey()
    local vk = features.health_bars_vk
    if type(vk) ~= "number" or vk <= 0x06 then
        runtime.hb_key_down = false
        runtime.hb_vk = vk
        return
    end
    local down = false
    pcall(function()
        down = reframework:is_key_down(vk) and true or false
    end)
    if runtime.hb_vk ~= vk or menu.rebinding then
        runtime.hb_vk = vk
        runtime.hb_key_down = down
        return
    end
    if vk == menu.cfg.toggle_vk then
        runtime.hb_key_down = down
        return
    end
    if down and not runtime.hb_key_down then
        features.health_bars = not features.health_bars
        menu.dirty = true
        if HealthBars then
            HealthBars.enabled = features.health_bars and true or false
            if features.health_bars and HealthBars.kick then
                HealthBars.kick()
            end
        end
        menu:toast(
            features.health_bars and "Health Bars on" or "Health Bars off",
            features.health_bars and "success" or "warning",
            800
        )
    end
    runtime.hb_key_down = down
end

local function poll_move_fast_hotkey()
    local vk = features.move_fast_vk
    if type(vk) ~= "number" or vk <= 0x06 then
        runtime.mf_key_down = false
        runtime.mf_vk = vk
        return
    end
    local down = false
    pcall(function()
        down = reframework:is_key_down(vk) and true or false
    end)
    if runtime.mf_vk ~= vk or menu.rebinding then
        runtime.mf_vk = vk
        runtime.mf_key_down = down
        return
    end
    if vk == menu.cfg.toggle_vk or vk == features.health_bars_vk then
        runtime.mf_key_down = down
        return
    end
    if down and not runtime.mf_key_down then
        if not runtime.cheats_enabled and not features.move_fast then
            menu:toast("Move Fast is solo only", "warning", 800)
        else
            features.move_fast = not features.move_fast
            menu.dirty = true
            menu:toast(
                features.move_fast and ("Move Fast " .. string.format("%.1fx", as_float(features.move_fast_mult))) or
                "Move Fast off",
                features.move_fast and "success" or "warning",
                800
            )
        end
    end
    runtime.mf_key_down = down
end

re.on_frame(function()
    poll_health_bars_hotkey()
    poll_move_fast_hotkey()
    runtime.party = party_status()
    runtime.cheats_enabled = runtime.party.enabled
    runtime.hp, runtime.max_hp = read_hp()
    runtime.stamina, runtime.max_stamina = read_stamina()
    runtime.sharpness = read_sharpness()
    runtime.zenny = read_zenny()
    runtime.points = read_points()
    if HealthBars then
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
    apply_god_mode(runtime.cheats_enabled and features.god_mode)
    apply_inf_stamina(runtime.cheats_enabled and features.inf_stamina)
    apply_inf_items(runtime.cheats_enabled and features.inf_items)
    apply_free_craft(runtime.cheats_enabled and features.free_craft)
    apply_free_smithy(runtime.cheats_enabled and features.free_smithy)
    apply_unlock_armor(runtime.cheats_enabled and features.unlock_armor)
    apply_unlock_palico(runtime.cheats_enabled and features.unlock_palico)
    apply_unlock_weapons(runtime.cheats_enabled and features.unlock_weapons)
    apply_always_sharp(runtime.cheats_enabled and features.always_sharp)
    apply_play_speed(runtime.cheats_enabled and features.move_fast)
end)

re.on_script_reset(function()
    if set_global_speed then
        pcall(function()
            set_global_speed:call(nil, 1.0)
        end)
    end
end)

menu:bind()

-- Old F6/F7/F8 defaults fight Wilds bindings. Move menu to ~ and
-- unbind the optional overlay / speed keys so they stay menu-only.
if menu.cfg.toggle_vk == 0x75 then
    menu.cfg.toggle_vk = 0xC0
    menu.dirty = true
end
if features.health_bars_vk == 0x76 then
    features.health_bars_vk = 0
    menu.dirty = true
end
if features.move_fast_vk == 0x77 then
    features.move_fast_vk = 0
    menu.dirty = true
end
