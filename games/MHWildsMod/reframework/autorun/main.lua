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
    log.error("[mhwilds] refshell.lua missing — put it in reframework/autorun/")
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
}

local features = {
    god_mode = false,
    inf_stamina = false,
    always_sharp = false,
    more_damage = false,
    more_damage_mult = 2.0,
    move_fast = false,
    move_fast_mult = 2.0,
    move_fast_vk = 0,
    health_bars = true,
    health_bars_vk = 0,
    health_bars_dist = 55,
    health_bars_hp_text = true,
    health_bars_show_dist = true,
    health_bars_scale = 1.5,
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
    lock_camera = true,
    lock_cursor = true,
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
        ui.muted("HP text is 5000/5000 on the bar. Distance is how far you are from that monster.")
        ui.bind_combo("Draw distance", features, "health_bars_dist", DIST_OPTIONS)
        ui.bind_combo("Bar scale", features, "health_bars_scale", SCALE_OPTIONS)
        ui.muted("How far a bar still draws. Longer range helps sniping and makes town bleed worse.")
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
        HealthBars.enabled = features.health_bars and true or false
        local dist = features.health_bars_dist
        if type(dist) == "number" then
            HealthBars.max_draw_dist = dist
        end
        HealthBars.show_hp_text = features.health_bars_hp_text ~= false
        HealthBars.show_dist = features.health_bars_show_dist ~= false
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
