-- dmc5_menu.lua
-- Player-facing DMC5 trainer on RefShell. Cheats tab only.

local RefShell = _G.RefShell
if not RefShell then
    local ok, mod = pcall(require, "refshell")
    if ok then
        RefShell = mod
    end
end

if not RefShell then
    log.error("[dmc5_menu] refshell.lua missing — put it in reframework/autorun/")
    return
end

-- app.GauntletID — shop names, not internal enum names.
local BREAKERS = {
    { 0, "Overture" },
    { 1, "Ragtime" },
    { 2, "Helter Skelter" },
    { 3, "Gerbera" },
    { 4, "Punch Line" },
    { 5, "Super Buster" },
    { 6, "Rawhide" },
    { 7, "Tomboy" },
    { 8, "Mega Buster" },
    { 9, "Gerbera GP01" },
    { 10, "Pasta Breaker" },
    { 11, "Sweet Surrender" },
    { 12, "Banana" },
}

local SPEED_OPTIONS = {
    { 1.0, "1x" },
    { 1.5, "1.5x" },
    { 2.0, "2x" },
    { 3.0, "3x" },
    { 5.0, "5x" },
    { 10.0, "10x" },
}

local DAMAGE_OPTIONS = {
    { 1.0, "1x" },
    { 1.5, "1.5x" },
    { 2.0, "2x" },
    { 3.0, "3x" },
    { 5.0, "5x" },
    { 10.0, "10x" },
    { 99.0, "99x" },
}

local features = {
    god_mode = false,
    infinite_dt = false,
    infinite_sdt = false,
    infinite_exceed = false,
    always_color_up = false,
    mega_buster_keep = false,
    move_fast = false,
    move_fast_mult = 2.0,
    more_damage = false,
    more_damage_mult = 2.0,
}

local runtime = {
    last_log = "(none)",
    god_was_on = false,
    speed_was_on = false,
    exceed_was_on = false,
    sdt_was_on = false,
    unlock_sdt = false,
    unlock_super_nero = false,
    super_nero_was_on = false,
    color_up_was_on = false,
    mega_buster_keep_was_on = false,
}

local function log_action(text)
    runtime.last_log = text
    log.info("[dmc5_menu] " .. text)
end

local function get_player_manager()
    return sdk.get_managed_singleton("app.PlayerManager")
        or sdk.get_managed_singleton(sdk.game_namespace("PlayerManager"))
end

local function get_manual_player()
    local playman = get_player_manager()
    if not playman then
        return nil
    end
    return playman:call("get_manualPlayer")
end

-- app.PlayerID: Nero=0 Dante=1 Gilver=2 (V) Vergil=3 VergilPL=4
local function character_kind(player)
    if not player then
        return "none"
    end
    local ok, id = pcall(function()
        return player:call("get_playerID")
    end)
    if ok then
        if id == 0 then
            return "nero"
        end
        if id == 1 then
            return "dante"
        end
        if id == 2 then
            return "v"
        end
        if id == 3 or id == 4 then
            return "vergil"
        end
    end
    return "none"
end

local CHAR_LABEL = {
    none = "—",
    nero = "Nero",
    dante = "Dante",
    v = "V",
    vergil = "Vergil",
}

local function is_nero(player)
    return character_kind(player) == "nero"
end

local function is_vergil(player)
    return character_kind(player) == "vergil"
end

local function is_dante(player)
    return character_kind(player) == "dante"
end

local function is_v(player)
    return character_kind(player) == "v"
end

local function get_component(obj, typename)
    if not obj then
        return nil
    end
    local go = obj
    local ok_td, td = pcall(function()
        return obj:get_type_definition()
    end)
    if ok_td and td and td:get_full_name() ~= "via.GameObject" then
        go = obj:call("get_GameObject")
    end
    if not go then
        return nil
    end
    local typ = sdk.typeof(typename)
    if not typ then
        return nil
    end
    return go:call("getComponent(System.Type)", typ)
end

local function get_hit_controller(character)
    return get_component(character, "app.HitController")
end

local function write_hit_point(hc, value)
    if not hc then
        return false
    end
    local ok = pcall(function()
        hc:set_field("<hitPoint>k__BackingField", value)
    end)
    if ok then
        return true
    end
    ok = pcall(function()
        hc:set_field("hitPoint", value)
    end)
    return ok
