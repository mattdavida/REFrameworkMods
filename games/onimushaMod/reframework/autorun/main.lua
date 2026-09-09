-- Onimusha: Way of the Sword QOL on RefShell.
-- ~ toggles. Cursor lock uses the refcursor plugin when present.

local RefShell = _G.RefShell
if not RefShell then
    local ok, mod = pcall(require, "refshell")
    if ok then
        RefShell = mod
    end
end

if not RefShell then
    log.error("[onimusha] refshell missing — run npm run bundle (inlines ../../REFrameworkRefShell)")
    return
end

local COL_OK = 0xFF6EE66E
local COL_WAIT = 0xFF66C8E6

local features = {
    god_mode = false,
    inf_health = false,
    inf_stamina = false,
    inf_oni_power = false,
    inf_oni_change = false,
    inf_items = false,
    easier_issen = false,
    always_issen = false,
    always_deflect = false,
    auto_absorb = false,
    soul_mult_on = false,
    soul_mult = 2.0,
    god_mode_vk = 0,
    inf_health_vk = 0,
    inf_stamina_vk = 0,
    inf_oni_power_vk = 0,
    inf_oni_change_vk = 0,
    inf_items_vk = 0,
    easier_issen_vk = 0,
    always_issen_vk = 0,
    always_deflect_vk = 0,
    auto_absorb_vk = 0,
    soul_mult_on_vk = 0,
    issen_split = false,
}

local menu

local runtime = {
    last_log = "(none)",
    hooked = false,
    player = "—",
    hp = nil,
    max_hp = nil,
    stamina = nil,
    max_stamina = nil,
    oni = nil,
    max_oni = nil,
    oni_change = nil,
    max_oni_change = nil,
    god_was_on = false,
    health_was_on = false,
    stamina_was_on = false,
    oni_was_on = false,
    oni_change_was_on = false,
    items_was_on = false,
    item_hooks = false,
    just_hooks = false,
    pouch = nil,
    god_hooks = false,
    absorb_hooks = false,
    absorb_was_on = false,
    souls_ready = false,
    soul_hooks = false,
}

local function log_action(text)
    runtime.last_log = text
    local L = RefShell and RefShell.Log
    if L and L.info then
        L.info("onimusha", text)
        return
    end
    log.info("[onimusha] " .. text)
end

local function try_call(obj, name, ...)
    if not obj then
        return nil
    end
    local n = select("#", ...)
    local a, b, c, d, e = ...
    local ok, result = pcall(function()
        if n >= 5 then
            return obj:call(name, a, b, c, d, e)
        end
        if n >= 4 then
            return obj:call(name, a, b, c, d)
        end
        if n >= 3 then
            return obj:call(name, a, b, c)
        end
        if n >= 2 then
            return obj:call(name, a, b)
        end
        if n >= 1 then
            return obj:call(name, a)
        end
        return obj:call(name)
    end)
    if ok then
        return result
    end
    return nil
end

local function enum_value(type_name, field_name)
    local td = sdk.find_type_definition(type_name)
    if not td then
        return nil
    end
    local field = td:get_field(field_name)
    if not field then
        return nil
    end
    local ok, value = pcall(function()
        return field:get_data(nil)
    end)
    if ok then
        return value
    end
    return nil
end

local function try_field(obj, name)
    if not obj then
        return nil
    end
    local ok, result = pcall(function()
        return obj:get_field(name)
    end)
    if ok then
        return result
    end
    return nil
end

local function obj_type(obj)
    if obj == nil then
        return "nil"
    end
    local ok, td = pcall(function()
        return obj:get_type_definition()
    end)
    if ok and td then
        local ok_name, name = pcall(function()
            return td:get_full_name()
        end)
        if ok_name and name then
            return name
        end
    end
    return type(obj)
end

local function try_any(obj, names, ...)
    if not obj then
        return nil
    end
    for _, name in ipairs(names) do
        local result = try_call(obj, name, ...)
        if result ~= nil then
            return result
        end
    end
    return nil
end

local function try_static(type_name, names, ...)
    local td = sdk.find_type_definition(type_name)
    if not td then
        return nil
    end
    local a = ...
    for _, name in ipairs(names) do
        local method = td:get_method(name)
        if method then
            local ok, result = pcall(function()
                if a ~= nil then
                    return method:call(nil, a)
                end
                return method:call(nil)
            end)
            if ok and result ~= nil then
                return result
            end
        end
    end
    return nil
end

local function is_managed(obj)
    if obj == nil then
        return false
    end
    local ok, td = pcall(function()
        return obj:get_type_definition()
    end)
    return ok and td ~= nil
end

local function to_managed(ptr)
    if ptr == nil then
        return nil
    end
    local ok, obj = pcall(sdk.to_managed_object, ptr)
    if ok and obj ~= nil then
        return obj
    end
    return nil
end

local function is_type(obj, name)
    if not is_managed(obj) then
        return false
    end
    local ok, td = pcall(function()
        return obj:get_type_definition()
    end)
    return ok and td and td:get_full_name() == name
end

local function get_player_info()
    local pm = sdk.get_managed_singleton("app.PlayerManager")
    local info = try_any(pm, {
        "getControllingPlayer",
        "getControllingPlayerInfo",
        "getMasterPlayer",
        "get_MasterPlayer",
    })
    if is_managed(info) then
        return info
    end
    return nil
end

local function get_player_character(info)
    local chara = try_static("app.PlayerUtil", { "getControllingPlayerCharacter" })
    if is_managed(chara) then
        return chara
    end
    info = info or get_player_info()
    chara = try_any(info, { "get_Character", "get_Hunter" })
    if is_managed(chara) then
        return chara
    end
    return nil
end

