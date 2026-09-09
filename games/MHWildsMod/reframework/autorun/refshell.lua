-- refshell.lua
-- Reusable ImGui trainer shell for REFramework.
-- Other mods: local RefShell = require("refshell")  or  _G.RefShell
--
-- Persist (same host API as UE4SS ConfigManager, REF json instead of a parser):
--   local cfg = RefShell.Config.create({
--       id = "MyMod",
--       defaults = { volume = 1 },
--   })
--   cfg:Get("volume")
--   cfg:Set("volume", 0.5)  -- writes reframework/data/refshell_MyMod.json
--
-- Menus: create({ persist = features }) remembers toggles / sliders / combos.
--
-- REFramework has no BeginTabBar binding, so tabs are custom buttons.
-- Style colors use stable ImGuiCol indices + RGBA tables.

local RefShell = _G.RefShell or {}
_G.RefShell = RefShell

local COL = {
    Text = 0,
    TextDisabled = 1,
    WindowBg = 2,
    ChildBg = 3,
    PopupBg = 4,
    Border = 5,
    BorderShadow = 6,
    FrameBg = 7,
    FrameBgHovered = 8,
    FrameBgActive = 9,
    TitleBg = 10,
    TitleBgActive = 11,
    TitleBgCollapsed = 12,
    MenuBarBg = 13,
    ScrollbarBg = 14,
    ScrollbarGrab = 15,
    ScrollbarGrabHovered = 16,
    ScrollbarGrabActive = 17,
    CheckMark = 18,
    SliderGrab = 19,
    SliderGrabActive = 20,
    Button = 21,
    ButtonHovered = 22,
    ButtonActive = 23,
    Header = 24,
    HeaderHovered = 25,
    HeaderActive = 26,
    Separator = 27,
    SeparatorHovered = 28,
    SeparatorActive = 29,
    ResizeGrip = 30,
    ResizeGripHovered = 31,
    ResizeGripActive = 32,
}

local WIN = {
    NoTitleBar = 1,
    NoResize = 2,
    NoMove = 4,
    NoScrollbar = 8,
    NoCollapse = 32,
    AlwaysAutoResize = 64,
    NoSavedSettings = 256,
}

local COND = {
    Always = 1,
    Once = 2,
    FirstUseEver = 4,
    Appearing = 8,
}

local VK_NAMES = {
    [0x08] = "Backspace",
    [0x09] = "Tab",
    [0x0D] = "Enter",
    [0x10] = "Shift",
    [0x11] = "Ctrl",
    [0x12] = "Alt",
    [0x1B] = "Esc",
    [0x20] = "Space",
    [0x25] = "Left",
    [0x26] = "Up",
    [0x27] = "Right",
    [0x28] = "Down",
    [0x2D] = "Insert",
    [0x2E] = "Delete",
    [0x70] = "F1",
    [0x71] = "F2",
    [0x72] = "F3",
    [0x73] = "F4",
    [0x74] = "F5",
    [0x75] = "F6",
    [0x76] = "F7",
    [0x77] = "F8",
    [0x78] = "F9",
    [0x79] = "F10",
    [0x7A] = "F11",
    [0x7B] = "F12",
    [0xC0] = "~",
}

local function vk_name(vk)
    if VK_NAMES[vk] then
        return VK_NAMES[vk]
    end
    if vk >= 0x30 and vk <= 0x39 then
        return string.char(vk)
    end
    if vk >= 0x41 and vk <= 0x5A then
        return string.char(vk)
    end
    return string.format("VK 0x%02X", vk)
end

local THEMES = {
    midnight = {
        window   = { 0.08, 0.08, 0.10, 0.94 },
        child    = { 0.00, 0.00, 0.00, 0.00 },
        title    = { 0.06, 0.06, 0.07, 1.00 },
        border   = { 0.28, 0.28, 0.32, 0.80 },
        text     = { 0.92, 0.93, 0.95, 1.00 },
        muted    = { 0.62, 0.64, 0.68, 1.00 },
        frame    = { 0.14, 0.15, 0.17, 1.00 },
        frame_h  = { 0.20, 0.22, 0.26, 1.00 },
        button   = { 0.18, 0.19, 0.22, 1.00 },
        button_h = { 0.24, 0.26, 0.30, 1.00 },
        button_a = { 0.12, 0.55, 0.58, 1.00 },
        header   = { 0.16, 0.17, 0.20, 1.00 },
        header_h = { 0.22, 0.24, 0.28, 1.00 },
        accent   = { 0.20, 0.82, 0.88, 1.00 },
        accent_d = { 0.10, 0.42, 0.46, 1.00 },
        selected = { 0.16, 0.48, 0.28, 1.00 },
        check    = { 0.20, 0.82, 0.88, 1.00 },
        sep      = { 0.32, 0.33, 0.36, 0.70 },
        grab     = { 0.20, 0.82, 0.88, 1.00 },
    },
}

local function copy_defaults(dst, src)
    for k, v in pairs(src) do
        if dst[k] == nil then
            dst[k] = v
        elseif type(v) == "table" and type(dst[k]) == "table" and not v[1] then
            copy_defaults(dst[k], v)
        end
    end
    return dst
end

local function deep_copy(value, seen)
    if type(value) ~= "table" then
        return value
    end
    seen = seen or {}
    if seen[value] then
        error("RefShell.Config: circular table")
    end
    seen[value] = true
    local out = {}
    for k, v in pairs(value) do
        out[deep_copy(k, seen)] = deep_copy(v, seen)
    end
    seen[value] = nil
    return out
end