end

local function refill_health(player)
    player = player or get_manual_player()
    local hc = get_hit_controller(player)
    if not hc then
        return false, "no HitController"
    end
    local maxhp = hc:call("get_maxHitPoint")
    if not maxhp then
        return false, "no maxHitPoint"
    end
    if write_hit_point(hc, maxhp) then
        return true, string.format("HP -> %.0f", maxhp)
    end
    return false, "could not write hitPoint"
end

local function max_dt(player)
    player = player or get_manual_player()
    if not player then
        return false, "no player"
    end
    local maxg = player:call("get_maxDevilTriggerGauge")
    if not maxg then
        return false, "no max DT"
    end
    player:call("set_devilTriggerGauge", maxg)
    return true, string.format("DT -> %.0f", maxg)
end

-- Sin Devil Trigger. Engine name is TheDevilTrigger / theDTGauge (Dante + Vergil).
-- No max getter — addTheDevilTriggerGauge clamps. Training: TraningSetParam INFINIT=2.
local SDT_FILL = 10000.0

local function has_sdt(player)
    return is_dante(player) or is_vergil(player)
end

local function set_training_infinite_sdt(on)
    local value = on and 2 or 0
    local td = sdk.find_type_definition("app.TrainingManager")
    local method = td and td:get_method("setTrainingInfiniteTheDevil")
    if method then
        pcall(function()
            method:call(nil, value)
        end)
    end
    local tm = sdk.get_managed_singleton("app.TrainingManager")
        or sdk.get_managed_singleton(sdk.game_namespace("TrainingManager"))
    if tm then
        pcall(function()
            tm:call("setTrainingInfiniteTheDevil", value)
        end)
        pcall(function()
            tm:set_field("isInfiniteTheDevil", value)
        end)
        pcall(function()
            tm:set_field("isVergilInfiniteTheDevil", value)
        end)
    end
end

local function max_sdt(player)
    if not player or not has_sdt(player) then
        return false, "no SDT"
    end
    pcall(function()
        player:call("set_theDTGauge", SDT_FILL)
    end)
    pcall(function()
        player:set_field("<theDTGauge>k__BackingField", SDT_FILL)
    end)
    -- DevilTriggerAddType.Special = 3
    pcall(function()
        player:call("addTheDevilTriggerGauge", SDT_FILL, 3)
    end)
    return true, "SDT full"
end

-- Dante SDT is story-gated (Devil Sword Dante / get_isTheDTEnable).
-- Session-only: hook the enable getters and add DSD to this actor's slots.
-- Does not touch GameData / DanteWeaponSUnlock, so the save can still unlock later.
local DANTE_WEAPON_DEVIL_SWORD = 2

local function dante_has_devil_sword(player)
    if not player then
        return false
    end
    local ok, slots = pcall(function()
        return player:call("get_slotWeaponS")
    end)
    if not ok or not slots then
        return false
    end
    local n = slots:call("get_Count")
    if not n then
        return false
    end
    for i = 0, n - 1 do
        if slots:call("get_Item", i) == DANTE_WEAPON_DEVIL_SWORD then
            return true
        end
    end
    return false
end

local function ensure_dante_devil_sword(player)
    if not player or not is_dante(player) then
        return false
    end
    if dante_has_devil_sword(player) then
        return true
    end
    local ok = pcall(function()
        player:call("addSlotWeaponS", DANTE_WEAPON_DEVIL_SWORD)
    end)
    return ok
end

local function hook_sdt_enable(typename)
    local td = sdk.find_type_definition(typename)
    if not td then
        return
    end
    local function force_enable(retval)
        if runtime.unlock_sdt then
            return sdk.to_ptr(true)
        end
        return retval
    end
    local enable = td:get_method("get_isTheDTEnable")
    if enable then
        sdk.hook(enable, function() end, force_enable)
    end
    local check = td:get_method("get_isTheDTGaugeCheck")
    if check then
        sdk.hook(check, function() end, force_enable)
    end
end

hook_sdt_enable("app.PlayerDante")