local function get_player_entity(info)
    local entity = try_static("app.PlayerUtil", { "getControllingPlayerCharacterEntity" })
    if is_managed(entity) then
        return entity
    end
    info = info or get_player_info()
    entity = try_any(info, { "get_CharacterEntity" })
        or try_field(info, "<CharacterEntity>k__BackingField")
    if is_managed(entity) then
        return entity
    end
    local chara = get_player_character(info)
    entity = try_field(chara, "_PlayerCharacterEntity")
        or try_any(chara, { "get_PlayerCharacterEntity" })
    if is_managed(entity) then
        return entity
    end
    return nil
end

local function get_invincible(entity)
    entity = entity or get_player_entity()
    local inv = try_any(entity, { "get_InvincibleSupporter" })
        or try_field(entity, "<InvincibleSupporter>k__BackingField")
    if is_managed(inv) then
        return inv
    end
    return nil
end

local function find_health_on(obj)
    if not is_managed(obj) then
        return nil
    end
    local mgr = try_any(obj, { "get_HealthManager", "get_HealthMgr" })
        or try_field(obj, "<HealthManager>k__BackingField")
    if is_managed(mgr) then
        return mgr
    end
    return nil
end

local function get_health_mgr(info)
    info = info or get_player_info()
    local mgr = find_health_on(info)
        or find_health_on(get_player_character(info))
        or find_health_on(get_player_entity(info))
    if mgr then
        return mgr
    end

    local chara = get_player_character(info)
    mgr = find_health_on(try_any(chara, { "get_Context", "get_ContextParam", "get_Param" }))
    if mgr then
        return mgr
    end

    local holder = try_any(info, { "get_ContextHolder" })
        or try_field(info, "_ContextHolder")
        or try_any(chara, { "get_ContextHolder" })
        or try_field(chara, "_ContextHolder")
    mgr = find_health_on(holder)
        or find_health_on(try_field(holder, "_ContextCore"))
        or find_health_on(try_any(holder, { "get_ContextCore" }))
    if mgr then
        return mgr
    end

    local contexts = try_field(holder, "Contexts") or try_any(holder, { "get_Contexts" })
    if contexts then
        local ok, n = pcall(function()
            return contexts:get_size()
        end)
        if ok and type(n) == "number" then
            for i = 0, n - 1 do
                local ctx = nil
                pcall(function()
                    ctx = contexts:get_element(i)
                end)
                if ctx == nil then
                    pcall(function()
                        ctx = contexts[i]
                    end)
                end
                mgr = find_health_on(ctx)
                if mgr then
                    return mgr
                end
            end
        end
    end

    local go = try_static("app.PlayerUtil", { "getControllingPlayerGameObject" })
        or try_any(info, { "get_Object" })
        or try_field(info, "<Object>k__BackingField")
    local td = sdk.find_type_definition("app.cHealthManager")
    if go and td then
        local rt = nil
        pcall(function()
            rt = sdk.typeof("app.cHealthManager")
        end)
        if not rt then
            pcall(function()
                rt = td:get_runtime_type()
            end)
        end
        if rt then
            mgr = try_call(go, "getComponent(System.Type)", rt)
            if is_managed(mgr) then
                return mgr
            end
        end
    end
    return nil
end

local function read_hp()
    local mgr = get_health_mgr()
    if not mgr then
        return nil, nil
    end
    local hp = try_any(mgr, { "get_Health", "get_TotalHealth" })
    local max_hp = try_any(mgr, { "get_MaxHealth", "get_TotalMaxHealth" })
    if type(hp) == "number" and type(max_hp) == "number" then
        return hp, max_hp
    end
    return nil, nil
end

local function refill_health()
    local mgr = get_health_mgr()
    if not mgr then
        return false
    end
    local max_hp = try_any(mgr, { "get_MaxHealth", "get_TotalMaxHealth" })
    if type(max_hp) ~= "number" then
        return false
    end
    pcall(function()
        mgr:call("setHealth", max_hp)
    end)
    pcall(function()
        mgr:call("set_Health", max_hp)
    end)
    return true
end

local function no_hit_fixed()
    return enum_value("app.PlayerNoHitLevel.TYPE_Fixed", "NO_HIT") or 7308
end

local function set_no_damage(on)
    local inv = get_invincible()
    if not inv then
        return false
    end
    if on then
        local level = no_hit_fixed()
        pcall(function()
            inv:call("requestNoHit", level)
        end)
        pcall(function()
            inv:call("requestHighestNoHit")
        end)
        pcall(function()
            inv:set_field("_RequestNoHitLevel", level)
        end)
        pcall(function()
            inv:set_field("_CurrentNoHitLevel", level)
        end)
    else
        pcall(function()
            inv:set_field("_RequestNoHitLevel", 0)
        end)
        pcall(function()
            inv:set_field("_CurrentNoHitLevel", 0)
        end)
    end
    return true
end

local function is_player_invincible(this)
    if not this then
        return false
    end
    local ok, td = pcall(function()
        return this:get_type_definition()
    end)
    return ok and td and td:get_full_name() == "app.cPlayerInvincibleSupporter"
end

local function hook_check_no_hit(method)
    if not method then
        return
    end
    local force = false
    pcall(sdk.hook, method, function(args)
        force = false
        if not features.god_mode then
            return
        end
        if not is_player_invincible(to_managed(args[2])) then
            return
        end
        force = true
        return sdk.PreHookResult.SKIP_ORIGINAL
    end, function(retval)
        if force then
            return sdk.to_ptr(1)
        end
        return retval
    end)
end