local function deep_equal(a, b)
    if a == b then
        return true
    end
    if type(a) ~= type(b) or type(a) ~= "table" then
        return false
    end
    for k, v in pairs(a) do
        if not deep_equal(v, b[k]) then
            return false
        end
    end
    for k in pairs(b) do
        if a[k] == nil then
            return false
        end
    end
    return true
end

local function is_json_safe(value)
    local t = type(value)
    if value == nil or t == "boolean" or t == "string" then
        return true
    end
    if t == "number" then
        return value == value and value ~= math.huge and value ~= -math.huge
    end
    if t ~= "table" then
        return false
    end
    for k, v in pairs(value) do
        local kt = type(k)
        if kt ~= "string" and kt ~= "number" then
            return false
        end
        if not is_json_safe(v) then
            return false
        end
    end
    return true
end

-- Tiny JSON key/value store. Files live in reframework/data/ via json.load_file.
-- Hosts still own when to Set (or use create({ persist = tbl }) on a menu).
local function create_config(opts)
    opts = opts or {}
    if type(opts.id) ~= "string" or opts.id == "" then
        error("RefShell.Config: id must be a non-empty string")
    end
    if opts.defaults ~= nil and type(opts.defaults) ~= "table" then
        error("RefShell.Config: defaults must be a table")
    end
    if opts.defaults ~= nil and not is_json_safe(opts.defaults) then
        error("RefShell.Config: defaults must be JSON-safe")
    end

    local id = opts.id
    local file_path = opts.file
    if type(file_path) ~= "string" or file_path == "" then
        file_path = "refshell_" .. id .. ".json"
    end
    local autosave = opts.autosave ~= false
    local defaults = deep_copy(opts.defaults or {})
    local store = {}
    local load_failed = false
    local cfg = {}

    local function merge_loaded(loaded)
        store = deep_copy(defaults)
        if type(loaded) ~= "table" then
            return
        end
        for k, v in pairs(loaded) do
            if type(k) == "string" then
                store[k] = deep_copy(v)
            end
        end
    end

    local loaded = nil
    local ok_load, result = pcall(json.load_file, file_path)
    if ok_load then
        loaded = result
    end
    if loaded == nil then
        merge_loaded(nil)
        log.info(string.format("[RefShell.Config] %s: no config yet (%s)", id, file_path))
    elseif type(loaded) ~= "table" then
        load_failed = true
        merge_loaded(nil)
        log.error(string.format("[RefShell.Config] %s: %s is not an object (file left untouched)", id, file_path))
    else
        merge_loaded(loaded)
        log.info(string.format("[RefShell.Config] %s: loaded %s", id, file_path))
    end

    function cfg:has(key)
        return type(key) == "string" and store[key] ~= nil
    end

    function cfg:Get(key)
        if type(key) ~= "string" or key == "" then
            error("RefShell.Config:Get: key must be a non-empty string")
        end
        local value = store[key]
        if value == nil then
            value = defaults[key]
        end
        return deep_copy(value)
    end

    function cfg:Set(key, value)
        if type(key) ~= "string" or key == "" then
            error("RefShell.Config:Set: key must be a non-empty string")
        end
        if value ~= nil and not is_json_safe(value) then
            error("RefShell.Config:Set: value must be JSON-safe")
        end

        local current = store[key]
        if current == nil then
            current = defaults[key]
        end
        if deep_equal(current, value) then
            return
        end

        if value == nil then
            store[key] = nil
        else
            store[key] = deep_copy(value)
        end
        load_failed = false
        if autosave then
            cfg:Save()
        end
    end

    function cfg:Save()
        if load_failed then
            log.error(string.format("[RefShell.Config] %s: skip save, %s did not parse", id, file_path))
            return false
        end
        local out = {}
        for k, v in pairs(store) do
            out[k] = v
        end
        local ok, err = pcall(json.dump_file, file_path, out, 4)
        if not ok then
            log.error(string.format("[RefShell.Config] %s: save failed %s — %s", id, file_path, tostring(err)))
            return false
        end
        return true
    end

    function cfg:File()
        return file_path
    end

    return cfg
end

RefShell.Config = {
    create = create_config,
    Init = create_config,
}

-- ImGuiStyleVar enum is not bound on REF 1.5.9. Indices are ImGui 1.83+
-- (DisabledAlpha inserted at 1). Wrong type on a slot is skipped via pcall.
--
-- REF push_style_color only accepts Vector4f or a packed int. Lua tables are
-- a silent no-op, so counting those "pushes" and popping them trips
-- PopStyleColor / PopStyleVar too many times.
local SV = {
    WindowPadding = 2,
    WindowRounding = 3,
    WindowBorderSize = 4,
    WindowTitleAlign = 6,
    FramePadding = 11,
    FrameRounding = 12,
    ItemSpacing = 14,
    ScrollbarRounding = 19,
    GrabRounding = 21,
}

local function as_vec4(rgba)
    if type(rgba) ~= "table" then
        return rgba
    end
    if not Vector4f or not Vector4f.new then
        return nil
    end
    return Vector4f.new(rgba[1] or 0, rgba[2] or 0, rgba[3] or 0, rgba[4] or 1)
end

local function as_vec2(value)
    if type(value) ~= "table" then
        return value
    end
    if not Vector2f or not Vector2f.new then
        return nil
    end
    return Vector2f.new(value[1] or 0, value[2] or 0)
end

local function push_color(idx, rgba)
    local color = as_vec4(rgba)
    if color == nil then
        return false
    end
    return pcall(imgui.push_style_color, idx, color)
end

