-- Rise-style world bars. Discover via cEnemyContext.get_IsAngry
-- (the shipped path). HP: HealthManager.
-- Crits sit in stock until hitstop ends (calcApplyDamage). Tick the bar
-- from stockLocal / FinalDamage, same role as Rise stockDamage.

local HealthBars = _G.MHHealthBars or {}
_G.MHHealthBars = HealthBars

HealthBars.enabled = true
HealthBars.paused = false
HealthBars.show_zako = false
HealthBars.max_draw_dist = 0
HealthBars.show_hp_text = true
HealthBars.show_dist = true
HealthBars.scale = 1.5

local STALE_S = 1.5
local FLOAT_S = 1.2
local SHOW_TAU = 0.055
local SHOW_TAU_HEAVY = 0.085
local CHIP_HOLD = 0.1
local CHIP_TAU = 0.16
local OTHER_BASE = 1.5
local BOSS_BASE = 2.0
local MAX_BAR_W = 260
local WORLD_LIFT_BOSS = 3.1
local WORLD_LIFT_ZAKO = 1.15
-- Native quest/status icons sit on MissionBeaconPos when they show.
-- Drop the bar stack under that point so we do not cover them.
local ICON_CLEAR_PX = 40
local FONT_MIN = 14
local FONT_MAX = 22
local BASE_FONT = 16
local CHAR_W = 7
local MAX_BARS = 12
local BOSS_TICKS = 10

local COL_EMPTY = 0xE8000000
local COL_LINE = 0xFF141414
local COL_NAME = 0xFFE8E8E8
local COL_SHADOW = 0xFF000000
local COL_FRAME = 0xFF2A2A2A
local COL_BOSS_RIM = 0xFF3CC8E6
local COL_BOSS_FILL = 0xFF2A2AD9
local COL_BOSS_TEXT = 0xFF2A2AD9
local COL_BOSS_FLOAT = 0xFF3333FF
local COL_ZAKO_RIM = 0xFF8A8A8A
local COL_ZAKO_FILL = 0xFFD2A84A
local COL_ZAKO_TEXT = 0xFFD2A84A
local COL_ZAKO_FLOAT = 0xFFFFCC66

local tracked = {}
local by_chara = {}
local name_cache = {}
local scratch_vec = nil
local installed = false
local dmg_hooked = false
local prev_now = nil

local enemy_context_td = sdk.find_type_definition("app.cEnemyContext")
local get_is_angry = enemy_context_td and enemy_context_td:get_method("get_IsAngry")
local get_is_boss = enemy_context_td and enemy_context_td:get_method("get_IsBoss")
local get_is_zako = enemy_context_td and enemy_context_td:get_method("get_IsZako")
local get_is_animal = enemy_context_td and enemy_context_td:get_method("get_IsAnimal")
local get_browser = enemy_context_td and enemy_context_td:get_method("get_Browser")
local get_em_id = enemy_context_td and enemy_context_td:get_method("get_EmID")
local get_role_id = enemy_context_td and enemy_context_td:get_method("get_RoleID")
local get_legendary_id = enemy_context_td and enemy_context_td:get_method("get_LegendaryID")

local get_chara = nil
local get_health_manager = nil
local get_health = nil
local get_max_health = nil
local name_string = nil
local context_field = nil
local stock_character = nil
local stock_context = nil
local holder_em = nil
local calc_apply = nil
local stock_local = nil
local get_scaled_radius = nil

if get_browser then
    local browser_td = get_browser:get_return_type()
    get_scaled_radius = browser_td and browser_td:get_method("get_ScaledModelRadius")
    context_field = browser_td and browser_td:get_field("_Context")
    if context_field then
        local holder_td = context_field:get_type()
        get_chara = holder_td and holder_td:get_method("get_Chara")
        holder_em = holder_td and holder_td:get_method("get_Em")
        if get_chara then
            local chara_td = get_chara:get_return_type()
            get_health_manager = chara_td and chara_td:get_method("get_HealthManager")
            if get_health_manager then
                local hm_td = get_health_manager:get_return_type()
                get_health = hm_td and hm_td:get_method("get_Health")
                get_max_health = hm_td and hm_td:get_method("get_MaxHealth")
            end
        end
    end