local function install_god_hooks()
    if runtime.god_hooks then
        return
    end
    local player_td = sdk.find_type_definition("app.cPlayerInvincibleSupporter")
    if not player_td then
        return
    end
    runtime.god_hooks = true
    hook_check_no_hit(player_td:get_method("checkNoHit"))
    hook_check_no_hit(
        player_td:get_method("checkNoHit(app.PlayerNoHitLevel.TYPE_Fixed, app.HitInfo)")
    )
    local base_td = sdk.find_type_definition("app.cCharacterInvincibleSupporter")
    if base_td then
        hook_check_no_hit(base_td:get_method("checkNoHit"))
        hook_check_no_hit(base_td:get_method("checkNoHit(app.HitInfo)"))
    end
end

local function apply_god_mode(want)
    install_god_hooks()
    if want then
        local first = not runtime.god_was_on
        local ok = set_no_damage(true)
        refill_health()
        runtime.god_was_on = true
        if first and ok then
            log_action("god mode on")
        end
        return ok
    elseif runtime.god_was_on then
        set_no_damage(false)
        runtime.god_was_on = false
        log_action("god mode off")
    end
    return true
end

local function get_context_holder(info)
    info = info or get_player_info()
    local holder = try_any(info, { "get_ContextHolder" })
        or try_field(info, "_ContextHolder")
    if is_managed(holder) then
        return holder
    end
    local chara = get_player_character(info)
    holder = try_any(chara, { "get_ContextHolder" })
        or try_field(chara, "_ContextHolder")
    if is_managed(holder) then
        return holder
    end
    local entity = get_player_entity(info)
    holder = try_any(entity, { "get_ContextHolder" })
        or try_field(entity, "_ContextHolder")
    if is_managed(holder) then
        return holder
    end
    return nil
end

local function get_player_context(info)
    info = info or get_player_info()
    local ctx = try_any(info, { "get_Context", "get_ContextParam", "get_Param" })
    if is_type(ctx, "app.cPlayerContextParam") then
        return ctx
    end
    local chara = get_player_character(info)
    ctx = try_any(chara, { "get_Context", "get_ContextParam", "get_Param" })
    if is_type(ctx, "app.cPlayerContextParam") then
        return ctx
    end
    local holder = get_context_holder(info)
    ctx = try_any(holder, { "get_Player" })
    if is_type(ctx, "app.cPlayerContextParam") then
        return ctx
    end
    local contexts = try_field(holder, "Contexts") or try_any(holder, { "get_Contexts" })
    if contexts then
        local ok, n = pcall(function()
            return contexts:get_size()
        end)
        if ok and type(n) == "number" then
            for i = 0, n - 1 do
                local item = nil
                pcall(function()
                    item = contexts:get_element(i)
                end)
                if item == nil then
                    pcall(function()
                        item = contexts[i]
                    end)
                end
                if is_type(item, "app.cPlayerContextParam") then
                    return item
                end
            end
        end
    end
    return nil
end

local function read_oni()
    local ctx = get_player_context()
    if not ctx then
        return nil, nil
    end
    local cur = try_any(ctx, { "get_OniEnergy" })
        or try_field(ctx, "<OniEnergy>k__BackingField")
    local max_oni = try_any(ctx, { "get_OniEnergyMax" })
        or try_field(ctx, "<OniEnergyMax>k__BackingField")
    if type(cur) == "number" and type(max_oni) == "number" then
        return cur, max_oni
    end
    return nil, nil
end

local function refill_oni()
    local ctx = get_player_context()
    if not ctx then
        return false
    end
    local ok = pcall(function()
        ctx:call("setOniEnergyToMax")
    end)
    if ok then
        return true
    end
    local max_oni = try_any(ctx, { "get_OniEnergyMax" })
        or try_field(ctx, "<OniEnergyMax>k__BackingField")
    if type(max_oni) ~= "number" then
        return false
    end
    pcall(function()
        ctx:call("setOniEnergy", max_oni)
    end)
    pcall(function()
        ctx:set_field("<OniEnergy>k__BackingField", max_oni)
    end)
    return true
end

-- Purple souls fill OniChangeEnergy on the same context. Max = ultimate transform.
local function read_oni_change()
    local ctx = get_player_context()
    if not ctx then
        return nil, nil
    end
    local cur = try_any(ctx, { "get_OniChangeEnergy" })
        or try_field(ctx, "<OniChangeEnergy>k__BackingField")
    local max_chg = try_any(ctx, { "get_OniChangeEnergyMax" })
        or try_field(ctx, "<OniChangeEnergyMax>k__BackingField")
    if type(cur) == "number" and type(max_chg) == "number" then
        return cur, max_chg
    end
    return nil, nil
end

local function refill_oni_change()
    local ctx = get_player_context()
    if not ctx then
        return false
    end
    local max_chg = try_any(ctx, { "get_OniChangeEnergyMax" })
        or try_field(ctx, "<OniChangeEnergyMax>k__BackingField")
    if type(max_chg) ~= "number" then
        return false
    end
    local ok = pcall(function()
        ctx:call("setOniChangeEnergy", max_chg)
    end)
    if not ok then
        pcall(function()
            ctx:call("setOniChangeEnergy", max_chg, true)
        end)
        pcall(function()
            ctx:call("set_OniChangeEnergy", max_chg)
        end)
    end
    pcall(function()
        ctx:set_field("<OniChangeEnergy>k__BackingField", max_chg)
    end)
    return true
end

local function find_rikido_on(obj)
    if not is_managed(obj) then
        return nil
    end
    local sup = try_any(obj, { "get_RikidoSupporter" })
        or try_field(obj, "<RikidoSupporter>k__BackingField")
    if is_managed(sup) then
        return sup
    end
    return nil
end

