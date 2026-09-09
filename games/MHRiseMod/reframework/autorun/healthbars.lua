-- World HP bars. Discover via EnemyManager lists, not an angry hook.
-- HP: EnemyCharacterBase.getHpVital / getHpMaxVital only.
-- Track by native address — getBossEnemy() returns a new handle every poll.
-- Draw only on on_frame. Rise discards draw.* from Begin/EndRendering.

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
-- 1x combo = these bases. Combo 2x/3x multiplies both.
local OTHER_BASE = 1.5
local BOSS_BASE = 2.0
local MAX_BAR_W = 260
local WORLD_LIFT_BOSS = 3.1
local WORLD_LIFT_ZAKO = 1.15
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
local name_cache = {}
local methods = {}
local scratch_vec = nil
local force_poll = false
local installed = false
local hooked = false
local last_qstatus = nil
local prev_now = nil
local dmg_hooked = false

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
    if not method or obj == nil then
        return nil
    end
    local n = select("#", ...)
    local a, b = ...
    local ok, result = pcall(function()
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

local function type_key(em_type)
    local n = as_number(em_type)
    if n then
        return n
    end
    if not is_managed(em_type) then
        return nil
    end
    local ok, value = pcall(function()
        if em_type.get_value then
            return em_type:get_value()
        end
        return nil
    end)
    if ok then
        n = as_number(value)
        if n then
            return n
        end
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
        return tostring(value)
    end)
    if ok and type(text) == "string" and text ~= "" and not text:find("userdata") then
        return text
    end
    return nil
end

local function dummy_name(name)
    if type(name) ~= "string" then
        return true
    end
    local trimmed = name:gsub("%s+", "")
    return trimmed == "" or trimmed:match("^[%?？─%-]+$") ~= nil
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
    return x, y, z
end

local function trans_pos(trans)
    if not is_managed(trans) then
        return nil
    end
    return vec3(call(methods.get_position, trans))
end

local function component_trans(obj)
    local go = call(methods.get_game_object, obj)
    if not is_managed(go) then
        return nil
    end
    local trans = call(methods.get_transform, go)
    if is_managed(trans) then
        return trans
    end
    return nil
end

local function enemy_name(enemy)
    local em_type = call(methods.get_enemy_type, enemy)
    local key = type_key(em_type)
    if key ~= nil and name_cache[key] then
        return name_cache[key]
    end
    local mm = nil
    pcall(function()
        mm = sdk.get_managed_singleton("snow.gui.MessageManager")
    end)
    local name = as_name(call(methods.enemy_name_message, mm, em_type))
    if dummy_name(name) then
        name = as_name(em_type)
    end
    if dummy_name(name) then
        name = "Enemy"
    end
    if key ~= nil then
        name_cache[key] = name
    end
    return name
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

local function camera_pos()
    local cam = nil
    pcall(function()
        if sdk.get_primary_camera then
            cam = sdk.get_primary_camera()
        end
    end)
    return trans_pos(component_trans(cam))
end

local function hunter_pos()
    local pm = nil
    pcall(function()
        pm = sdk.get_managed_singleton("snow.player.PlayerManager")
    end)
    return trans_pos(component_trans(call(methods.find_master, pm)))
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
    -- getBossEnemy returns a new handle each poll. Cached transforms go stale.
    row.trans = component_trans(row.enemy)
    local x, y, z = trans_pos(row.trans)
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

-- Crit / hitstop stocks damage before getHpVital moves (IsHPStop1).
-- Keep the early tick until the getter catches up so poll cannot snap back.
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

local function update_enemy(enemy, is_boss, now)
    local addr = obj_addr(enemy)
    if not addr then
        return
    end
    local hp = as_number(call(methods.get_hp, enemy))
    local max_hp = as_number(call(methods.get_hp_max, enemy))
    local row = tracked[addr]
    -- Carcass stays on getBossEnemy at 0. Do not start a new bar for it.
    if row == nil then
        if not hp or hp <= 0 then
            return
        end
        row = {
            enemy = enemy,
            name = enemy_name(enemy),
            boss = is_boss == true,
            health = 0,
            max_health = 0,
            prev_health = nil,
            floats = {},
            shown = nil,
            chip = nil,
            chip_hold = nil,
            seen = now,
            trans = nil,
            pending_hp = nil,
            last_stock_dmg = nil,
            hit_at = nil,
        }
        tracked[addr] = row
    else
        row.enemy = enemy
        row.boss = is_boss == true
        row.seen = now
    end
    apply_hp(row, live_hp(row, hp), max_hp, now)
    refresh_row_pos(row)