end

if not get_health_manager then
    local chara_td = sdk.find_type_definition("app.EnemyCharacter")
    get_health_manager = chara_td and chara_td:get_method("get_HealthManager")
    if get_health_manager then
        local hm_td = get_health_manager:get_return_type()
        get_health = get_health or (hm_td and hm_td:get_method("get_Health"))
        get_max_health = get_max_health or (hm_td and hm_td:get_method("get_MaxHealth"))
    end
end

local enemy_def_td = sdk.find_type_definition("app.EnemyDef")
name_string = enemy_def_td and (
    enemy_def_td:get_method("NameString(app.EnemyDef.ID, app.EnemyDef.ROLE_ID, app.EnemyDef.LEGENDARY_ID)")
    or enemy_def_td:get_method("NameString")
)

local stock_td = sdk.find_type_definition("app.cEnemyStockDamage")
if stock_td then
    stock_character = stock_td:get_method("get_Character()")
    stock_context = stock_td:get_method("get_Context()")
    calc_apply = stock_td:get_method("calcApplyDamage()") or stock_td:get_method("calcApplyDamage")
    stock_local = stock_td:get_method(
        "stockLocal(app.cEnemyStockDamage.cCalcDamage)"
    )
end

local function call(method, obj, ...)
    if not method then
        return nil
    end
    local ok, result = pcall(method.call, method, obj, ...)
    if ok then
        return result
    end
    return nil
end

local function is_managed(obj)
    return obj ~= nil and type(obj) == "userdata"
end

local function as_number(value)
    if type(value) == "number" then
        return value
    end
    return nil
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

local function as_name(value)
    if type(value) == "string" then
        return value
    end
    if not is_managed(value) then
        return nil
    end
    local ok, text = pcall(function()
        if value.to_string then
            return value:to_string()
        end
        return value:call("ToString")
    end)
    if ok and type(text) == "string" and text ~= "" and not text:find("userdata") then
        return text
    end
    return nil
end

local function dummy_name(name)
    name = as_name(name) or name
    if type(name) ~= "string" then
        return true
    end
    local trimmed = name:gsub("%s+", "")
    return trimmed == "" or trimmed:match("^[%?？─%-]+$") ~= nil
end

local function enemy_name(enemy_context)
    local em_id = call(get_em_id, enemy_context)
    local role_id = call(get_role_id, enemy_context)
    local legendary_id = call(get_legendary_id, enemy_context)
    if em_id == nil or role_id == nil or legendary_id == nil then
        return nil
    end
    local key = tostring(em_id) .. ":" .. tostring(role_id) .. ":" .. tostring(legendary_id)
    if name_cache[key] then
        return name_cache[key]
    end
    local name = as_name(call(name_string, nil, em_id, role_id, legendary_id))
    if dummy_name(name) then
        return nil
    end
    name_cache[key] = name
    return name
end

local function resolve_health_manager(enemy_context)
    local browser = call(get_browser, enemy_context)
    if not is_managed(browser) or not context_field then
        return nil, nil, nil
    end
    local holder = context_field:get_data(browser)
    if not is_managed(holder) then
        return nil, nil, browser
    end
    local character = call(get_chara, holder)
    if not is_managed(character) then
        return nil, nil, browser
    end
    local health_manager = call(get_health_manager, character)
    if not is_managed(health_manager) then
        return character, nil, browser
    end
    return character, health_manager, browser
end

local function user_mult()
    local s = HealthBars.scale
    if type(s) ~= "number" or s < OTHER_BASE then
        s = OTHER_BASE
    elseif s > 2.5 then
        s = 2.5
    end
    return s / OTHER_BASE
end

local function bar_scale(is_boss)
    local s = (is_boss and BOSS_BASE or OTHER_BASE) * user_mult()
    local max_s = MAX_BAR_W / 110
    if s > max_s then
        s = max_s
    end
    return s
end

local function font_px(s)
    local px = BASE_FONT * (s / OTHER_BASE)
    if px < FONT_MIN then
        return FONT_MIN
    end
    if px > FONT_MAX then
        return FONT_MAX
    end
    return px