local function get_rikido_supporter(info)
    info = info or get_player_info()
    local sup = find_rikido_on(get_player_entity(info))
        or find_rikido_on(get_player_character(info))
        or find_rikido_on(info)
        or find_rikido_on(get_player_context(info))
    if sup then
        return sup
    end
    local holder = get_context_holder(info)
    sup = find_rikido_on(holder)
        or find_rikido_on(try_any(holder, { "get_ContextCore" }))
        or find_rikido_on(try_field(holder, "_ContextCore"))
    if sup then
        return sup
    end
    local contexts = try_field(holder, "Contexts") or try_any(holder, { "get_Contexts" })
    if contexts then
        local ok, n = pcall(function()
            return contexts:get_size()
        end)
        if ok and type(n) == "number" then
            for i = 0, n - 1 do
                local ctx = nil
                pcall(function()
                    ctx = contexts:get_element(i)
                end)
                if ctx == nil then
                    pcall(function()
                        ctx = contexts[i]
                    end)
                end
                sup = find_rikido_on(ctx)
                if sup then
                    return sup
                end
            end
        end
    end
    return nil
end

local function get_rikido_gauge(sup)
    sup = sup or get_rikido_supporter()
    local gauge = try_any(sup, { "get_Guage", "get_Gauge", "get_Rikido" })
        or try_field(sup, "_Guage")
    if is_managed(gauge) then
        return gauge
    end
    return nil
end

local function read_stamina()
    local sup = get_rikido_supporter()
    if not sup then
        return nil, nil
    end
    local cur = try_any(sup, { "getRikidoValue" })
    local max_st = try_any(sup, { "getRikidoMaxValue" })
    local gauge = get_rikido_gauge(sup)
    if type(cur) ~= "number" then
        cur = try_any(gauge, { "get_CurrentValue" }) or try_field(gauge, "_CurrentValue")
    end
    if type(max_st) ~= "number" then
        max_st = try_any(gauge, { "get_MaxValue" }) or try_field(gauge, "_MaxValue")
    end
    if type(cur) == "number" and type(max_st) == "number" then
        return cur, max_st
    end
    return nil, nil
end

local function refill_stamina()
    local sup = get_rikido_supporter()
    if not sup then
        return false
    end
    pcall(function()
        sup:call("setRikidoValueFromRate", 1.0)
    end)
    local gauge = get_rikido_gauge(sup)
    local max_st = try_any(sup, { "getRikidoMaxValue" })
        or try_any(gauge, { "get_MaxValue" })
        or try_field(gauge, "_MaxValue")
    if type(max_st) == "number" then
        local value = math.floor(max_st + 0.5)
        pcall(function()
            gauge:call("setValue", value, true)
        end)
        pcall(function()
            gauge:set_field("_CurrentValue", value)
        end)
        pcall(function()
            sup:call("addRecoveryValue", value, true)
        end)
    end
    return true
end

local function apply_inf_health(want)
    if want then
        local first = not runtime.health_was_on
        local ok = refill_health()
        runtime.health_was_on = true
        if first and ok then
            log_action("infinite health on")
        end
        return ok
    elseif runtime.health_was_on then
        runtime.health_was_on = false
        log_action("infinite health off")
    end
    return true
end

local function apply_inf_stamina(want)
    if want then
        local first = not runtime.stamina_was_on
        local ok = refill_stamina()
        runtime.stamina_was_on = true
        if first and ok then
            log_action("infinite stamina on")
        end
        return ok
    elseif runtime.stamina_was_on then
        runtime.stamina_was_on = false
        log_action("infinite stamina off")
    end
    return true
end

local function apply_inf_oni(want)
    if want then
        local first = not runtime.oni_was_on
        local ok = refill_oni()
        runtime.oni_was_on = true
        if first and ok then
            log_action("oni power on")
        end
        return ok
    elseif runtime.oni_was_on then
        runtime.oni_was_on = false
        log_action("oni power off")
    end
    return true
end

local function apply_inf_oni_change(want)
    if want then
        local first = not runtime.oni_change_was_on
        local ok = refill_oni_change()
        runtime.oni_change_was_on = true
        if first and ok then
            log_action("oni change on")
        end
        return ok
    elseif runtime.oni_change_was_on then
        runtime.oni_change_was_on = false
        log_action("oni change off")
    end
    return true
end

local function get_item_helper()
    local sdm = sdk.get_managed_singleton("app.SaveDataManager")
    local helper = try_any(sdm, { "get_Helper", "get_SaveDataHelper" })
        or try_field(sdm, "_Helper")
    local item = try_any(helper, { "get_Item" }) or try_field(helper, "_Item")
    if is_type(item, "app.SaveDataHelper_Item") then
        return item
    end
    item = try_any(sdm, { "get_Item" }) or try_field(sdm, "_Item")
    if is_type(item, "app.SaveDataHelper_Item") then
        return item
    end
    return nil
end

local function read_pouch()
    -- ItemUtil.getHaveMedicineBag AVs on the title screen. Wait for a save helper.
    local helper = get_item_helper()
    if not helper then
        return nil
    end
    local bag_id = try_static("app.ItemUtil", { "getHaveMedicineBag" })
    if type(bag_id) ~= "number" or bag_id <= 0 then
        return nil
    end
    local count = try_call(helper, "getMedicineBagCount", bag_id)
    if type(count) == "number" then
        return count
    end
    return nil
end

local function refill_pouch()
    local ok = pcall(function()
        local td = sdk.find_type_definition("app.ItemUtil")
        local method = td and td:get_method("forceFullReloadHaveMedicineBag")
        if method then
            method:call(nil)
        end
    end)
    return ok
end