-- Nero Super Nero only. Flag unlock — do not swap meshes (that hid the head).
-- One-shot mesh restore undoes the leftover Enabled=false from the old swap.
-- DevilTrigger: Human=0 Devil=1 (same as L1 + d-pad up). Majin=2 unused here.
local DT_HUMAN = 0
local DT_DEVIL = 1

local function nero_restore_meshes(player)
    local fields = {
        { "get_cachedDevilMesh", "<cachedDevilMesh>k__BackingField" },
        { "get_cachedHumanMesh", "<cachedHumanMesh>k__BackingField" },
        { "get_cachedHumanArmMesh", "<cachedHumanArmMesh>k__BackingField" },
        { "get_cachedHumanHarnessMesh", "<cachedHumanHarnessMesh>k__BackingField" },
    }
    for _, pair in ipairs(fields) do
        local mesh = nil
        pcall(function()
            mesh = player:call(pair[1]) or player:get_field(pair[2])
        end)
        if mesh then
            pcall(function()
                mesh:call("set_Enabled", true)
            end)
            pcall(function()
                mesh:set_field("Enabled", true)
            end)
            pcall(function()
                local go = mesh:call("get_GameObject")
                if go then
                    go:call("set_DrawSelf", true)
                    go:call("set_UpdateSelf", true)
                end
            end)
        end
    end
end

local function apply_nero_form_unlocks(player)
    if not player or not is_nero(player) then
        return
    end

    if runtime.unlock_super_nero then
        if not runtime.super_nero_was_on then
            nero_restore_meshes(player)
            pcall(function()
                player:call("set_hasDevilPower", true)
                player:call("set_hasDevilPowerNoSync", true)
                player:call("set_isExDevilTrigger", true)
                -- isNotProduction skips the story cutscene
                player:call("setDevilTrigger", DT_DEVIL, true)
            end)
        else
            pcall(function()
                player:call("set_hasDevilPower", true)
                player:call("set_hasDevilPowerNoSync", true)
                player:call("set_isExDevilTrigger", true)
            end)
        end
        runtime.super_nero_was_on = true
    elseif runtime.super_nero_was_on then
        pcall(function()
            player:call("set_isExDevilTrigger", false)
            player:call("setDevilTrigger", DT_HUMAN, true)
        end)
        runtime.super_nero_was_on = false
    end
end

-- Nero Red Queen exceed. Training room flag is isInfiniteExseed (game typo).
-- TraningSetParam: OFF=0 AUTO=1 INFINIT=2. Gauge refill covers story missions.
local function get_exceed_gauge(player)
    player = player or get_manual_player()
    if not player or not (is_nero(player) or is_v(player)) then
        return nil
    end
    local ok, gauge = pcall(function()
        return player:call("get_exceedGaugeManager")
            or player:get_field("<exceedGaugeManager>k__BackingField")
    end)
    if ok then
        return gauge
    end
    return nil
end

local function set_training_infinite_exceed(on)
    local value = on and 2 or 0
    local td = sdk.find_type_definition("app.TrainingManager")
    local method = td and td:get_method("setTrainingInfiniteExseed")
    if method then
        pcall(function()
            method:call(nil, value)
        end)
    end
    local tm = sdk.get_managed_singleton("app.TrainingManager")
        or sdk.get_managed_singleton(sdk.game_namespace("TrainingManager"))
    if tm then
        pcall(function()
            tm:call("setTrainingInfiniteExseed", value)
        end)
        pcall(function()
            tm:set_field("isInfiniteExseed", value)
        end)
    end
end

local function max_exceed(player)
    local gauge = get_exceed_gauge(player)
    if not gauge then
        return false, "no exceed"
    end
    local maxs = gauge:call("get_stockMax")
    if maxs then
        pcall(function()
            gauge:call("setStock", maxs)
        end)
        pcall(function()
            gauge:call("set_Stock", maxs)
        end)
        pcall(function()
            gauge:call("set_exceedLevel", maxs)
        end)
    end
    local gmax = gauge:call("getGaugeMax")
    if gmax then
        gmax = (tonumber(gmax) or 1) * 1.0
        pcall(function()
            gauge:set_field("Now", gmax)
            gauge:set_field("Target", gmax)
        end)
    end
    return true, "exceed full"