end

local function row_style(is_boss)
    if is_boss then
        return COL_BOSS_FILL, COL_BOSS_TEXT, COL_BOSS_FLOAT, COL_BOSS_RIM
    end
    return COL_ZAKO_FILL, COL_ZAKO_TEXT, COL_ZAKO_FLOAT, COL_ZAKO_RIM
end

local function pack_col(a, r, g, b)
    return a * 16777216 + b * 65536 + g * 256 + r
end

local function unpack_col(c)
    c = c % 4294967296
    local a = math.floor(c / 16777216) % 256
    local b = math.floor(c / 65536) % 256
    local g = math.floor(c / 256) % 256
    local r = c % 256
    return a, r, g, b
end

local function shade(c, add)
    local a, r, g, b = unpack_col(c)
    local function cl(v)
        v = v + add
        if v < 0 then
            return 0
        end
        if v > 255 then
            return 255
        end
        return math.floor(v)
    end
    return pack_col(a, cl(r), cl(g), cl(b))
end

local function fg_dl()
    if not imgui or not imgui.get_foreground_draw_list then
        return nil
    end
    local ok, dl = pcall(imgui.get_foreground_draw_list)
    if ok then
        return dl
    end
    return nil
end

local function fill_rect(dl, x, y, w, h, col, round)
    if w <= 0.5 or h <= 0.5 then
        return
    end
    if dl and dl.add_rect_filled then
        local ok = pcall(function()
            dl:add_rect_filled({ x, y }, { x + w, y + h }, col, round or 0)
        end)
        if ok then
            return
        end
    end
    draw.filled_rect(x, y, w, h, col)
end

local function stroke_rect(dl, x, y, w, h, col, round, thick)
    if w <= 0.5 or h <= 0.5 then
        return
    end
    if dl and dl.add_rect then
        local ok = pcall(function()
            dl:add_rect({ x, y }, { x + w, y + h }, col, round or 0, 0, thick or 1)
        end)
        if ok then
            return
        end
    end
    draw.outline_rect(x, y, w, h, col)
end

local function vec3(pos)
    if pos == nil then
        return nil
    end
    local x, y, z = pos.x, pos.y, pos.z
    if type(x) ~= "number" or type(y) ~= "number" or type(z) ~= "number" then
        return nil
    end
    if x ~= x or y ~= y or z ~= z then
        return nil
    end
    if x == 0 and y == 0 and z == 0 then
        return nil
    end
    return x, y, z
end

local function read_vec3(obj, names)
    if not is_managed(obj) then
        return nil
    end
    for _, name in ipairs(names) do
        local ok, pos = pcall(function()
            return obj:call(name)
        end)
        if ok then
            local x, y, z = vec3(pos)
            if x then
                return x, y, z
            end
        end
        ok, pos = pcall(function()
            return obj:get_field(name)
        end)
        if ok then
            local x, y, z = vec3(pos)
            if x then
                return x, y, z
            end
        end
    end
    return nil
end

local function trans_pos(obj)
    if not is_managed(obj) then
        return nil
    end
    local x, y, z = read_vec3(obj, { "get_Position", "get_Pos" })
    if x then
        return x, y, z
    end
    local ok, go = pcall(function()
        return obj:call("get_GameObject")
    end)
    if not ok or not is_managed(go) then
        return nil
    end
    local ok_t, trans = pcall(function()
        return go:call("get_Transform")
    end)
    if not ok_t then
        return nil
    end
    return read_vec3(trans, { "get_Position" })
end

local function radius_lift(browser, is_boss)
    local r = as_number(call(get_scaled_radius, browser))
    if type(r) ~= "number" or r < 0.25 then
        return is_boss and WORLD_LIFT_BOSS or WORLD_LIFT_ZAKO
    end
    local lift = r * 0.72
    if is_boss then
        if lift < 3.4 then
            lift = 3.4
        elseif lift > 6.2 then
            lift = 6.2
        end
    elseif lift < 1.05 then
        lift = 1.05
    elseif lift > 2.2 then
        lift = 2.2
    end
    return lift
