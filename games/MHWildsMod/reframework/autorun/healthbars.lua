-- healthbars.lua
-- Silksong-style world bars. Track bosses via cEnemyContext.get_IsAngry
-- plus IsBoss and HealthManager.

local HealthBars = _G.MHHealthBars or {}
_G.MHHealthBars = HealthBars

HealthBars.enabled = true
HealthBars.max_draw_dist = 55
HealthBars.show_hp_text = true
HealthBars.show_dist = true
HealthBars.scale = 1.5

local STALE_S = 1.0
local FLOAT_S = 1.2
local BASE_SCALE = 1.5
local BASE_FONT = 16
local CHAR_W = 7

local function bar_scale()
    local s = HealthBars.scale
    if type(s) ~= "number" or s < BASE_SCALE then
        return BASE_SCALE
    end
    if s > 2.5 then
        return 2.5
    end
    return s
end

local function font_px()
    return BASE_FONT * (bar_scale() / BASE_SCALE)
end

local COL_FILL = 0xFF2A2AD9
local COL_EMPTY = 0xE6000000
local COL_LINE = 0xFF000000
local COL_TEXT = 0xFF2A2AD9
local COL_NAME = 0xFFE8E8E8
local COL_SHADOW = 0xFF000000
local COL_FLOAT = 0xFF3333FF

local bosses = {}
local installed = false

local enemy_context_td = sdk.find_type_definition("app.cEnemyContext")
local get_is_angry = enemy_context_td and enemy_context_td:get_method("get_IsAngry")
local get_is_boss = enemy_context_td and enemy_context_td:get_method("get_IsBoss")
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

if get_browser then
    local browser_td = get_browser:get_return_type()
    context_field = browser_td and browser_td:get_field("_Context")
    if context_field then
        local holder_td = context_field:get_type()
        get_chara = holder_td and holder_td:get_method("get_Chara")
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

local enemy_def_td = sdk.find_type_definition("app.EnemyDef")
name_string = enemy_def_td and enemy_def_td:get_method("NameString")

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
    if trimmed == "" then
        return true
    end
    if trimmed:match("^[%?？─%-]+$") then
        return true
    end
    return false
end

local function vec3(pos)
    if pos == nil then
        return nil
    end
    local x, y, z = pos.x, pos.y, pos.z
    if type(x) ~= "number" or type(y) ~= "number" or type(z) ~= "number" then
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

local function world_pos(boss)
    local ctx = boss.enemy_context
    local x, y, z = read_vec3(ctx, { "get_ModelCenterPos", "ModelCenterPos", "get_GroundPos", "GroundPos" })
    if x then
        return x, y, z
    end
    for _, obj in ipairs({ boss.health_manager, boss.character, ctx }) do
        x, y, z = read_vec3(obj, { "get_Position", "get_Pos" })
        if x then
            return x, y, z
        end
        if is_managed(obj) then
            local ok, go = pcall(function()
                return obj:call("get_GameObject")
            end)
            if ok and is_managed(go) then
                local ok_t, trans = pcall(function()
                    return go:call("get_Transform")
                end)
                if ok_t then
                    x, y, z = read_vec3(trans, { "get_Position" })
                    if x then
                        return x, y, z
                    end
                end
            end
        end
    end
    return nil
end