local function remaining_after_skip(args)
    local item = to_managed(args[3])
    if is_managed(item) then
        local n = try_any(item, { "get_EquipNum" })
            or try_field(item, "<EquipNum>k__BackingField")
        if type(n) == "number" then
            return n
        end
    end
    local this = to_managed(args[2])
    local id = sdk.to_int64(args[3])
    if this and type(id) == "number" then
        local data = try_call(this, "getItem", id)
        local n = try_any(data, { "get_EquipNum" })
            or try_field(data, "<EquipNum>k__BackingField")
        if type(n) == "number" then
            return n
        end
    end
    return 1
end

local function hook_skip_consume(method, returns_count)
    if not method then
        return
    end
    local force = false
    local remain = 1
    pcall(sdk.hook, method, function(args)
        force = false
        if not features.inf_items then
            return
        end
        force = true
        if returns_count then
            remain = remaining_after_skip(args)
        end
        return sdk.PreHookResult.SKIP_ORIGINAL
    end, function(retval)
        if force and returns_count then
            return sdk.to_ptr(remain)
        end
        return retval
    end)
end

local function install_item_hooks()
    if runtime.item_hooks then
        return
    end
    local td = sdk.find_type_definition("app.SaveDataHelper_Item")
    if not td then
        return
    end
    runtime.item_hooks = true
    hook_skip_consume(td:get_method("subItem"), true)
    hook_skip_consume(td:get_method("subItem(System.Int32, System.UInt32, System.Boolean)"), true)
    hook_skip_consume(td:get_method("subItemNum"), true)
    hook_skip_consume(
        td:get_method("subItemNum(app.SaveDataHelper_Item.cItemData, System.UInt32, System.Boolean)"),
        true
    )
    hook_skip_consume(td:get_method("subItemHasObtainNum"), false)
end

local function apply_inf_items(want)
    install_item_hooks()
    if want then
        local first = not runtime.items_was_on
        refill_pouch()
        runtime.items_was_on = true
        if first then
            log_action("infinite items on")
        end
        return true
    elseif runtime.items_was_on then
        runtime.items_was_on = false
        log_action("infinite items off")
    end
    return true
end

local JF_COUNTER_ISSEN = 0
local JF_BLOCK = 2
local GRADE_SUCCESS_GREAT = 1
local CHAIN_INPUT_SUCCESS = 1

local SOUL_MULT_OPTIONS = {
    { 1.0,  "1x" },
    { 1.5,  "1.5x" },
    { 2.0,  "2x" },
    { 3.0,  "3x" },
    { 5.0,  "5x" },
    { 10.0, "10x" },
}

local function as_float(value)
    local n = tonumber(value)
    if not n then
        return 1.0
    end
    return n
end

local function soul_scale()
    if not features.soul_mult_on then
        return 1.0
    end
    local n = as_float(features.soul_mult)
    if n <= 0 then
        return 1.0
    end
    return n
end

local function hook_force_bool(method, should_force, value)
    if not method then
        return
    end
    local force = false
    pcall(sdk.hook, method, function()
        force = false
        if not should_force() then
            return
        end
        force = true
        return sdk.PreHookResult.SKIP_ORIGINAL
    end, function(retval)
        if force then
            return sdk.to_ptr(value and 1 or 0)
        end
        return retval
    end)
end

local function just_type_from_args(args)
    local ok, value = pcall(function()
        return sdk.to_int64(args[3])
    end)
    if ok and value ~= nil then
        return tonumber(value)
    end
    return nil
end

local function get_guard_controller(entity)
    entity = entity or get_player_entity()
    local gc = try_any(entity, { "get_GuardController" })
        or try_field(entity, "<GuardController>k__BackingField")
    if is_managed(gc) then
        return gc
    end
    return nil
end

local function is_block_held(entity)
    entity = entity or get_player_entity()
    local gc = get_guard_controller(entity)
    if is_managed(gc) then
        if try_any(gc, { "get_IsGuard" }) then
            return true
        end
        if try_field(gc, "_IsGuardButton") then
            return true
        end
    end
    if try_any(entity, { "isGuardStance" }) then
        return true
    end
    return false
end

local function deflect_active(entity)
    return features.always_deflect and is_block_held(entity)
end

local function issen_assist()
    return features.easier_issen or features.always_issen
end

local function want_just_type(jf_type)
    if jf_type == JF_COUNTER_ISSEN then
        return issen_assist()
    end
    if jf_type == JF_BLOCK then
        return deflect_active()
    end
    return false
end

local function hook_check_grade(method)
    if not method then
        return
    end
    local force = false
    pcall(sdk.hook, method, function(args)
        force = false
        if want_just_type(just_type_from_args(args)) then
            force = true
            return sdk.PreHookResult.SKIP_ORIGINAL
        end
    end, function(retval)
        if force then
            return sdk.to_ptr(GRADE_SUCCESS_GREAT)
        end
        return retval
    end)
end

local function install_just_hooks()
    if runtime.just_hooks then
        return
    end
    runtime.just_hooks = true

    local jf = sdk.find_type_definition("app.cPlayerJustFrameUpdater")
    if jf then
        hook_check_grade(jf:get_method("checkGrade"))
        hook_check_grade(jf:get_method("checkGradeForShell"))
    end

    local sensor = sdk.find_type_definition("app.cPlayerIssenSensorController")
    if sensor then
        hook_force_bool(sensor:get_method("getIssenSuccess"), function()
            return issen_assist()
        end, true)
    end

    local guard = sdk.find_type_definition("app.cPlayerJustGuardSupporter")
    if guard then
        hook_force_bool(guard:get_method("isCheckJustGuard"), function()
            return deflect_active()
        end, true)
        hook_force_bool(guard:get_method("isCheckShellJustGuard"), function()
            return deflect_active()
        end, true)
        local grade = guard:get_method("getJustGuardGrade")
        if grade then
            local force = false
            pcall(sdk.hook, grade, function()
                force = false
                if not deflect_active() then
                    return
                end
                force = true
                return sdk.PreHookResult.SKIP_ORIGINAL
            end, function(retval)
                if force then
                    return sdk.to_ptr(GRADE_SUCCESS_GREAT)
                end
                return retval
            end)
        end
    end

    local chain = sdk.find_type_definition("app.cPlayerChainIssenSupporter")
    if chain then
        hook_force_bool(chain:get_method("isChainIssenDetectionInput"), function()
            return issen_assist()
        end, true)
        hook_force_bool(chain:get_method("isChainIssenStartActionSuccess"), function()
            return issen_assist()
        end, true)
        hook_force_bool(chain:get_method("isChainIssenFail"), function()
            return issen_assist()
        end, false)
    end