end

-- Browser ModelCenter/GameObject is the root. MissionBeacon is the native
-- above-head slot (quest icons use it when they appear). LookedPos is the
-- camera lock point — often chest/head, still better than root+3.1.
local function world_pos(row)
    local browser = row.browser
    if not is_managed(browser) then
        browser = call(get_browser, row.enemy_context)
        row.browser = browser
    end
    local gx, gy, gz = read_vec3(browser, {
        "get_GameObjectPos",
        "get_ModelCenterPos",
    })
    local bx, by, bz = read_vec3(browser, { "get_MissionBeaconPos" })
    if bx and (gy == nil or by > gy + 0.35) then
        row.crown = true
        return bx, by, bz
    end
    local lx, ly, lz = read_vec3(browser, { "get_LookedPos" })
    if lx and gy and ly > gy + 0.35 then
        row.crown = true
        return lx, ly, lz
    end
    row.crown = false
    if gx then
        return gx, gy + radius_lift(browser, row.boss), gz
    end
    for _, obj in ipairs({ row.character, row.health_manager, row.enemy_context }) do
        local x, y, z = trans_pos(obj)
        if x then
            return x, y + radius_lift(browser, row.boss), z
        end
    end
    return nil
end

local function camera_pos()
    local cam = nil
    pcall(function()
        if sdk.get_primary_camera then
            cam = sdk.get_primary_camera()
        end
    end)
    return trans_pos(cam)
end

local function hunter_pos()
    local pm = sdk.get_managed_singleton("app.PlayerManager")
    if not is_managed(pm) then
        return nil
    end
    local info
    for _, name in ipairs({ "getMasterPlayer", "get_MasterPlayer" }) do
        local ok, value = pcall(function()
            return pm:call(name)
        end)
        if ok and is_managed(value) then
            info = value
            break
        end
    end
    if not info then
        return nil
    end
    local chara
    for _, name in ipairs({ "get_Character", "get_Hunter" }) do
        local ok, value = pcall(function()
            return info:call(name)
        end)
        if ok and is_managed(value) then
            chara = value
            break
        end
    end
    return trans_pos(chara)
end

local function dist3(x, y, z, ox, oy, oz)
    if ox == nil then
        return nil
    end
    local dx, dy, dz = x - ox, y - oy, z - oz
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function too_far(x, y, z, cx, cy, cz)
    local max_d = HealthBars.max_draw_dist
    if type(max_d) ~= "number" or max_d <= 0 or cx == nil then
        return false
    end
    local dx, dy, dz = x - cx, y - cy, z - cz
    return (dx * dx + dy * dy + dz * dz) > (max_d * max_d)
end

local function to_screen(x, y, z)
    if not draw or not draw.world_to_screen or not Vector3f then
        return nil
    end
    if scratch_vec == nil then
        scratch_vec = Vector3f.new(0, 0, 0)
    end
    scratch_vec.x = x
    scratch_vec.y = y
    scratch_vec.z = z
    local ok, screen = pcall(draw.world_to_screen, scratch_vec)
    if not ok or screen == nil then
        return nil
    end
    local sx, sy = screen.x, screen.y
    if type(sx) ~= "number" or type(sy) ~= "number" then
        return nil
    end
    if sx ~= sx or sy ~= sy then
        return nil
    end
    return sx, sy
end

local function refresh_row_pos(row)
    local x, y, z = world_pos(row)
    if x then
        row.x, row.y, row.z = x, y, z
    end
end

local function apply_hp(row, hp, max_hp, now)
    if not hp or not max_hp or max_hp <= 0 then
        return
    end
    if row.prev_health ~= nil and hp < row.prev_health - 0.5 then
        local floats = row.floats
        floats[#floats + 1] = {
            amount = row.prev_health - hp,
            born = now,
        }
        if #floats > 8 then
            table.remove(floats, 1)
        end
        if row.chip == nil or row.chip < row.prev_health then
            row.chip = row.prev_health
        end
        row.chip_hold = now + CHIP_HOLD
    end
    row.health = hp
    row.max_health = max_hp
    row.prev_health = hp
    if row.shown == nil then
        row.shown = hp
    end
    if row.chip == nil then
        row.chip = hp
    end