end

local function poll_list(mgr, count_m, get_m, is_boss, now)
    local count = as_number(call(count_m, mgr))
    if not count or count <= 0 then
        return
    end
    if count > 16 then
        count = 16
    end
    for i = 0, count - 1 do
        update_enemy(call(get_m, mgr, i), is_boss, now)
    end
end

local function poll_enemies(now)
    local mgr = nil
    pcall(function()
        mgr = sdk.get_managed_singleton("snow.enemy.EnemyManager")
    end)
    if not is_managed(mgr) then
        return
    end
    poll_list(mgr, methods.boss_count, methods.boss_at, true, now)
    if HealthBars.show_zako then
        poll_list(mgr, methods.zako_count, methods.zako_at, false, now)
    end
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

local function draw_centered(text, cx, cy, color, px)
    local w = #text * CHAR_W * (px / BASE_FONT)
    local x = cx - w * 0.5
    draw.text(text, x + 1, cy + 1, COL_SHADOW)
    draw.text(text, x, cy, color)
    return px
end

local function draw_row(row, now, hx, hy, hz)
    local x, y, z = row.x, row.y, row.z
    if x == nil then
        return
    end
    local lift = row.boss and WORLD_LIFT_BOSS or WORLD_LIFT_ZAKO
    local meters = dist3(x, y, z, hx, hy, hz)
    local sx, sy = to_screen(x, y + lift, z)
    if sx == nil then
        return false
    end
    local s = bar_scale(row.boss)
    local px = font_px(s)
    local fill_col, text_col, float_col, rim_col = row_style(row.boss)
    local bar_h = 12 * s
    local name_gap = px + 6
    sy = sy - name_gap

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

-- Ready/Reset/Return is the load window. Success/Failed/SuccessSub stay
-- in the field (carve, faint, meat-eaters) — keep polling those.
-- Do not pause on the cheat playable gate — that wipe hid bars until toggle.
local function quest_status()
    local qm
    pcall(function()
        qm = sdk.get_managed_singleton("snow.QuestManager")
    end)
    if not is_managed(qm) then
        return nil
    end
    local status
    pcall(function()
        status = qm:get_field("_QuestStatus")
    end)
    if type(status) == "number" then
        return status
    end
    return nil
end

local function scene_busy(status)
    -- 1 Ready, 5 Reset, 7 Return. Leave Success/Failed/SuccessSub alone.
    return status == 1 or status == 5 or status == 7
end