end

-- Same Infinite Exceed toggle: Nero Red Queen stocks, Vergil concentration.
-- Playable Vergil is app.PlayerVergilPL (concentGauge / concentLv 0–2).
local function set_training_concentration(level)
    local td = sdk.find_type_definition("app.TrainingManager")
    local method = td and td:get_method("setTrainingConcentrationLevel")
    if method then
        pcall(function()
            method:call(nil, level)
        end)
    end
    local tm = sdk.get_managed_singleton("app.TrainingManager")
        or sdk.get_managed_singleton(sdk.game_namespace("TrainingManager"))
    if tm then
        pcall(function()
            tm:call("setTrainingConcentrationLevel", level)
        end)
        pcall(function()
            tm:set_field("ConcentrationLevel", level)
        end)
    end
end

local function max_concentration(player)
    if not player or not (is_vergil(player) or is_v(player)) then
        return false, "no concentration"
    end
    local maxg = player:call("get_maxConcentGauge")
    if maxg then
        maxg = (tonumber(maxg) or 1) * 1.0
        pcall(function()
            player:call("set_concentGauge", maxg)
        end)
        pcall(function()
            player:set_field("<concentGauge>k__BackingField", maxg)
        end)
        pcall(function()
            player:call("addConcentGauge", maxg, true, 0.0, true)
        end)
    end
    pcall(function()
        player:call("set_concentLv", 2)
    end)
    pcall(function()
        player:call("set_concentRationLevel", 2)
    end)
    set_training_concentration(2)
    return true, "concentration full"
end

-- Nero Blue Rose Color Up. Training flag is isInfiniteBlueRose (OFF=0 INFINIT=2).
-- inifinitBlueRoseTrigger is the in-game name (typo). Shell count stays at the
-- unlocked max (1 before Color Up 2, 3 after) — same UX as Exceed.
local function get_blue_rose(player)
    player = player or get_manual_player()
    if not player or not is_nero(player) then
        return nil
    end
    local ok, rose = pcall(function()
        return player:call("get_cachedBlueRose")
            or player:get_field("<cachedBlueRose>k__BackingField")
    end)
    if ok then
        return rose
    end
    return nil
end

local function set_training_infinite_bluerose(on)
    local value = on and 2 or 0
    local td = sdk.find_type_definition("app.TrainingManager")
    local method = td and td:get_method("setTrainingInfiniteBlueRose")
    if method then
        pcall(function()
            method:call(nil, value)
        end)
    end
    local tm = sdk.get_managed_singleton("app.TrainingManager")
        or sdk.get_managed_singleton(sdk.game_namespace("TrainingManager"))
    if tm then
        pcall(function()
            tm:call("setTrainingInfiniteBlueRose", value)
        end)
        pcall(function()
            tm:set_field("isInfiniteBlueRose", value)
        end)
    end
end

local function apply_always_color_up(player, enabled)
    if not player or not is_nero(player) then
        return false
    end
    pcall(function()
        player:call("set_inifinitBlueRoseTrigger", enabled)
    end)
    pcall(function()
        player:set_field("<inifinitBlueRoseTrigger>k__BackingField", enabled)
    end)
    local charge = player:get_field("BlueRoseCharge")
    if charge then
        pcall(function()
            charge:set_field("Infinity", enabled)
        end)
        if enabled then
            local limit = charge:get_field("LimitLevel")
            if type(limit) == "number" then
                pcall(function()
                    charge:call("set_currentLevel", limit)
                end)
            end
        end
    end
    if enabled then
        local rose = get_blue_rose(player)
        if rose then
            local maxc = rose:call("get_maxShellCount")
            if maxc then
                pcall(function()
                    rose:call("set_shellCount", maxc)
                end)
            end
        end
    end
    set_training_infinite_bluerose(enabled)
    return true
end

local function apply_god(player, enabled)
    local hc = get_hit_controller(player)
    if hc then
        pcall(function()
            hc:call("set_isDamageZero", enabled)
        end)
    end
    if enabled then
        refill_health(player)
    end
end