end

local function just_is_active(updater, jf_type)
    if not updater then
        return false
    end
    local active = false
    pcall(function()
        active = updater:call("isActive", jf_type) and true or false
    end)
    return active
end

local function hold_just_input(updater, jf_type)
    if not updater then
        return
    end
    if not just_is_active(updater, jf_type) then
        pcall(function()
            updater:call("enableParam", jf_type)
        end)
    end
    pcall(function()
        updater:call("forceEnableInput", jf_type)
    end)
    pcall(function()
        updater:call("setInputOn", jf_type)
    end)
end

local function get_issen_sensor(entity)
    entity = entity or get_player_entity()
    local sensor = try_any(entity, { "get_IssenSensor" })
        or try_field(entity, "<IssenSensor>k__BackingField")
    if is_managed(sensor) then
        return sensor
    end
    return nil
end

local function issen_has_target(entity)
    local sensor = get_issen_sensor(entity)
    if not is_managed(sensor) then
        return false
    end
    if try_any(sensor, { "getTargetContext" }) then
        return true
    end
    local info = try_any(sensor, { "get_SelectInfo" })
        or try_field(sensor, "<SelectInfo>k__BackingField")
    if not is_managed(info) then
        return false
    end
    return try_any(info, { "get_TargetObject", "get_TargetContext" }) ~= nil
end

local function poke_chain_issen(entity)
    local chain = try_any(entity, { "get_ChainIssenSuporter", "get_ChainIssenSupporter" })
        or try_field(entity, "<ChainIssenSuporter>k__BackingField")
    local detect = try_any(chain, {
        "isChainIssenDetectionStart",
        "isChainIssenDetectionInput",
    }) or try_field(chain, "IsDetection")
    if not detect then
        return
    end
    pcall(function()
        chain:set_field("_InputChainIssen", true)
        chain:set_field("_ChainIssenJustSuccessTiming", true)
        chain:set_field("_CounterIssenJustSuccess", true)
        chain:set_field("<InputState>k__BackingField", CHAIN_INPUT_SUCCESS)
    end)
end

local function apply_just_actions()
    install_just_hooks()
    if not (features.easier_issen or features.always_issen or features.always_deflect) then
        return
    end
    local entity = get_player_entity()
    local updater = try_any(entity, { "get_JustFrameUpdater" })
        or try_field(entity, "<JustFrameUpdater>k__BackingField")
    if features.always_issen and not is_block_held(entity) then
        if just_is_active(updater, JF_COUNTER_ISSEN) or issen_has_target(entity) then
            hold_just_input(updater, JF_COUNTER_ISSEN)
        end
        poke_chain_issen(entity)
    elseif features.easier_issen then
        poke_chain_issen(entity)
    end
    if deflect_active(entity) then
        hold_just_input(updater, JF_BLOCK)
    end
end

local function get_soul_absorption(info)
    local entity = get_player_entity(info)
    local sup = try_any(entity, { "get_SoulAbsorption" })
        or try_field(entity, "<SoulAbsorption>k__BackingField")
    if is_type(sup, "app.cPlayerSoulAbsorptionSupporter") then
        return sup
    end
    local chara = get_player_character(info)
    sup = try_any(chara, { "get_SoulAbsorption" })
        or try_field(chara, "<SoulAbsorption>k__BackingField")
    if is_type(sup, "app.cPlayerSoulAbsorptionSupporter") then
        return sup
    end
    return nil
end

local function get_equip_skill_cache(info)
    local entity = get_player_entity(info)
    local go = try_any(entity, { "get_GameObjectSupporter" })
        or try_field(entity, "<GameObjectSupporter>k__BackingField")
    local cache = try_any(go, { "get_EquipSkillCache" })
        or try_field(go, "_EquipSkillCache")
    if is_type(cache, "app.user_data.cPlayerEquipSkill") then
        return cache
    end
    return nil
end

local function list_count(list)
    if not is_managed(list) then
        return 0
    end
    local n = try_any(list, { "get_Count", "get_Size" })
    if type(n) == "number" then
        return n
    end
    local ok, size = pcall(function()
        return list:get_size()
    end)
    if ok and type(size) == "number" then
        return size
    end
    return 0
end

local function list_item(list, index)
    local item = nil
    pcall(function()
        item = list:call("get_Item", index)
    end)
    if item == nil then
        pcall(function()
            item = list:get_element(index)
        end)
    end
    if item == nil then
        pcall(function()
            item = list[index]
        end)
    end
    return item
end

local function active_soul_count()
    local sm = sdk.get_managed_singleton("app.SoulManager")
    local n = try_any(sm, { "get_ActiveSoulCount" })
        or try_field(sm, "<ActiveSoulCount>k__BackingField")
    if type(n) == "number" then
        return n
    end
    return list_count(try_field(sm, "_ActiveSoulList"))