end

local function live_hp(row, hp)
    if row.pending_hp == nil then
        return hp
    end
    if type(hp) == "number" and hp <= row.pending_hp + 0.5 then
        row.pending_hp = nil
        row.last_stock_dmg = nil
        return hp
    end
    return row.pending_hp
end

local function tick_shown(row, dt)
    local target = row.health
    if type(target) ~= "number" then
        return
    end
    if row.shown == nil then
        row.shown = target
        return
    end
    local delta = row.shown - target
    if delta <= 0.35 then
        row.shown = target
        return
    end
    local tau = SHOW_TAU
    local max_hp = row.max_health or 0
    if max_hp > 0 and delta > max_hp * 0.2 then
        tau = SHOW_TAU_HEAVY
    end
    row.shown = row.shown + (target - row.shown) * (1 - math.exp(-dt / tau))
    if row.shown - target < 0.35 then
        row.shown = target
    end
end

local function tick_chip(row, now, dt)
    local target = row.health
    if type(target) ~= "number" then
        return
    end
    if row.chip == nil then
        row.chip = target
        return
    end
    if target > row.chip then
        row.chip = target
        row.chip_hold = nil
        return
    end
    if row.chip_hold and now < row.chip_hold then
        return
    end
    if row.chip - target <= 0.35 then
        row.chip = target
        row.chip_hold = nil
        return
    end
    row.chip = row.chip + (target - row.chip) * (1 - math.exp(-dt / CHIP_TAU))
    if row.chip - target < 0.35 then
        row.chip = target
        row.chip_hold = nil
    end
end

local function remember_chara(row, character)
    local addr = obj_addr(character)
    if not addr then
        return
    end
    if row.chara_addr and row.chara_addr ~= addr then
        by_chara[row.chara_addr] = nil
    end
    row.chara_addr = addr
    by_chara[addr] = row
end

local function forget_row(row)
    if row and row.chara_addr then
        by_chara[row.chara_addr] = nil
    end
end

local function want_enemy(enemy_context)
    if call(get_is_boss, enemy_context) == true then
        return true, true
    end
    if not HealthBars.show_zako then
        return false, false
    end
    if call(get_is_animal, enemy_context) == true then
        return false, false
    end
    if call(get_is_zako, enemy_context) == true then
        return true, false
    end
    return false, false
end

local function on_update(enemy_context)
    if not HealthBars.enabled or HealthBars.paused then
        return
    end
    if not is_managed(enemy_context) then
        return
    end
    local addr = obj_addr(enemy_context)
    if not addr then
        return
    end

    local keep, is_boss = want_enemy(enemy_context)
    if not keep then
        return
    end

    local row = tracked[addr]
    local character = row and row.character
    local health_manager = row and row.health_manager
    local browser = row and row.browser
    if not is_managed(health_manager) or not is_managed(browser) then
        character, health_manager, browser = resolve_health_manager(enemy_context)
        if not is_managed(health_manager) then
            return
        end
    end

    local hp = as_number(call(get_health, health_manager))
    local max_hp = as_number(call(get_max_health, health_manager))
    local now = os.clock()
    if row == nil then
        if not hp or hp <= 0 or not max_hp or max_hp <= 0 then
            return
        end
        local name = enemy_name(enemy_context)
        if dummy_name(name) then
            return
        end
        row = {
            name = name,
            enemy_context = enemy_context,
            character = character,
            health_manager = health_manager,
            browser = browser,
            boss = is_boss,
            health = 0,
            max_health = 0,
            prev_health = nil,
            floats = {},
            shown = nil,
            chip = nil,
            chip_hold = nil,
            pending_hp = nil,
            last_stock_dmg = nil,
            hit_at = nil,
            seen = now,
        }
        tracked[addr] = row
    else
        row.enemy_context = enemy_context
        row.character = character
        row.health_manager = health_manager
        row.browser = browser
        row.boss = is_boss
        row.seen = now
    end
    remember_chara(row, character)
    apply_hp(row, live_hp(row, hp), max_hp, now)
    refresh_row_pos(row)