-- Same path as walking over a world pickup.
local function add_breaker(id, name)
    local player = get_manual_player()
    if not player then
        return false, "no player"
    end
    if not is_nero(player) then
        return false, "breakers are Nero-only"
    end
    local before = player:call("get_gauntletNum")
    local ok = pcall(function()
        player:call("addGauntletFromUI(app.GauntletID)", id)
    end)
    if not ok then
        ok = pcall(function()
            player:call("addGauntlet(app.GauntletID)", id)
        end)
    end
    pcall(function()
        local tmp = player:call("get_neroStatusTmp")
        if tmp then
            tmp:call("add(app.PlayerNero.NeroStatusTmp)", 32) -- Equip
        end
    end)
    if not ok then
        return false, "could not add " .. name
    end
    local after = player:call("get_gauntletNum")
    return true, string.format("%s  stack %s -> %s", name, tostring(before), tostring(after))
end

-- Mega Buster charge shot calls requestGauntletBreak. NoGauntletBreak=8192
-- is the official "do not consume" bit. Only while Mega Buster (GauntletID=8)
-- is equipped so other breakers still explode / swap.
local GAUNTLET_MEGA_BUSTER = 8
local NERO_NO_GAUNTLET_BREAK = 8192
local NERO_BREAK_GAUNTLET = 2048

local function current_gauntlet_id(player)
    if not player then
        return nil
    end
    local id = nil
    pcall(function()
        id = player:call("get_currentGauntletID") or player:call("get_gauntletID")
    end)
    return id
end

local function nero_status_bit(player, flag, on)
    local tmp = nil
    pcall(function()
        tmp = player:call("get_neroStatusTmp")
    end)
    if not tmp then
        return
    end
    if on then
        pcall(function()
            tmp:call("add(app.PlayerNero.NeroStatusTmp)", flag)
        end)
    else
        pcall(function()
            tmp:call("sub(app.PlayerNero.NeroStatusTmp)", flag)
        end)
    end
end

local function apply_mega_buster_keep(player)
    if not player or not is_nero(player) then
        return
    end
    local want = features.mega_buster_keep and current_gauntlet_id(player) == GAUNTLET_MEGA_BUSTER
    nero_status_bit(player, NERO_NO_GAUNTLET_BREAK, want)
    if want then
        nero_status_bit(player, NERO_BREAK_GAUNTLET, false)
    end
end

local function get_game_data()
    local sdm = sdk.get_managed_singleton("app.SaveDataManager")
        or sdk.get_managed_singleton(sdk.game_namespace("SaveDataManager"))
    if not sdm then
        return nil
    end
    local gd = sdm:get_field("GameData")
    if gd then
        return gd
    end
    local ok, value = pcall(function()
        return sdm:call("get_GameData")
    end)
    if ok then
        return value
    end
    return nil
end

local function read_orb_count(inv, gd)
    local live = inv and (inv:call("get_redOrbGetPoint") or inv:get_field("RedOrbGetPoint"))
    local save = gd and gd:get_field("RedOrbCount")
    return live, save
end

-- addRedOrbPoint is (uint point, GameObject targetGo, bool addAchievement).
-- The 1-arg call we used first was a silent no-op (6426570 -> 6426570).
-- Shop / save wallet is GameData.RedOrbCount, not only InventoryManager.
local function add_red_orbs(amount)
    amount = amount or 1000
    local inv = sdk.get_managed_singleton("app.InventoryManager")
        or sdk.get_managed_singleton(sdk.game_namespace("InventoryManager"))
    local gd = get_game_data()
    if not inv and not gd then
        return false, "no InventoryManager / GameData"
    end

    local before_live, before_save = read_orb_count(inv, gd)
    local player = get_manual_player()
    local go = nil
    if player then
        pcall(function()
            go = player:call("get_GameObject")
        end)
    end

    if inv then
        pcall(function()
            inv:call(
                "addRedOrbPoint(System.UInt32, via.GameObject, System.Boolean)",
                amount,
                go,
                false
            )
        end)
    end

    local after_live = inv and (inv:call("get_redOrbGetPoint") or inv:get_field("RedOrbGetPoint"))
    if inv and after_live == before_live then
        local target = (tonumber(before_live) or 0) + amount
        pcall(function()
            inv:set_field("RedOrbGetPoint", target)
        end)
        pcall(function()
            inv:set_field("TemporaryRedOrbGetPoint", target)
        end)
        after_live = inv:call("get_redOrbGetPoint") or inv:get_field("RedOrbGetPoint")
    end

    if gd then
        local target
        if after_live ~= nil and after_live ~= before_live then
            target = after_live
        else
            target = (tonumber(before_save) or 0) + amount
        end
        pcall(function()
            gd:set_field("RedOrbCount", target)
        end)
    end

    return true, string.format(
        "red orbs %s -> %s",
        tostring(before_live),
        tostring(after_live)
    )