end

-- Souls on screen, or any active soul if InScreen cannot be read.
local function souls_are_absorbable()
    local sm = sdk.get_managed_singleton("app.SoulManager")
    if not is_managed(sm) then
        return false
    end
    if active_soul_count() <= 0 then
        return false
    end
    local list = try_field(sm, "_ActiveSoulList")
    local n = list_count(list)
    if n <= 0 then
        return true
    end
    local checked = 0
    for i = 0, n - 1 do
        local soul = list_item(list, i)
        if is_managed(soul) then
            checked = checked + 1
            local on = try_any(soul, { "get_InScreen" })
                or try_field(soul, "<InScreen>k__BackingField")
            if on then
                return true
            end
        end
    end
    return checked == 0
end

local function absorb_should_hold(sup)
    if try_any(sup, { "get_IsAbsorption" }) then
        return true
    end
    if try_any(sup, { "get_IsAbsorptionEnableAction" }) then
        return true
    end
    return souls_are_absorbable()
end

local function install_absorb_hooks()
    if runtime.absorb_hooks then
        return
    end
    local td = sdk.find_type_definition("app.user_data.cPlayerEquipSkill")
    if not td then
        return
    end
    runtime.absorb_hooks = true
    hook_force_bool(td:get_method("get_IsAutoSoulAbsorbe"), function()
        return features.auto_absorb and runtime.souls_ready
    end, true)
end

local function apply_auto_absorb(want)
    install_absorb_hooks()
    if not want then
        runtime.souls_ready = false
        if runtime.absorb_was_on then
            runtime.absorb_was_on = false
            log_action("auto absorb off")
        end
        return true
    end

    local first = not runtime.absorb_was_on
    local sup = get_soul_absorption()
    local ready = absorb_should_hold(sup)
    runtime.souls_ready = ready

    if ready then
        local cache = get_equip_skill_cache()
        if cache then
            pcall(function()
                cache:set_field("_IsAutoSoulAbsorbe", true)
            end)
        end
        pcall(function()
            sup:set_field("_IsCommandAbsorb", true)
        end)
        pcall(function()
            sup:call("requestSoulAbsorptionAction", true)
        end)
    elseif is_managed(sup) then
        pcall(function()
            sup:set_field("_IsCommandAbsorb", false)
        end)
    end

    runtime.absorb_was_on = true
    if first then
        log_action("auto absorb on")
    end
    return true
end

local function scale_int_arg(args, index)
    local scale = soul_scale()
    if scale == 1.0 then
        return
    end
    local ok, n = pcall(function()
        return sdk.to_int64(args[index])
    end)
    if not ok or type(n) ~= "number" or n <= 0 then
        return
    end
    local scaled = math.floor(n * scale + 0.5)
    if scaled < 1 then
        scaled = 1
    end
    args[index] = sdk.to_ptr(scaled)
end

local function install_soul_hooks()
    if runtime.soul_hooks then
        return
    end
    local td = sdk.find_type_definition("app.cPlayerSoulAbsorptionSupporter")
    if not td then
        return
    end
    runtime.soul_hooks = true
    local method = td:get_method("addSoulAbsorption")
        or td:get_method("addSoulAbsorption(app.SoulDef.ID_Fixed, System.Int32, System.Boolean)")
    if method then
        pcall(sdk.hook, method, function(args)
            scale_int_arg(args, 4)
        end)
    end
end

local function apply_soul_mult()
    install_soul_hooks()
end

local function refresh_player_status()
    local info = get_player_info()
    local chara = get_player_character(info)
    if chara then
        runtime.player = obj_type(chara)
        runtime.hooked = true
    elseif info then
        runtime.player = obj_type(info)
        runtime.hooked = true
    else
        runtime.player = "—"
        runtime.hooked = false
    end
    runtime.hp, runtime.max_hp = read_hp()
    runtime.stamina, runtime.max_stamina = read_stamina()
    runtime.oni, runtime.max_oni = read_oni()
    runtime.oni_change, runtime.max_oni_change = read_oni_change()
    runtime.pouch = read_pouch()
end

menu = RefShell.create({
    id = "onimusha",
    title = "ONIMUSHA QOL",
    toggle_vk = 0xC0,
    dock = "right",
    width = 520,
    height = 720,
    start_open = false,
    persist = features,
    host = true,
    lock_camera = true,
    lock_cursor = true,
})