local function camera_pos()
    local ok, cam = pcall(function()
        if sdk.get_primary_camera then
            return sdk.get_primary_camera()
        end
        return nil
    end)
    if not ok or not is_managed(cam) then
        return nil
    end
    local go = nil
    ok, go = pcall(function()
        if not is_managed(cam) then
            return nil
        end
        return cam:call("get_GameObject")
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
    if not is_managed(chara) then
        return nil
    end
    local x, y, z = read_vec3(chara, { "get_Position", "get_Pos" })
    if x then
        return x, y, z
    end
    local ok, go = pcall(function()
        return chara:call("get_GameObject")
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

local function dist3(x, y, z, ox, oy, oz)
    if ox == nil then
        return nil
    end
    local dx, dy, dz = x - ox, y - oy, z - oz
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function too_far(x, y, z, cx, cy, cz)
    local max_d = HealthBars.max_draw_dist
    if type(max_d) ~= "number" or max_d <= 0 then
        return false
    end
    if cx == nil then
        return false
    end
    local dx, dy, dz = x - cx, y - cy, z - cz
    return (dx * dx + dy * dy + dz * dz) > (max_d * max_d)
end

local function to_screen(x, y, z)
    if not draw or not draw.world_to_screen or not Vector3f then
        return nil
    end
    local ok, screen = pcall(draw.world_to_screen, Vector3f.new(x, y, z))
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

local function on_update(enemy_context)
    if not HealthBars.enabled then
        return
    end
    if not is_managed(enemy_context) then
        return
    end

    local boss = bosses[enemy_context]
    if boss == nil then
        local is_boss = call(get_is_boss, enemy_context)
        if is_boss ~= true then
            return
        end

        local browser = call(get_browser, enemy_context)
        if not is_managed(browser) or not context_field then
            return
        end

        local holder = context_field:get_data(browser)
        if not is_managed(holder) then
            return
        end

        local character = call(get_chara, holder)
        if not is_managed(character) then
            return
        end

        local health_manager = call(get_health_manager, character)
        if not is_managed(health_manager) then
            return
        end

        local em_id = call(get_em_id, enemy_context)
        local role_id = call(get_role_id, enemy_context)
        local legendary_id = call(get_legendary_id, enemy_context)
        if em_id == nil or role_id == nil or legendary_id == nil then
            return
        end

        local name = as_name(call(name_string, nil, em_id, role_id, legendary_id))
        if dummy_name(name) then
            return
        end

        boss = {
            name = name,
            enemy_context = enemy_context,
            character = character,
            health_manager = health_manager,
            health = -1,
            max_health = -1,
            prev_health = nil,
            floats = {},
            last_update = 0,
        }
    end

    local health = call(get_health, boss.health_manager)
    if health == nil then
        return
    end
    local max_health = call(get_max_health, boss.health_manager)
    if max_health == nil or max_health <= 0 then
        return
    end

    if boss.prev_health ~= nil and health < boss.prev_health - 0.5 then
        local floats = boss.floats
        floats[#floats + 1] = {
            amount = boss.prev_health - health,
            born = os.clock(),
        }
        if #floats > 8 then
            table.remove(floats, 1)
        end
    end

    boss.health = health
    boss.max_health = max_health
    boss.prev_health = health
    boss.last_update = os.clock()
    bosses[enemy_context] = boss
end

local function draw_bar(sx, sy, pct)
    local s = bar_scale()
    local bar_w = 110 * s
    local bar_h = 12 * s
    local x = sx - bar_w * 0.5
    local y = sy
    if pct > 1 then
        pct = 1
    end
    if pct < 0 then
        pct = 0
    end
    draw.filled_rect(x, y, bar_w, bar_h, COL_EMPTY)
    local fill = bar_w * pct
    if fill > 0.5 then
        draw.filled_rect(x, y, fill, bar_h, COL_FILL)
    end
    draw.outline_rect(x, y, bar_w, bar_h, COL_LINE)
end

local function measure_text(text)
    if imgui and imgui.calc_text_size then
        local ok, size = pcall(imgui.calc_text_size, text)
        if ok and size and type(size.x) == "number" then
            return size.x, size.y
        end
    end
    local px = font_px()
    return #text * CHAR_W * (px / BASE_FONT), px
end

local function draw_centered(text, cx, cy, color)
    local pushed = false
    if imgui and imgui.push_font_size then
        pushed = pcall(imgui.push_font_size, font_px())
    end
    local w, h = measure_text(text)
    local x = cx - w * 0.5
    local y = cy
    local dl = imgui and imgui.get_foreground_draw_list and imgui.get_foreground_draw_list()
    if dl and dl.add_text then
        pcall(function()
            dl:add_text({ x + 1, y + 1 }, COL_SHADOW, text)
            dl:add_text({ x, y }, color, text)
        end)
    else
        draw.text(text, x + 1, y + 1, COL_SHADOW)
        draw.text(text, x, y, color)
    end
    if pushed and imgui.pop_font_size then
        pcall(imgui.pop_font_size)
    end
    return h
end

local function draw_boss(boss, now, cx, cy, cz, hx, hy, hz)
    local x, y, z = world_pos(boss)
    if x == nil then
        return
    end
    if too_far(x, y, z, cx, cy, cz) then
        return
    end
    local sx, sy = to_screen(x, y, z)
    if sx == nil then
        return
    end
    local s = bar_scale()
    local px = font_px()
    local bar_h = 12 * s
    sy = sy - (24 * s + px)

    local pct = boss.health / boss.max_health
    draw_bar(sx, sy, pct)
    local label = boss.name
    if HealthBars.show_dist then
        local meters = dist3(x, y, z, hx, hy, hz)
        if meters then
            label = string.format("%s  %.0fm", boss.name, meters)
        end
    end
    draw_centered(label, sx, sy - px - 2, COL_NAME)
    if HealthBars.show_hp_text then
        draw_centered(string.format("%.0f/%.0f", boss.health, boss.max_health), sx, sy + (bar_h - px) * 0.5, COL_TEXT)
    end

    local keep = {}
    for _, flt in ipairs(boss.floats) do
        local age = now - flt.born
        if age < FLOAT_S then
            local rise = age / FLOAT_S
            local fy = sy - px - 14 - rise * (28 * s)
            draw_centered(string.format("-%.0f", flt.amount), sx, fy, COL_FLOAT)
            keep[#keep + 1] = flt
        end
    end
    boss.floats = keep
end

local function on_frame()
    if not HealthBars.enabled then
        return
    end

    local now = os.clock()
    local cx, cy, cz = camera_pos()
    local hx, hy, hz = hunter_pos()
    if hx == nil then
        hx, hy, hz = cx, cy, cz
    end
    local drop = {}
    for ctx, boss in pairs(bosses) do
        local live_float = false
        for _, flt in ipairs(boss.floats) do
            if (now - flt.born) < FLOAT_S then
                live_float = true
                break
            end
        end
        if (boss.health <= 0 or (now - boss.last_update) > STALE_S) and not live_float then
            drop[#drop + 1] = ctx
        else
            pcall(draw_boss, boss, now, cx, cy, cz, hx, hy, hz)
        end
    end
    for _, ctx in ipairs(drop) do
        bosses[ctx] = nil
    end
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
    re.on_frame(function()
        pcall(on_frame)
    end)
end

HealthBars.install()
return HealthBars