end

local function is_cutscene_playing()
    local csm = sdk.get_managed_singleton("app.CutSceneManager")
        or sdk.get_managed_singleton(sdk.game_namespace("CutSceneManager"))
    if not csm then
        return false
    end
    local playing = false
    pcall(function()
        playing = csm:call("get_isCutScenePlaying")
            or csm:call("get_isExclusiveCutScenePlaying")
    end)
    return playing and true or false
end

local function as_float(n)
    return (tonumber(n) or 1) * 1.0
end

-- Do not write Player.MotionSpeed: integer set_field stores int bits (~0) and freezes.
local function apply_play_speed(player, scale)
    if not player then
        return
    end
    scale = as_float(scale)

    local applied = false
    pcall(function()
        local ctrl = player:call("get_animationPlaySpeedControl")
            or player:get_field("<animationPlaySpeedControl>k__BackingField")
        if ctrl then
            ctrl:call("set_speed", scale)
            applied = true
            local cached = ctrl:call("get_cachedMotion")
            if cached then
                cached:call("set_PlaySpeed", scale)
            end
        end
    end)

    if not applied then
        pcall(function()
            local motion = get_component(player, "via.motion.Motion")
            if motion then
                motion:call("set_PlaySpeed", scale)
            end
        end)
    end
end

local function current_play_scale()
    if not features.move_fast or is_cutscene_playing() then
        return 1.0
    end
    return as_float(features.move_fast_mult)
end

local function damage_scale()
    if not features.more_damage then
        return 1.0
    end
    return as_float(features.more_damage_mult)
end

-- calcDamageValueDmgEm = damage applied to an enemy. DmgPl is incoming player hit — leave it.
local function scale_damage_info(info, scale)
    if not info or scale == 1.0 then
        return
    end
    for _, field in ipairs({ "Damage", "FixedDamage" }) do
        local ok, value = pcall(function()
            return info:get_field(field)
        end)
        if ok and value ~= nil then
            pcall(function()
                info:set_field(field, as_float(value) * scale)
            end)
        end
    end
end

local hit_td = sdk.find_type_definition("app.HitController")
local calc_em = hit_td and (
    hit_td:get_method("calcDamageValueDmgEm(app.HitController.DamageInfo)")
    or hit_td:get_method("calcDamageValueDmgEm")
)
if calc_em then
    local pending_info = nil
    sdk.hook(calc_em, function(args)
        pending_info = nil
        if not features.more_damage then
            return
        end
        pending_info = sdk.to_managed_object(args[3])
    end, function(retval)
        if pending_info then
            scale_damage_info(pending_info, damage_scale())
        end
        return retval
    end)
end

local function same_object(a, b)
    if not a or not b then
        return false
    end
    return a == b
end

-- God mode: skip incoming player damage, and keep HitController.isDamageZero on.
local dmg_method = sdk.find_type_definition("app.Player"):get_method("onDamageHit")
if dmg_method then
    sdk.hook(dmg_method, function(args)
        if not features.god_mode then
            return
        end
        local this = sdk.to_managed_object(args[2])
        if same_object(this, get_manual_player()) then
            return sdk.PreHookResult.SKIP_ORIGINAL
        end
    end, function(retval)
        return retval
    end)
end

local nero_td = sdk.find_type_definition("app.PlayerNero")
local request_break = nero_td and (
    nero_td:get_method("requestGauntletBreak(System.Boolean)")
    or nero_td:get_method("requestGauntletBreak")
)
if request_break then
    sdk.hook(request_break, function(args)
        if not features.mega_buster_keep then
            return
        end
        local this = sdk.to_managed_object(args[2])
        if same_object(this, get_manual_player()) and current_gauntlet_id(this) == GAUNTLET_MEGA_BUSTER then
            return sdk.PreHookResult.SKIP_ORIGINAL
        end
    end, function(retval)
        return retval
    end)