end

local function clamp01(v)
    if v > 1 then
        return 1
    end
    if v < 0 then
        return 0
    end
    return v
end

local function draw_fill_grad(dl, x, y, w, h, col, round)
    if w <= 0.5 or h <= 0.5 then
        return
    end
    local band = h / 3
    fill_rect(dl, x, y, w, band + 0.5, shade(col, 38), round)
    fill_rect(dl, x, y + band, w, band + 0.5, col, 0)
    fill_rect(dl, x, y + band * 2, w, h - band * 2, shade(col, -32), 0)
    local hi = math.max(1.2, h * 0.18)
    fill_rect(dl, x, y, w, hi, shade(col, 58), round)
end

local function draw_bar(sx, sy, pct, chip_pct, s, fill_col, rim_col, is_boss)
    local bar_w = 110 * s
    local bar_h = 12 * s
    local x = sx - bar_w * 0.5
    local y = sy
    pct = clamp01(pct)
    chip_pct = clamp01(chip_pct)
    if chip_pct < pct then
        chip_pct = pct
    end
    local round = is_boss and 3.5 * s / OTHER_BASE or 2.4 * s / OTHER_BASE
    local dl = fg_dl()
    fill_rect(dl, x, y, bar_w, bar_h, COL_EMPTY, round)
    local chip_w = bar_w * chip_pct
    if chip_w > pct * bar_w + 0.5 then
        draw_fill_grad(dl, x, y, chip_w, bar_h, shade(fill_col, 70), round)
    end
    local fill = bar_w * pct
    if fill > 0.5 then
        draw_fill_grad(dl, x, y, fill, bar_h, fill_col, round)
    end
    if is_boss then
        for i = 1, BOSS_TICKS - 1 do
            local tx = x + bar_w * (i / BOSS_TICKS)
            fill_rect(dl, tx, y + 1, 1, bar_h - 2, 0x66101010, 0)
        end
        local cap = math.max(2, 2.2 * s / OTHER_BASE)
        fill_rect(dl, x, y, cap, cap, COL_BOSS_RIM, 0)
        fill_rect(dl, x + bar_w - cap, y, cap, cap, COL_BOSS_RIM, 0)
        fill_rect(dl, x, y + bar_h - cap, cap, cap, COL_BOSS_RIM, 0)
        fill_rect(dl, x + bar_w - cap, y + bar_h - cap, cap, cap, COL_BOSS_RIM, 0)
    end
    stroke_rect(dl, x, y, bar_w, bar_h, COL_FRAME, round, 2)
    stroke_rect(dl, x + 1, y + 1, bar_w - 2, bar_h - 2, rim_col, round, 1)
    stroke_rect(dl, x, y, bar_w, bar_h, COL_LINE, round, 1)
end

local function measure_text(text, px)
    if imgui and imgui.calc_text_size then
        local ok, size = pcall(imgui.calc_text_size, text)
        if ok and size and type(size.x) == "number" then
            return size.x, size.y
        end
    end
    return #text * CHAR_W * (px / BASE_FONT), px
end

local function draw_centered(text, cx, cy, color, px)
    local pushed = false
    if imgui and imgui.push_font_size then
        pushed = pcall(imgui.push_font_size, px)
    end
    local w = measure_text(text, px)
    local x = cx - w * 0.5
    local dl = fg_dl()
    if dl and dl.add_text then
        pcall(function()
            dl:add_text({ x + 1, cy + 1 }, COL_SHADOW, text)
            dl:add_text({ x, cy }, color, text)
        end)
    else
        draw.text(text, x + 1, cy + 1, COL_SHADOW)
        draw.text(text, x, cy, color)
    end
    if pushed and imgui.pop_font_size then
        pcall(imgui.pop_font_size)
    end
    return px
end