local function on_frame()
    if not HealthBars.enabled then
        return
    end
    local status = quest_status()
    if status ~= last_qstatus then
        last_qstatus = status
        force_poll = true
        if scene_busy(status) then
            tracked = {}
            prev_now = nil
        end
    end
    if HealthBars.paused or scene_busy(status) then
        if next(tracked) ~= nil then
            tracked = {}
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
    force_poll = false
    poll_enemies(now)

    local cx, cy, cz = camera_pos()
    local hx, hy, hz = hunter_pos()
    if hx == nil then
        hx, hy, hz = cx, cy, cz
    end

    local ranked = {}
    local drop = {}
    for addr, row in pairs(tracked) do
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
        if (stale or dead) and not live_float then
            drop[#drop + 1] = addr
        elseif ready and row.health > 0 then
            tick_shown(row, dt)
            tick_chip(row, now, dt)
            local x, y, z = row.x, row.y, row.z
            if x and not too_far(x, y, z, cx, cy, cz) then
                row._dist = dist3(x, y, z, hx, hy, hz) or 0
                ranked[#ranked + 1] = row
            end
        elseif ready and dead and live_float then
            -- Killing-blow floats only. No empty 0/max bar.
            local x, y, z = row.x, row.y, row.z
            if x and not too_far(x, y, z, cx, cy, cz) then
                row._dist = dist3(x, y, z, hx, hy, hz) or 0
                ranked[#ranked + 1] = row
            end
        end
    end
    for _, addr in ipairs(drop) do
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

local function refresh_tracked(enemy)
    if not HealthBars.enabled or HealthBars.paused then
        return
    end
    if scene_busy(quest_status()) then
        return
    end
    local addr = obj_addr(enemy)
    local row = addr and tracked[addr]
    if not row then
        return
    end
    apply_hp(
        row,
        live_hp(row, as_number(call(methods.get_hp, enemy))),
        as_number(call(methods.get_hp_max, enemy)),
        os.clock()
    )
    row.enemy = enemy
    row.seen = os.clock()
end

local function info_vital(info)
    if not is_managed(info) then
        return 0
    end
    if call(methods.info_ignore, info) == true then
        return 0
    end
    local phys = as_number(call(methods.info_phys, info)) or 0
    local elem = as_number(call(methods.info_elem, info)) or 0
    return phys + elem
end

-- Tick the bar from AfterCalcInfo at stock time. Crits sit in hitstop
-- before applyDamage writes getHpVital; the float would wait otherwise.
local function note_hit(enemy, info)
    if not HealthBars.enabled or HealthBars.paused then
        return
    end
    if scene_busy(quest_status()) then
        return
    end
    local dmg = info_vital(info)
    if dmg < 0.5 then
        return
    end
    local addr = obj_addr(enemy)
    local row = addr and tracked[addr]
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
    local cur = row.health
    if type(cur) ~= "number" then
        cur = as_number(call(methods.get_hp, enemy))
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
end

local function hook_hp(signature)
    local method = bind("snow.enemy.EnemyCharacterBase", signature)
    if not method then
        return
    end
    local pending = { enemy = nil, info = nil }
    pcall(sdk.hook, method, function(args)
        pending.enemy = nil
        pending.info = nil
        pcall(function()
            pending.enemy = sdk.to_managed_object(args[2])
            pending.info = sdk.to_managed_object(args[3])
        end)
        pcall(note_hit, pending.enemy, pending.info)
    end, function(retval)
        local enemy = pending.enemy
        pending.enemy = nil
        pending.info = nil
        pcall(refresh_tracked, enemy)
        return retval
    end)
end

local function install_dmg_hooks()
    if dmg_hooked then
        return
    end
    dmg_hooked = true
    hook_hp("applyDamage(snow.hit.EnemyCalcDamageInfo.AfterCalcInfo_DamageSide)")
    hook_hp("stockDamage(snow.hit.EnemyCalcDamageInfo.AfterCalcInfo_DamageSide)")
end

local function bind_methods()
    methods.boss_count = bind("snow.enemy.EnemyManager", "getBossEnemyCount()")
    methods.boss_at = bind("snow.enemy.EnemyManager", "getBossEnemy(System.Int32)")
    methods.zako_count = bind("snow.enemy.EnemyManager", "getZakoEnemyCount()")
    methods.zako_at = bind("snow.enemy.EnemyManager", "getZakoEnemy(System.Int32)")
    methods.get_hp = bind("snow.enemy.EnemyCharacterBase", "getHpVital()")
    methods.get_hp_max = bind("snow.enemy.EnemyCharacterBase", "getHpMaxVital()")
    methods.info_phys = bind(
        "snow.hit.EnemyCalcDamageInfo.AfterCalcInfo_DamageSide",
        "get_PhysicalPartsVitalDamage()"
    )
    methods.info_elem = bind(
        "snow.hit.EnemyCalcDamageInfo.AfterCalcInfo_DamageSide",
        "get_ElementPartsVitalDamage()"
    )
    methods.info_ignore = bind(
        "snow.hit.EnemyCalcDamageInfo.AfterCalcInfo_DamageSide",
        "get_IsIgnoreDamage()"
    )
    methods.get_enemy_type = bind("snow.enemy.EnemyCharacterBase", "get_EnemyType()")
    methods.find_master = bind("snow.player.PlayerManager", "findMasterPlayer()")
    methods.get_game_object = bind("via.Component", "get_GameObject()")
        or bind("snow.CharacterBase", "get_GameObject()")
        or bind("snow.enemy.EnemyCharacterBase", "get_GameObject()")
    methods.get_transform = bind("via.GameObject", "get_Transform()")
    methods.get_position = bind("via.Transform", "get_Position()")
    methods.enemy_name_message = bind(
        "snow.gui.MessageManager",
        "getEnemyNameMessage(snow.enemy.EnemyDef.EmTypes)"
    )
    return methods.boss_count and methods.boss_at and methods.get_hp and methods.get_position
end

function HealthBars.kick()
    force_poll = true
    last_qstatus = nil
end

local function tick()
    if not installed then
        local ok, ready = pcall(bind_methods)
        if ok and ready then
            installed = true
            force_poll = true
            pcall(install_dmg_hooks)
        else
            return
        end
    end
    pcall(on_frame)
end

function HealthBars.install()
    if hooked then
        return
    end
    hooked = true
    re.on_frame(tick)
end

HealthBars.install()
return HealthBars