end

re.on_pre_application_entry("UpdateBehavior", function()
    local player = get_manual_player()

    if features.god_mode then
        apply_god(player, true)
        runtime.god_was_on = true
    elseif runtime.god_was_on then
        apply_god(player, false)
        runtime.god_was_on = false
    end

    if features.infinite_dt and player then
        max_dt(player)
    end

    if features.infinite_sdt then
        set_training_infinite_sdt(true)
        max_sdt(player)
        runtime.sdt_was_on = true
    elseif runtime.sdt_was_on then
        set_training_infinite_sdt(false)
        runtime.sdt_was_on = false
    end

    if runtime.unlock_sdt then
        ensure_dante_devil_sword(player)
    end

    if runtime.unlock_super_nero or runtime.super_nero_was_on then
        apply_nero_form_unlocks(player)
    end

    if features.infinite_exceed then
        set_training_infinite_exceed(true)
        if is_nero(player) then
            max_exceed(player)
        elseif is_vergil(player) then
            max_concentration(player)
        elseif is_v(player) then
            max_exceed(player)
            max_concentration(player)
        end
        runtime.exceed_was_on = true
    elseif runtime.exceed_was_on then
        set_training_infinite_exceed(false)
        set_training_concentration(0)
        runtime.exceed_was_on = false
    end

    if features.always_color_up then
        apply_always_color_up(player, true)
        runtime.color_up_was_on = true
    elseif runtime.color_up_was_on then
        apply_always_color_up(player, false)
        runtime.color_up_was_on = false
    end

    if features.mega_buster_keep or runtime.mega_buster_keep_was_on then
        apply_mega_buster_keep(player)
        runtime.mega_buster_keep_was_on = features.mega_buster_keep
    end

    if features.move_fast or runtime.speed_was_on then
        apply_play_speed(player, current_play_scale())
        runtime.speed_was_on = features.move_fast
    end
end)

local menu = RefShell.create({
    id = "dmc5",
    title = "DMC5 CHEATS",
    toggle_vk = 0x75,
    dock = "right",
    width = 400,
    height = 900,
    start_open = false,
    persist = features,
})