local function draw_row(row, now, hx, hy, hz)
    local x, y, z = row.x, row.y, row.z
    if x == nil then
        return
    end
    local meters = dist3(x, y, z, hx, hy, hz)
    local sx, sy = to_screen(x, y, z)
    if sx == nil then
        return false
    end
    local s = bar_scale(row.boss)
    local px = font_px(s)
    local fill_col, text_col, float_col, rim_col = row_style(row.boss)
    local bar_h = 12 * s
    -- Crown = MissionBeacon / LookedPos (native icon slot). Name goes
    -- under that point so conditional icons stay clear. Fallback already
    -- has world lift baked in; keep the old name-above-bar stack.
    if row.crown then
        sy = sy + ICON_CLEAR_PX + px + 4
    else
        sy = sy - (px + 6)
    end

    local shown = row.shown or row.health
    local chip = row.chip or shown
    local alive = type(row.health) == "number" and row.health > 0
    if alive then
        local pct = 0
        local chip_pct = 0
        if row.max_health and row.max_health > 0 then
            pct = shown / row.max_health
            chip_pct = chip / row.max_health
        end
        draw_bar(sx, sy, pct, chip_pct, s, fill_col, rim_col, row.boss)
        local label = row.name
        if HealthBars.show_dist and meters then
            label = string.format("%s  %.0fm", row.name, meters)
        end
        draw_centered(label, sx, sy - px - 4, COL_NAME, px)
        if HealthBars.show_hp_text then
            draw_centered(
                string.format("%.0f/%.0f", shown, row.max_health),
                sx,
                sy + bar_h + 3,
                text_col,
                px
            )
        end
    end

    local keep = {}
    for _, flt in ipairs(row.floats) do
        local age = now - flt.born
        if age < FLOAT_S then
            local rise = age / FLOAT_S
            local fy = sy - px - 14 - rise * (28 * s)
            draw_centered(string.format("-%.0f", flt.amount), sx, fy, float_col, px)
            keep[#keep + 1] = flt
        end
    end
    row.floats = keep
    return true
end

local function row_from_stock(stock)
    local character = call(stock_character, stock)
    local row = by_chara[obj_addr(character)]
    if row then
        return row, character
    end
    local holder = call(stock_context, stock)
    local em = call(holder_em, holder)
    row = tracked[obj_addr(em)]
    return row, character
end

local function calc_final_damage(calc)
    if not is_managed(calc) then
        return 0
    end
    local dmg
    pcall(function()
        dmg = calc:get_field("FinalDamage")
    end)
    if type(dmg) == "number" and dmg >= 0.5 then
        return dmg
    end
    local phys, elem = 0, 0
    pcall(function()
        phys = calc:get_field("Physical") or 0
        elem = calc:get_field("Element") or 0
    end)
    return (tonumber(phys) or 0) + (tonumber(elem) or 0)
end

-- from_stock: tick at stock time (crit / hitstop). Apply-time must not
-- subtract again — pending_hp holds until HealthManager catches up.
local function note_hit(stock, dmg, from_stock)
    if not HealthBars.enabled or HealthBars.paused then
        return
    end
    if type(dmg) ~= "number" or dmg < 0.5 then
        return
    end
    local row, character = row_from_stock(stock)
    if not row then
        return
    end
    local now = os.clock()
    if row.last_stock_dmg
        and math.abs(row.last_stock_dmg - dmg) < 0.5
        and (now - (row.hit_at or 0)) < 0.12
    then
        return
    end
    if not from_stock and row.pending_hp ~= nil then
        return
    end
    local cur = row.health
    if from_stock and row.pending_hp ~= nil then
        cur = row.pending_hp
    end
    if type(cur) ~= "number" then
        cur = as_number(call(get_health, row.health_manager))
    end
    if type(cur) ~= "number" then
        return
    end
    local next_hp = cur - dmg
    if next_hp < 0 then
        next_hp = 0
    end
    row.last_stock_dmg = dmg
    row.hit_at = now
    row.pending_hp = next_hp
    apply_hp(row, next_hp, row.max_health, now)
    row.seen = now
    remember_chara(row, character or row.character)
end

local function hook_stock(method, pre_fn, post_fn)
    if not method then
        return
    end
    pcall(sdk.hook, method, pre_fn, post_fn)
end

local function install_dmg_hooks()
    if dmg_hooked then
        return
    end
    dmg_hooked = true

    -- Rise stockDamage: numbers exist before HealthManager moves.
    if stock_local then
        local pending = { stock = nil, calc = nil }
        hook_stock(stock_local, function(args)
            pending.stock = nil
            pending.calc = nil
            pcall(function()
                pending.stock = sdk.to_managed_object(args[2])
                pending.calc = sdk.to_managed_object(args[3])
            end)
        end, function(retval)
            local stock = pending.stock
            local calc = pending.calc
            pending.stock = nil
            pending.calc = nil
            pcall(note_hit, stock, calc_final_damage(calc), true)
            return retval
        end)
    end

    -- Apply after hitstop. Skip if stock already ticked this hit.
    if calc_apply then
        local pending = { stock = nil }
        hook_stock(calc_apply, function(args)
            pending.stock = nil
            pcall(function()
                pending.stock = sdk.to_managed_object(args[2])
            end)
        end, function(retval)
            local stock = pending.stock
            pending.stock = nil
            local dmg = nil
            pcall(function()
                dmg = sdk.to_float(retval)
            end)
            pcall(note_hit, stock, dmg, false)
            return retval
        end)
    end
end

local function on_frame()
    if not HealthBars.enabled then
        return
    end
    if HealthBars.paused then
        if next(tracked) ~= nil then
            for _, row in pairs(tracked) do
                forget_row(row)
            end
            tracked = {}
            by_chara = {}
        end
        prev_now = nil
        return
    end

    local now = os.clock()
    local dt = 1 / 60
    if prev_now then
        dt = now - prev_now
        if dt < 0.001 then
            dt = 0.001
        elseif dt > 0.1 then
            dt = 0.1
        end
    end
    prev_now = now

    local cx, cy, cz = camera_pos()
    local hx, hy, hz = hunter_pos()
    if hx == nil then
        hx, hy, hz = cx, cy, cz
    end

    local ranked = {}
    local drop = {}
    for addr, row in pairs(tracked) do
        refresh_row_pos(row)
        local live_float = false
        for _, flt in ipairs(row.floats) do
            if (now - flt.born) < FLOAT_S then
                live_float = true
                break
            end
        end
        local ready = row.max_health and row.max_health > 0
        local stale = (now - (row.seen or 0)) > STALE_S
        local dead = ready and row.health <= 0
        local hide_zako = (not row.boss) and (not HealthBars.show_zako)
        if hide_zako and not live_float then
            drop[#drop + 1] = addr
        elseif (stale or dead) and not live_float then
            drop[#drop + 1] = addr
        elseif ready and row.health > 0 and not hide_zako then
            tick_shown(row, dt)
            tick_chip(row, now, dt)
            local x, y, z = row.x, row.y, row.z
            if x and not too_far(x, y, z, cx, cy, cz) then
                row._dist = dist3(x, y, z, hx, hy, hz) or 0
                ranked[#ranked + 1] = row
            end
        elseif ready and dead and live_float then
            local x, y, z = row.x, row.y, row.z
            if x and not too_far(x, y, z, cx, cy, cz) then
                row._dist = dist3(x, y, z, hx, hy, hz) or 0
                ranked[#ranked + 1] = row
            end
        end
    end
    for _, addr in ipairs(drop) do
        forget_row(tracked[addr])
        tracked[addr] = nil
    end

    table.sort(ranked, function(a, b)
        if a.boss ~= b.boss then
            return a.boss
        end
        return (a._dist or 0) < (b._dist or 0)
    end)

    local n = #ranked
    if n > MAX_BARS then
        n = MAX_BARS
    end
    for i = 1, n do
        pcall(draw_row, ranked[i], now, hx, hy, hz)
    end
end

function HealthBars.kick()
    prev_now = nil
end

function HealthBars.install()
    if installed then
        return
    end
    installed = true
    if get_is_angry then
        sdk.hook(get_is_angry, function(args)
            local ctx = sdk.to_managed_object(args[2])
            pcall(on_update, ctx)
        end, function(retval)
            return retval
        end)
    end
    pcall(install_dmg_hooks)
    re.on_frame(function()
        pcall(on_frame)
    end)
end

HealthBars.install()
return HealthBars