local function push_theme(theme)
    local t = theme or THEMES.midnight
    local color_n = 0
    local var_n = 0

    local function c(idx, rgba)
        if push_color(idx, rgba) then
            color_n = color_n + 1
        end
    end

    local function v(idx, value)
        local packed = as_vec2(value)
        if packed == nil then
            return
        end
        if pcall(imgui.push_style_var, idx, packed) then
            var_n = var_n + 1
        end
    end

    c(COL.Text, t.text)
    c(COL.TextDisabled, t.muted)
    c(COL.WindowBg, t.window)
    c(COL.ChildBg, t.child)
    c(COL.PopupBg, t.window)
    c(COL.Border, t.border)
    c(COL.FrameBg, t.frame)
    c(COL.FrameBgHovered, t.frame_h)
    c(COL.FrameBgActive, t.frame)
    c(COL.TitleBg, t.title)
    c(COL.TitleBgActive, t.title)
    c(COL.TitleBgCollapsed, t.title)
    c(COL.CheckMark, t.check)
    c(COL.SliderGrab, t.grab)
    c(COL.SliderGrabActive, t.accent)
    c(COL.Button, t.button)
    c(COL.ButtonHovered, t.button_h)
    c(COL.ButtonActive, t.button_a)
    c(COL.Header, t.header)
    c(COL.HeaderHovered, t.header_h)
    c(COL.HeaderActive, t.accent_d)
    c(COL.Separator, t.sep)
    c(COL.ScrollbarBg, { 0.05, 0.05, 0.06, 0.60 })
    c(COL.ScrollbarGrab, { 0.32, 0.33, 0.36, 1.00 })
    c(COL.ResizeGrip, { 0.20, 0.82, 0.88, 0.35 })
    c(COL.ResizeGripHovered, t.accent)

    v(SV.WindowRounding, 8)
    v(SV.WindowBorderSize, 1)
    v(SV.WindowPadding, { 14, 16 })
    v(SV.FrameRounding, 4)
    v(SV.FramePadding, { 8, 5 })
    v(SV.ItemSpacing, { 8, 6 })
    v(SV.GrabRounding, 4)
    v(SV.ScrollbarRounding, 6)
    v(SV.WindowTitleAlign, { 0.5, 0.5 })

    return color_n, var_n
end

local function pop_theme(color_n, var_n)
    if color_n > 0 then
        pcall(imgui.pop_style_color, color_n)
    end
    if var_n > 0 then
        pcall(imgui.pop_style_var, var_n)
    end
end

local function display_size()
    local ok, size = pcall(imgui.get_display_size)
    if ok and size then
        return size.x, size.y
    end
    return 1920, 1080
end

local function dock_pos(dock, width, height, margin)
    local dw, dh = display_size()
    local y = margin
    if y < 8 then
        y = 8
    end
    if height > dh - margin * 2 then
        height = dh - margin * 2
    end
    if width > dw - margin * 2 then
        width = math.max(240, dw - margin * 2)
    end
    if dock == "left" then
        return margin, y
    elseif dock == "center" then
        return (dw - width) * 0.5, y
    end
    return dw - width - margin, y
end

local function fitted_height(margin)
    local _, dh = display_size()
    local h = dh - margin * 2
    if h < 320 then
        h = math.max(200, dh - 8)
    end
    return h
end

-- Mirror the current left inset on the right so rows share one width.
local function content_width()
    local size = imgui.get_window_size()
    local cursor = imgui.get_cursor_pos()
    local left = 14
    if cursor and cursor.x then
        left = cursor.x
    end
    local w = 320
    if size and size.x then
        w = size.x - left * 2
    end
    if w < 120 then
        w = 120
    end
    return w
end