menu:add_tab("Samurai", function(ui)
    ui.section("Status", function()
        imgui.text("Hooks:")
        imgui.same_line()
        imgui.text_colored(
            runtime.hooked and "Ready" or "Waiting for player",
            runtime.hooked and COL_OK or COL_WAIT
        )
        local god_label = "Off"
        local god_col = COL_WAIT
        if features.god_mode then
            if runtime.god_was_on and runtime.hooked then
                god_label = "Active"
                god_col = COL_OK
            else
                god_label = "Waiting for player"
            end
        end
        imgui.text("God:")
        imgui.same_line()
        imgui.text_colored(god_label, god_col)
        ui.kv("Player", runtime.player)
        if runtime.hp and runtime.max_hp then
            ui.kv("HP", string.format("%s / %s", runtime.hp, runtime.max_hp))
        else
            ui.kv("HP", "—")
        end
        if runtime.stamina and runtime.max_stamina then
            ui.kv("Stamina", string.format("%s / %s", runtime.stamina, runtime.max_stamina))
        else
            ui.kv("Stamina", "—")
        end
        if runtime.oni and runtime.max_oni then
            ui.kv("Oni Power", string.format("%s / %s", runtime.oni, runtime.max_oni))
        else
            ui.kv("Oni Power", "—")
        end
        if runtime.oni_change and runtime.max_oni_change then
            ui.kv("Oni Change", string.format("%.0f / %.0f", runtime.oni_change, runtime.max_oni_change))
        else
            ui.kv("Oni Change", "—")
        end
        if runtime.pouch then
            ui.kv("Hozuki pouch", tostring(runtime.pouch))
        else
            ui.kv("Hozuki pouch", "—")
        end
        ui.kv("Last action", runtime.last_log)
        ui.muted("~ toggles this menu (rebind on Settings). Look input pauses while it is open.")
    end, false)

    ui.section("Cheats", function()
        ui.bind_toggle("Infinite Health", features, "inf_health")
        ui.bind_toggle("Infinite Stamina", features, "inf_stamina")
        ui.bind_toggle("Infinite Oni Power", features, "inf_oni_power")
        ui.bind_toggle("Always Oni Change", features, "inf_oni_change")
        ui.bind_toggle("Infinite Items", features, "inf_items")
        ui.bind_toggle("Easier Issen", features, "easier_issen")
        ui.bind_toggle("Always Issen", features, "always_issen")
        ui.bind_toggle("Always Deflect", features, "always_deflect")
        ui.bind_toggle("God Mode (No Hit)", features, "god_mode")
        ui.bind_toggle("Auto Absorb Souls", features, "auto_absorb")
        ui.bind_toggle("Soul Multiplier", features, "soul_mult_on")
        ui.bind_combo("Soul Amount", features, "soul_mult", SOUL_MULT_OPTIONS)
        ui.muted(
        "Always Oni Change pins the purple-soul transform bar. Easier Issen widens the X/Y timing and keeps the chain. Always Issen auto-counters when a hit is coming — no button. Deflect turns a held block into a perfect just-guard. Auto absorb only holds L2 when souls are out. Soul multiplier is opt-in and scales red, yellow, blue, and purple. Appearance swaps meshes from this menu — it does not write unlocks to the save. Give writes the inventory. Optional hotkeys live under Settings → Keybind.")
    end, true)
end)

local Appearance = _G.OnimushaAppearance
if type(Appearance) ~= "table" then
    local ok, mod = pcall(require, "appearance")
    if ok then
        Appearance = mod
    end
end
if type(Appearance) == "table" and Appearance.bind then
    Appearance.bind({
        try_call = try_call,
        try_field = try_field,
        try_any = try_any,
        try_static = try_static,
        is_managed = is_managed,
        enum_value = enum_value,
        get_player_entity = get_player_entity,
        get_player_context = get_player_context,
        log_action = log_action,
    })
end

menu:add_tab("Appearance", function(ui)
    if type(Appearance) == "table" and Appearance.draw then
        Appearance.draw(ui)
        return
    end
    ui.muted("Appearance module failed to load.")
end)

local Give = _G.OnimushaGive
if type(Give) ~= "table" then
    local ok, mod = pcall(require, "give")
    if ok then
        Give = mod
    end
end
if type(Give) == "table" and Give.bind then
    Give.bind({
        try_call = try_call,
        try_field = try_field,
        try_any = try_any,
        try_static = try_static,
        is_managed = is_managed,
        enum_value = enum_value,
        get_item_helper = get_item_helper,
        log_action = log_action,
    })
end

menu:add_tab("Give", function(ui)
    if type(Give) == "table" and Give.draw then
        Give.draw(ui)
        return
    end
    ui.muted("Give module failed to load.")
end)

menu.extra_keybinds = function(ui)
    ui.bind_hotkey("Infinite Health", features, "inf_health_vk")
    ui.bind_hotkey("Infinite Stamina", features, "inf_stamina_vk")
    ui.bind_hotkey("Infinite Oni Power", features, "inf_oni_power_vk")
    ui.bind_hotkey("Always Oni Change", features, "inf_oni_change_vk")
    ui.bind_hotkey("Infinite Items", features, "inf_items_vk")
    ui.bind_hotkey("Easier Issen", features, "easier_issen_vk")
    ui.bind_hotkey("Always Issen", features, "always_issen_vk")
    ui.bind_hotkey("Always Deflect", features, "always_deflect_vk")
    ui.bind_hotkey("God Mode (No Hit)", features, "god_mode_vk")
    ui.bind_hotkey("Auto Absorb Souls", features, "auto_absorb_vk")
    ui.bind_hotkey("Soul Multiplier", features, "soul_mult_on_vk")
end

re.on_frame(function()
    refresh_player_status()
    apply_god_mode(features.god_mode)
    apply_inf_health(features.inf_health)
    apply_inf_stamina(features.inf_stamina)
    apply_inf_oni(features.inf_oni_power)
    apply_inf_oni_change(features.inf_oni_change)
    apply_inf_items(features.inf_items)
    local give_busy = type(Give) == "table" and Give.busy and Give.busy()
    if not give_busy then
        apply_just_actions()
    end
    apply_auto_absorb(features.auto_absorb)
    apply_soul_mult()
    if type(Give) == "table" and Give.tick then
        Give.tick()
    end
end)

re.on_script_reset(function()
    if runtime.god_was_on then
        set_no_damage(false)
        runtime.god_was_on = false
    end
end)

menu:bind()
if menu.cfg.toggle_vk == 0x2D then
    menu.cfg.toggle_vk = 0xC0
    menu.dirty = true
end
if not features.issen_split then
    features.issen_split = true
    if features.always_issen and not features.easier_issen then
        features.easier_issen = true
        features.always_issen = false
        if (features.easier_issen_vk or 0) == 0 and (features.always_issen_vk or 0) ~= 0 then
            features.easier_issen_vk = features.always_issen_vk
            features.always_issen_vk = 0
        end
    end
    menu.dirty = true
end