menu:add_tab("Cheats", function(ui)
    local player = get_manual_player()
    local kind = character_kind(player)

    ui.section("Playing: " .. CHAR_LABEL[kind], function()
        if player then
            local hc = get_hit_controller(player)
            local hp = hc and hc:call("get_hitPoint")
            local maxhp = hc and hc:call("get_maxHitPoint")
            if hp and maxhp then
                ui.kv("HP", string.format("%.0f / %.0f", hp, maxhp))
            end
            if kind == "nero" or kind == "dante" or kind == "vergil" or kind == "v" then
                local dt = player:call("get_devilTriggerGauge")
                local maxdt = player:call("get_maxDevilTriggerGauge")
                if dt and maxdt then
                    ui.kv("DT", string.format("%.0f / %.0f", dt, maxdt))
                end
            end
            if kind == "dante" or kind == "vergil" then
                local sdt = player:call("get_theDTGauge")
                if sdt then
                    ui.kv("SDT", string.format("%.0f", sdt))
                end
            end
            if kind == "nero" then
                local n = player:call("get_gauntletNum")
                if n then
                    ui.kv("Breakers", tostring(n))
                end
                local gauge = get_exceed_gauge(player)
                if gauge then
                    local stock = gauge:call("get_Stock") or gauge:call("getStock")
                    local maxs = gauge:call("get_stockMax")
                    if stock and maxs then
                        ui.kv("Exceed", string.format("%s / %s", tostring(stock), tostring(maxs)))
                    end
                end
                local rose = get_blue_rose(player)
                if rose then
                    local shells = rose:call("get_shellCount")
                    local maxc = rose:call("get_maxShellCount")
                    if shells and maxc then
                        ui.kv("Color Up", string.format("%s / %s", tostring(shells), tostring(maxc)))
                    end
                end
                local ex = player:call("get_isExDevilTrigger")
                if ex ~= nil then
                    ui.kv("Super Nero", ex and "yes" or "no")
                end
            elseif kind == "vergil" or kind == "v" then
                local lv = player:call("get_concentLv") or player:call("get_concentRationLevel")
                local g = player:call("get_concentGauge")
                local maxg = player:call("get_maxConcentGauge")
                if lv then
                    ui.kv(kind == "v" and "Animal Power" or "Concentration", string.format("%s / 2", tostring(lv)))
                end
                if g and maxg then
                    ui.kv(kind == "v" and "Animal gauge" or "Concent gauge", string.format("%.0f / %.0f", g, maxg))
                end
            end
        else
            ui.muted("Enter a mission. Layout follows the character you play.")
        end
        local live_orbs, save_orbs = read_orb_count(
            sdk.get_managed_singleton("app.InventoryManager"),
            get_game_data()
        )
        if live_orbs or save_orbs then
            ui.kv("Red Orbs", string.format("%s  (save %s)", tostring(live_orbs), tostring(save_orbs)))
        end
    end, false)

    ui.section("Shared", function()
        ui.bind_toggle("God Mode", features, "god_mode")
        ui.bind_toggle("Move Fast", features, "move_fast")
        ui.bind_toggle("More Damage", features, "more_damage")
    end, true)

    if kind == "nero" then
        ui.section("Nero", function()
            ui.bind_toggle("Infinite DT", features, "infinite_dt")
            ui.bind_toggle("Infinite Exceed", features, "infinite_exceed")
            ui.bind_toggle("Always Color Up", features, "always_color_up")
            ui.bind_toggle("Mega Buster Keep Charge", features, "mega_buster_keep")
            ui.muted("Charge shot stays. Mega Buster is not destroyed. Other breakers still break.")
            ui.bind_toggle("Unlock Super Nero", runtime, "unlock_super_nero")
            ui.muted("Session only. Finale devil body. The in-game DT bar may stay hidden until the story builds it.")
        end, true)
        ui.section("Devil Breakers", function()
            ui.muted("Adds a breaker the same way a world pickup does.")
            local buttons = {}
            for _, item in ipairs(BREAKERS) do
                local id, name = item[1], item[2]
                buttons[#buttons + 1] = { name, function()
                    local ok, msg = add_breaker(id, name)
                    log_action(msg)
                end }
            end
            ui.actions(buttons, 2)
        end, false)
    elseif kind == "dante" then
        ui.section("Dante", function()
            ui.bind_toggle("Infinite DT", features, "infinite_dt")
            ui.bind_toggle("Infinite SDT", features, "infinite_sdt")
            ui.bind_toggle("Unlock SDT", runtime, "unlock_sdt")
            ui.muted("Session only. Save stays locked so the story beat still unlocks it.")
            ui.muted("Unlocks the form. The SDT bar on the HUD may stay hidden until the story builds it.")
        end, true)
    elseif kind == "vergil" then
        ui.section("Vergil", function()
            ui.bind_toggle("Infinite DT", features, "infinite_dt")
            ui.bind_toggle("Infinite SDT", features, "infinite_sdt")
            ui.bind_toggle("Infinite Concentration", features, "infinite_exceed")
        end, true)
    elseif kind == "v" then
        ui.section("V", function()
            ui.bind_toggle("Infinite DT", features, "infinite_dt")
            ui.bind_toggle("Infinite Animal Power", features, "infinite_exceed")
        end, true)
    end

    ui.section("Character", function()
        ui.muted("Move Fast = play speed. More Damage = hits on enemies.")
        ui.bind_combo("Move Speed", features, "move_fast_mult", SPEED_OPTIONS)
        ui.bind_combo("Damage", features, "more_damage_mult", DAMAGE_OPTIONS)
    end, false)

    ui.section("Quick Actions", function()
        ui.actions({
            { "+10000 Red Orbs", function()
                local ok, msg = add_red_orbs(10000)
                log_action(msg)
            end },
        }, 1)
        ui.spacing()
        ui.kv("Last action", runtime.last_log)
    end, true)
end)

menu:bind()