local function make_ui(menu)
    local ui = {}
    local theme = menu.theme

    function ui.theme()
        return theme
    end

    function ui.section(title, draw_fn, default_open)
        if default_open == nil then
            default_open = true
        end
        if default_open then
            imgui.set_next_item_open(true, COND.FirstUseEver)
        end
        if imgui.collapsing_header(title .. "##sec") then
            imgui.indent(6)
            draw_fn()
            imgui.unindent(6)
            imgui.spacing()
        end
    end

    function ui.label(text)
        imgui.text(text)
    end

    local function note_width()
        local win = imgui.get_window_size()
        local cursor = imgui.get_cursor_pos()
        if win and cursor and win.x and cursor.x then
            return math.max(48, win.x - cursor.x - 18)
        end
        return 340
    end

    local function text_width(s)
        local ok, sz = pcall(imgui.calc_text_size, s)
        if ok and sz then
            return sz.x or sz[1] or (#s * 7)
        end
        return #s * 7
    end

    local function wrap_note(text, max_w)
        text = tostring(text or "")
        local out = {}
        for para in (text .. "\n"):gmatch("(.-)\n") do
            if para == "" then
                out[#out + 1] = ""
            else
                local line = ""
                for word in para:gmatch("%S+") do
                    local trial = (line == "") and word or (line .. " " .. word)
                    if line ~= "" and text_width(trial) > max_w then
                        out[#out + 1] = line
                        line = word
                    else
                        line = trial
                    end
                end
                if line ~= "" then
                    out[#out + 1] = line
                end
            end
        end
        if #out == 0 then
            out[1] = text
        end
        return out
    end

    function ui.muted(text)
        for _, line in ipairs(wrap_note(text, note_width())) do
            imgui.text_colored(line, 0xFFA0A3AD)
        end
    end

    function ui.kv(key, value)
        local text = tostring(key) .. ":  " .. tostring(value)
        for _, line in ipairs(wrap_note(text, note_width())) do
            imgui.text(line)
        end
    end

    function ui.separator()
        imgui.separator()
    end

    function ui.spacing()
        imgui.spacing()
    end

    function ui.toggle(label, value)
        return imgui.checkbox(label, value and true or false)
    end

    function ui.bind_toggle(label, tbl, key)
        local changed, value = imgui.checkbox(label, tbl[key] and true or false)
        if changed then
            tbl[key] = value
            menu.dirty = true
        end
        return changed, value
    end

    function ui.bind_hotkey(label, tbl, key)
        local vk = tbl[key]
        local name = (type(vk) == "number" and vk > 0) and vk_name(vk) or "None"
        local dest = menu.rebinding
        local waiting = dest and dest.tbl == tbl and dest.key == key
        imgui.text(label .. ":  " .. name)
        if waiting then
            ui.muted("Press a key...  (Esc to cancel)")
        elseif imgui.button("Rebind##" .. tostring(label) .. tostring(key), { -1, 28 }) then
            menu.rebinding = { tbl = tbl, key = key }
        end
    end

    function ui.slider_float(label, value, min_v, max_v, fmt)
        imgui.push_item_width(-1)
        local changed, new_v = imgui.slider_float(label, value, min_v, max_v, fmt)
        imgui.pop_item_width()
        return changed, new_v
    end

    function ui.bind_slider(label, tbl, key, min_v, max_v, fmt)
        local changed, value = ui.slider_float(label, tbl[key], min_v, max_v, fmt)
        if changed then
            tbl[key] = value
            menu.dirty = true
        end
        return changed, value
    end

    -- items: values, or {value, label}. tbl[key] stores the selected value.
    -- imgui.combo is 1-based in REFramework.
    function ui.bind_combo(label, tbl, key, items)
        local labels = {}
        local values = {}
        local current = 1
        for i, item in ipairs(items) do
            if type(item) == "table" then
                values[i] = item[1] or item.value
                labels[i] = item[2] or item.label or tostring(values[i])
            else
                values[i] = item
                labels[i] = tostring(item)
            end
            if tbl[key] == values[i] then
                current = i
            end
        end

        imgui.text(label)
        imgui.push_item_width(-1)
        local changed, new_i
        if imgui.combo then
            changed, new_i = imgui.combo("##" .. label, current, labels)
        else
            new_i = ui.choice_grid(labels, current, math.min(#labels, 3))
            changed = new_i ~= current
        end
        imgui.pop_item_width()

        if changed and new_i and values[new_i] ~= nil then
            tbl[key] = values[new_i]
            menu.dirty = true
            return true, values[new_i]
        end
        return false, tbl[key]
    end

    function ui.button(label, width, height)
        return imgui.button(label, { width or -1, height or 28 })
    end

    function ui.actions(items, columns)
        columns = columns or 2
        local avail = content_width()
        local gap = 8
        local btn_w = (avail - gap * (columns - 1)) / columns
        local btn_h = 30

        for i, item in ipairs(items) do
            local label = item[1] or item.label
            local fn = item[2] or item.on_click
            local col = (i - 1) % columns
            if col > 0 then
                imgui.same_line()
            end
            imgui.push_id(i)
            if imgui.button(label, { btn_w, btn_h }) and fn then
                fn()
            end
            imgui.pop_id()
        end
    end

    function ui.choice_grid(items, selected, columns)
        columns = columns or 2
        local avail = content_width()
        local gap = 8
        local btn_w = (avail - gap * (columns - 1)) / columns
        local btn_h = 28
        local result = selected

        for i, item in ipairs(items) do
            local label = item
            if type(item) == "table" then
                label = item[1] or item.label
            end
            local col = (i - 1) % columns
            if col > 0 then
                imgui.same_line()
            end

            local is_sel = (i == selected)
            local sel_pushed = 0
            if is_sel then
                if push_color(COL.Button, theme.selected) then
                    sel_pushed = sel_pushed + 1
                end
                if push_color(COL.ButtonHovered, theme.selected) then
                    sel_pushed = sel_pushed + 1
                end
            end
            imgui.push_id(1000 + i)
            if imgui.button(label, { btn_w, btn_h }) then
                result = i
                menu.dirty = true
            end
            imgui.pop_id()
            if sel_pushed > 0 then
                imgui.pop_style_color(sel_pushed)
            end
        end

        return result
    end

    function ui.shell_settings()
        ui.section("Window", function()
            ui.muted("Docks to the chosen side when you open the menu or the game window size changes.")
            ui.muted("Settings and cheats save to reframework/data/" .. menu:config_path())
            imgui.spacing()
            ui.actions({
                { "Dock Right",  function() menu:dock_now("right") end },
                { "Dock Left",   function() menu:dock_now("left") end },
                { "Dock Center", function() menu:dock_now("center") end },
                { "Reset Size",  function() menu:reset_size() end },
            }, 2)
        end, true)

        ui.section("Keybind", function()
            ui.bind_hotkey("Toggle menu", menu.cfg, "toggle_vk")
            if type(menu.extra_keybinds) == "function" then
                menu.extra_keybinds(ui)
            end
        end, true)
    end

    return ui
end

function RefShell.create(opts)
    opts = opts or {}
    local menu = {
        id = opts.id or "menu",
        title = opts.title or "TRAINER",
        theme = opts.theme or THEMES.midnight,
        tabs = {},
        active_tab = 1,
        dirty = false,
        rebinding = false,
        pending_dock = nil,
        pending_size = false,
        apply_layout = false,
        key_was_down = false,
        bound = false,
        ui = nil,
        lock_camera = opts.lock_camera ~= false,
        lock_cursor = opts.lock_cursor ~= false,
        can_open = opts.can_open,
        on_open_blocked = opts.on_open_blocked,
    }

    menu.cfg = copy_defaults(opts.config or {}, {
        open = opts.start_open or false,
        toggle_vk = opts.toggle_vk or 0x75,
        width = opts.width or 400,
        height = opts.height or 620,
        dock = opts.dock or "right",
        margin = opts.margin or 16,
        layout_rev = 0,
    })
    menu._persist = opts.persist

    menu.ui = make_ui(menu)

    function menu:config_path()
        return "refshell_" .. self.id .. ".json"
    end

    function menu:remember(tbl)
        self._persist = tbl
        return self
    end

    function menu:apply_store(tbl)
        if not tbl or not self.config then
            return
        end
        for k, _ in pairs(tbl) do
            if self.config:has(k) then
                tbl[k] = self.config:Get(k)
            end
        end
    end

    function menu:sync_store(tbl)
        if not tbl or not self.config then
            return
        end
        for k, v in pairs(tbl) do
            if is_json_safe(v) then
                self.config:Set(k, v)
            end
        end
    end

    function menu:load()
        if not self.config then
            self.config = create_config({
                id = self.id,
                file = self:config_path(),
                defaults = deep_copy(self.cfg),
                autosave = false,
            })
        end
        self:apply_store(self.cfg)
        self:apply_store(self._persist)
        -- Bump when default dock size/padding changes.
        if (self.cfg.layout_rev or 0) < 3 then
            self.cfg.layout_rev = 3
            self.cfg.width = opts.width or self.cfg.width
            self.cfg.margin = opts.margin or self.cfg.margin
            self.apply_layout = true
            self.dirty = true
        end
    end

    function menu:save()
        if not self.config then
            return
        end
        self:sync_store(self.cfg)
        self:sync_store(self._persist)
        self.config:Save()
        self.dirty = false
    end

    function menu:add_tab(name, draw_fn)
        self.tabs[#self.tabs + 1] = { name = name, draw = draw_fn }
        return self
    end

    function menu:dock_now(side)
        self.cfg.dock = side
        self.pending_dock = side
        self.pending_size = true
        self.dirty = true
    end

    function menu:reset_size()
        self.pending_size = true
        self.apply_layout = true
        self.dirty = true
    end

    function menu:current_size()
        local dw = display_size()
        local margin = self.cfg.margin or 16
        local w = self.cfg.width or 400
        local max_w = dw - margin * 2
        if w > max_w then
            w = math.max(240, max_w)
        end
        return w, fitted_height(margin)
    end

    -- Pixel pos is not saved. Re-dock when the menu opens or the game
    -- window size changes so a resolution swap cannot leave it off-screen.
    function menu:refresh_layout()
        local dw, dh = display_size()
        local opened = self._just_opened
        self._just_opened = false
        local resized = self._disp_w ~= dw or self._disp_h ~= dh
        if resized then
            self._disp_w = dw
            self._disp_h = dh
        end
        if opened or resized then
            self.apply_layout = true
        end
    end

    function menu:has_tab(name)
        for i = 1, #self.tabs do
            if self.tabs[i].name == name then
                return true
            end
        end
        return false
    end

    local function draw_tabs(self)
        local n = #self.tabs
        if n == 0 then
            return
        end

        -- same_line() uses ItemSpacing.x (we push 8). Widths must use that gap
        -- or the last tab misses the right edge.
        local pad_y = 10
        local gap = 8
        local tab_h = 28

        local origin_pos = imgui.get_cursor_pos()
        local left = (origin_pos and origin_pos.x) or 14
        imgui.set_cursor_pos({ left, ((origin_pos and origin_pos.y) or 0) + pad_y })

        local avail = content_width()
        local inner = avail - gap * (n - 1)
        local base_w = math.floor(inner / n)
        local leftover = inner - base_w * n

        for i, tab in ipairs(self.tabs) do
            if i > 1 then
                imgui.same_line()
            end
            local tab_w = base_w
            if i == n then
                tab_w = base_w + leftover
            end
            local origin = imgui.get_cursor_screen_pos()
            local active = (i == self.active_tab)
            local tab_pushed = 0
            if active then
                if push_color(COL.Button, self.theme.accent_d) then
                    tab_pushed = tab_pushed + 1
                end
                if push_color(COL.ButtonHovered, self.theme.accent_d) then
                    tab_pushed = tab_pushed + 1
                end
                if push_color(COL.Text, self.theme.accent) then
                    tab_pushed = tab_pushed + 1
                end
            end
            if imgui.button(tab.name, { tab_w, tab_h }) then
                self.active_tab = i
            end
            if tab_pushed > 0 then
                imgui.pop_style_color(tab_pushed)
                -- Underline sits just under the button so label padding stays even.
                pcall(function()
                    local dl = imgui.get_window_draw_list()
                    if dl and origin then
                        dl:add_rect_filled(
                            { origin.x, origin.y + tab_h },
                            { origin.x + tab_w, origin.y + tab_h + 2 },
                            0xFFE0D133,
                            0,
                            0
                        )
                    end
                end)
            end
        end

        local row_top = ((origin_pos and origin_pos.y) or 0) + pad_y
        imgui.set_cursor_pos({ left, row_top + tab_h + pad_y })
        imgui.separator()
    end

    function menu:draw_window()
        self:refresh_layout()
        local w, h = self:current_size()

        if self.apply_layout or self.pending_dock then
            local side = self.pending_dock or self.cfg.dock
            local x, y = dock_pos(side, w, h, self.cfg.margin)
            imgui.set_next_window_pos({ x, y }, COND.Always)
            imgui.set_next_window_size({ w, h }, COND.Always)
            self.pending_dock = nil
            self.pending_size = false
            self.apply_layout = false
        elseif self.pending_size then
            imgui.set_next_window_size({ w, h }, COND.Always)
            self.pending_size = false
        end

        local color_n, var_n = push_theme(self.theme)
        local still_open = imgui.begin_window(self.title, true, WIN.NoCollapse + WIN.NoSavedSettings)
        if still_open then
            -- Safety net if ImGui or a lagged display size left us off-screen.
            local pos_ok, pos = pcall(imgui.get_window_pos)
            local size_ok, size = pcall(imgui.get_window_size)
            if pos_ok and size_ok and pos and size then
                local dw, dh = display_size()
                local on_screen = pos.x + size.x > 16
                    and pos.y + size.y > 16
                    and pos.x < dw - 16
                    and pos.y < dh - 16
                if not on_screen then
                    self.apply_layout = true
                end
            end
            local ok, err = pcall(function()
                draw_tabs(self)

                local win = imgui.get_window_size()
                local cursor = imgui.get_cursor_pos()
                local close_h = 40
                local body_h = 400
                if win and cursor then
                    body_h = win.y - cursor.y - close_h - 12
                end
                if body_h < 100 then
                    body_h = 100
                end

                imgui.begin_child_window("##refshell_body", { 0, body_h }, false)
                local tab = self.tabs[self.active_tab]
                if tab and tab.draw then
                    tab.draw(self.ui, self)
                end
                imgui.end_child_window()

                imgui.spacing()
                if imgui.button("Close", { -1, 30 }) then
                    still_open = false
                end
            end)
            if not ok then
                imgui.text_colored("UI error: " .. tostring(err), 0xFF6666FF)
            end
        end
        imgui.end_window()
        pop_theme(color_n, var_n)

        if not still_open then
            self.cfg.open = false
            self.dirty = true
        end
    end

    -- Bootstrap-style alert: slides up from the bottom, then out.
    function menu:toast(text, kind, duration_ms)
        self._toast = {
            text = tostring(text or ""),
            kind = kind or "warning",
            started = os.clock(),
            duration = (duration_ms or 500) / 1000,
        }
    end

    function menu:draw_toast()
        local toast = self._toast
        if not toast then
            return
        end
        local now = os.clock()
        local age = now - toast.started
        if age >= toast.duration or toast.text == "" then
            self._toast = nil
            return
        end

        local slide = 0.08
        local lift = 36
        local offset = 0
        if age < slide then
            offset = (1 - age / slide) * lift
        elseif age > toast.duration - slide then
            offset = ((age - (toast.duration - slide)) / slide) * lift
        end

        local dw, dh = display_size()
        local width = 380
        local x = dw - width - (self.cfg.margin or 16)
        local y = dh - 70 - (self.cfg.margin or 16) + offset

        local bg = { 1.00, 0.95, 0.80, 0.96 }
        local border = { 0.90, 0.75, 0.25, 1.00 }
        local text = { 0.33, 0.24, 0.04, 1.00 }
        if toast.kind == "danger" then
            bg = { 0.97, 0.85, 0.86, 0.96 }
            border = { 0.85, 0.30, 0.32, 1.00 }
            text = { 0.45, 0.08, 0.10, 1.00 }
        elseif toast.kind == "success" then
            bg = { 0.82, 0.94, 0.86, 0.96 }
            border = { 0.30, 0.70, 0.45, 1.00 }
            text = { 0.08, 0.32, 0.16, 1.00 }
        end

        imgui.set_next_window_pos({ x, y }, COND.Always)
        imgui.set_next_window_size({ width, 0 }, COND.Always)
        local flags = WIN.NoTitleBar + WIN.NoResize + WIN.NoMove + WIN.NoScrollbar
            + WIN.NoCollapse + WIN.AlwaysAutoResize + WIN.NoSavedSettings
        local color_n = 0
        if push_color(COL.WindowBg, bg) then
            color_n = color_n + 1
        end
        if push_color(COL.Border, border) then
            color_n = color_n + 1
        end
        if push_color(COL.Text, text) then
            color_n = color_n + 1
        end
        -- REF skips ImGui::Begin when the open arg is false, then End() asserts.
        local open = imgui.begin_window("##refshell_toast", nil, flags)
        if open then
            imgui.text(toast.text)
            imgui.end_window()
        end
        if color_n > 0 then
            pcall(imgui.pop_style_color, color_n)
        end
    end

    -- Cursor: via.hid.Mouse ShowCursor + AbsoluteMode. No GUI mask,
    -- requestMask, or setMouseDeltaPos. Look lock is addRotationDegree skip.
    function menu:mouse_type()
        if not self._mouse_td then
            self._mouse_td = sdk.find_type_definition("via.hid.Mouse")
        end
        return self._mouse_td
    end

    function menu:mouse_call(name, ...)
        local td = self:mouse_type()
        if not td then
            return nil, false
        end
        local method = td:get_method(name)
        if not method then
            return nil, false
        end
        local a, b = ...
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
        return nil, false
    end

    function menu:gui_manager()
        return sdk.get_managed_singleton("app.GUIManager")
    end

    -- In-game cursor: isMouseCursorAvailable + _VirtualMouseEnable +
    -- IsHighHudInput. Look: CAMERA / CAMERA_RESET button masks.
    -- Do not requestMask or setEnable(5).
    function menu:wants_game_cursor()
        return self.lock_cursor and self.cfg.open
    end

    function menu:install_cursor_hooks()
        if self._cursor_hooks then
            return
        end
        self._cursor_hooks = true
        local td = sdk.find_type_definition("app.GUIManager")
        if not td then
            return
        end
        local function force_true_when_open(method_name)
            local method = td:get_method(method_name)
            if not method then
                return
            end
            pcall(sdk.hook, method, function()
                if self:wants_game_cursor() then
                    return sdk.PreHookResult.SKIP_ORIGINAL
                end
            end, function(retval)
                if self:wants_game_cursor() then
                    return sdk.to_ptr(1)
                end
                return retval
            end)
        end
        force_true_when_open("isMouseCursorAvailable")
        force_true_when_open("get_IsHighHudInput")
        force_true_when_open("get_VirtualMouseEnable")
    end

    function menu:game_input()
        return sdk.get_managed_singleton("app.GameInputManager")
    end

    function menu:button_mask_user(name)
        local td = sdk.find_type_definition("app.PlayerDef.ButtonMask.USER")
        if not td then
            return nil
        end
        local field = td:get_field(name)
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

    function menu:apply_player_mask(want)
        local gim = self:game_input()
        if not gim then
            return
        end
        if want then
            for _, name in ipairs({ "CAMERA", "CAMERA_RESET" }) do
                local value = self:button_mask_user(name)
                if value ~= nil then
                    pcall(function()
                        gim:call("setPlayerButtonMask", value)
                    end)
                end
            end
        end
    end

    function menu:apply_virtual_mouse(want)
        local gui = self:gui_manager()
        if want then
            if not self._vmouse_owned then
                local prev = false
                if gui then
                    pcall(function()
                        prev = gui:get_field("_VirtualMouseEnable") and true or false
                    end)
                end
                self._prev_vmouse = prev
                self._vmouse_owned = true
            end
            if gui then
                pcall(function()
                    gui:set_field("_VirtualMouseEnable", true)
                end)
            end
        elseif self._vmouse_owned then
            if gui then
                pcall(function()
                    gui:set_field("_VirtualMouseEnable", self._prev_vmouse and true or false)
                end)
            end
            self._vmouse_owned = false
        end
    end

    function menu:apply_cursor(want)
        if not self.lock_cursor then
            return
        end

        self:apply_virtual_mouse(want)
        self:apply_player_mask(want)

        if want then
            if not self._cursor_shown then
                local shown, shown_ok = self:mouse_call("get_ShowCursor")
                local abs, abs_ok = self:mouse_call("get_AbsoluteMode")
                local clip, clip_ok = self:mouse_call("get_ClipCursorToScreen")
                if shown_ok then
                    self._prev_show_cursor = shown and true or false
                end
                if abs_ok then
                    self._prev_absolute = abs and true or false
                end
                if clip_ok then
                    self._prev_clip = clip and true or false
                end
                self._cursor_shown = true
            end
            self:mouse_call("set_ShowCursor", true)
            self:mouse_call("set_AbsoluteMode", true)
            self:mouse_call("set_ClipCursorToScreen", false)
        elseif self._cursor_shown then
            local prev_show = self._prev_show_cursor
            if prev_show == nil then
                prev_show = false
            end
            local prev_abs = self._prev_absolute
            if prev_abs == nil then
                prev_abs = false
            end
            self:mouse_call("set_ShowCursor", prev_show)
            self:mouse_call("set_AbsoluteMode", prev_abs)
            local prev_clip = self._prev_clip
            if prev_clip == nil then
                prev_clip = true
            end
            self:mouse_call("set_ClipCursorToScreen", prev_clip)
            self._cursor_shown = false
        end
    end

    function menu:tick_cursor()
        if self.lock_cursor then
            self:apply_cursor(self.cfg.open)
        end
    end

    -- DMC5: forbidCameraControl. Wilds look lives on cPlayerCameraOperator
    -- (mouseRotation / padRotation), not AutoRotator and not event camera.
    -- Do not hook GUI, requestMask, setMouseDeltaPos, or markEventCamera.
    function menu:wants_camera_lock()
        return self.lock_camera and self.cfg.open
    end

    function menu:try_obj_call(obj, name)
        if not obj then
            return nil
        end
        local ok, result = pcall(function()
            return obj:call(name)
        end)
        if ok and result ~= nil and type(result) == "userdata" then
            return result
        end
        return nil
    end

    function menu:master_info()
        local pm = sdk.get_managed_singleton("app.PlayerManager")
        if not pm then
            return nil
        end
        return self:try_obj_call(pm, "getMasterPlayer")
            or self:try_obj_call(pm, "get_MasterPlayer")
    end

    function menu:camera_controller()
        local cm = sdk.get_managed_singleton("app.CameraManager")
        if cm then
            local ok, cam = pcall(function()
                return cm:get_field("_MasterPlCamera")
            end)
            if ok and cam then
                self._cam = cam
                return cam
            end
        end

        local info = self:master_info()
        local candidates = {
            info,
            self:try_obj_call(info, "get_Character"),
            self:try_obj_call(info, "get_Controller"),
            self:try_obj_call(info, "get_ContextHolder"),
            self:try_obj_call(info, "get_Hunter"),
        }
        for _, obj in ipairs(candidates) do
            local cam = self:try_obj_call(obj, "get_CameraController")
            if cam then
                self._cam = cam
                return cam
            end
        end

        local go = self:try_obj_call(info, "get_Object")
            or self:try_obj_call(info, "get_GameObject")
        local chara = self:try_obj_call(info, "get_Character")
        if not go and chara then
            go = self:try_obj_call(chara, "get_GameObject")
        end
        if go then
            local ok, cam = pcall(function()
                local typ = sdk.typeof("app.PlayerCameraController")
                if not typ then
                    return nil
                end
                return go:call("getComponent(System.Type)", typ)
            end)
            if ok and cam then
                self._cam = cam
                return cam
            end
        end
        return self._cam
    end

    function menu:camera_operator(cam)
        cam = cam or self:camera_controller()
        if not cam then
            return nil
        end
        local ok, op = pcall(function()
            return cam:get_field("_Operator") or cam:call("get_RotationOperator")
        end)
        if ok and op then
            self._cam_op = op
            return op
        end
        return self._cam_op
    end

    function menu:zero_look_input(op)
        if not op or not Vector2f then
            return
        end
        local zero = Vector2f.new(0, 0)
        for _, name in ipairs({
            "_MouseRotateAmount",
            "_PadInput",
            "_GyroInputAmount",
            "_RotAmount",
            "_RotDir",
        }) do
            pcall(function()
                op:set_field(name, zero)
            end)
        end
        pcall(function()
            op:set_field("_IsRotated", false)
        end)
        pcall(function()
            op:set_field("_IsRotatePad", false)
        end)
    end

    function menu:apply_camera_lock(want)
        if not self.lock_camera then
            return
        end
        self._cam_lock_active = want and true or false
        local cam = self:camera_controller()
        local op = self:camera_operator(cam)
        if want then
            self:zero_look_input(op)
            if cam then
                pcall(function()
                    cam:call("breakAutoRotate")
                end)
            end
        end
    end

    function menu:tick_camera()
        if self.lock_camera then
            self:apply_camera_lock(self:wants_camera_lock())
        end
    end

    function menu:install_camera_hooks()
        if self._cam_hooks then
            return
        end
        self._cam_hooks = true

        local function skip_if_locked(args)
            if not self:wants_camera_lock() then
                return
            end
            local obj = sdk.to_managed_object(args[2])
            if obj then
                local tname = ""
                pcall(function()
                    tname = obj:get_type_definition():get_name()
                end)
                if tname == "cPlayerCameraOperator" or tname == "PlayerCameraController" then
                    if tname == "cPlayerCameraOperator" then
                        self._cam_op = obj
                    else
                        self._cam = obj
                    end
                end
            end
            return sdk.PreHookResult.SKIP_ORIGINAL
        end

        local function hook_skip(td, name)
            if not td then
                return
            end
            local method = td:get_method(name)
            if not method then
                return
            end
            pcall(sdk.hook, method, skip_if_locked, function(retval)
                return retval
            end)
        end

        local cam_td = sdk.find_type_definition("app.PlayerCameraController")
        hook_skip(cam_td, "addRotationDegree(via.vec2, System.Boolean)")
        hook_skip(cam_td, "addRotationDegree")
        hook_skip(cam_td, "overwriteRotationDegree")

        local op_td = sdk.find_type_definition("app.cPlayerCameraOperator")
        hook_skip(op_td, "update")
        hook_skip(op_td, "mouseRotation")
        hook_skip(op_td, "padRotation")
        hook_skip(op_td, "gyroRotation")

        local rot_td = sdk.find_type_definition("app.cPlayerCameraAutoRotator")
        hook_skip(rot_td, "update")
    end

    function menu:is_allowed_open()
        if type(self.can_open) ~= "function" then
            return true
        end
        local ok, allowed = pcall(self.can_open, self)
        return ok and allowed == true
    end

    function menu:set_open(want)
        want = want and true or false
        if want and not self:is_allowed_open() then
            if type(self.on_open_blocked) == "function" then
                pcall(self.on_open_blocked, self)
            end
            return false
        end
        if self.cfg.open == want then
            return true
        end
        self.cfg.open = want
        self.dirty = true
        if want then
            self._just_opened = true
        end
        return true
    end

    function menu:enforce_open_gate()
        if self.cfg.open and not self:is_allowed_open() then
            self.cfg.open = false
            self.dirty = true
        end
    end

    function menu:poll_toggle()
        if self.rebinding then
            local dest = self.rebinding
            local key = reframework:get_first_key_down()
            if key ~= nil then
                if key == 0x1B then
                    self.rebinding = false
                elseif key > 0x06 then
                    if dest == true then
                        self.cfg.toggle_vk = key
                    elseif type(dest) == "table" and dest.tbl and dest.key then
                        dest.tbl[dest.key] = key
                    end
                    self.rebinding = false
                    self.dirty = true
                    self.key_was_down = true
                end
            end
            return
        end

        local down = reframework:is_key_down(self.cfg.toggle_vk)
        if down and not self.key_was_down then
            if self.cfg.open then
                self:set_open(false)
            else
                self:set_open(true)
            end
        end
        self.key_was_down = down
    end

    function menu:bind()
        if self.bound then
            return self
        end
        self.bound = true
        self:load()
        self:install_camera_hooks()
        self:install_cursor_hooks()

        if not self:has_tab("Settings") then
            self:add_tab("Settings", function(ui)
                ui.shell_settings()
            end)
        end

        re.on_frame(function()
            self:poll_toggle()
            self:enforce_open_gate()
            self:tick_cursor()
            self:tick_camera()
            if self.cfg.open then
                self:draw_window()
            end
            self:draw_toast()
            if self.dirty then
                self:save()
            end
        end)

        re.on_draw_ui(function()
            if imgui.tree_node(self.title) then
                imgui.text("Toggle: " .. vk_name(self.cfg.toggle_vk))
                local changed, open = imgui.checkbox("Menu open", self.cfg.open)
                if changed then
                    self:set_open(open)
                end
                if imgui.button("Dock right") then
                    self:dock_now("right")
                    self:set_open(true)
                end
                imgui.tree_pop()
            end
        end)

        re.on_config_save(function()
            self:save()
        end)

        re.on_script_reset(function()
            self:apply_cursor(false)
            self:apply_camera_lock(false)
            self:save()
        end)

        return self
    end

    return menu
end

RefShell.themes = THEMES
RefShell.COL = COL
RefShell.vk_name = vk_name

return RefShell
