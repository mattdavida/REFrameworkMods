-- RefShell: reusable ImGui trainer shell for REFramework.
-- Lua module: require("refshell")  or  _G.RefShell
--
--   local cfg = RefShell.Config.create({ id = "MyMod", defaults = { volume = 1 } })
--   cfg:Get("volume")
--   cfg:Set("volume", 0.5)  -- reframework/data/refshell_MyMod.json
--
-- Cursor lock: reframework/plugins/ref_cursor.dll  (refcursor.request)
-- Look lock / HID fallback: create({ host = true, lock_camera = true })
-- Live View is a separate product (REFrameworkLiveView). This repo is the menu shell.
--
-- REFramework has no BeginTabBar binding, so tabs are custom buttons.

local RefShell = _G.RefShell or {}
_G.RefShell = RefShell

local util = require("refshell.util")
local config_mod = require("refshell.config")
local input = require("refshell.input")
local theme = require("refshell.theme")
local log_mod = require("refshell.log")

local COL = theme.COL
local WIN = theme.WIN
local COND = theme.COND
local THEMES = theme.themes
local push_color = theme.push_color
local push_theme = theme.push_theme
local pop_theme = theme.pop_theme
local display_size = theme.display_size
local dock_pos = theme.dock_pos
local fitted_height = theme.fitted_height
local live_split = theme.live_split
local content_width = theme.content_width
local vk_name = input.vk_name
local copy_defaults = util.copy_defaults
local deep_copy = util.deep_copy
local is_json_safe = util.is_json_safe
local create_config = config_mod.create

RefShell.Config = config_mod
RefShell.Log = log_mod

local ui_mod = require("refshell.ui")

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
        lock_camera = opts.lock_camera == true,
        lock_cursor = opts.lock_cursor ~= false,
        can_open = opts.can_open,
        on_open_blocked = opts.on_open_blocked,
        show_logs = opts.show_logs ~= false,
        _logs_open = false,
        _live_layout = false,
        _dock_override = nil,
        _dock_before_live = nil,
    }

    menu.cfg = copy_defaults(opts.config or {}, {
        open = opts.start_open or false,
        auto_open = false,
        auto_open_vk = 0,
        toggle_vk = opts.toggle_vk or 0x75,
        width = opts.width or 520,
        height = opts.height or 720,
        dock = opts.dock or "right",
        margin = opts.margin or 16,
        layout_rev = 0,
    })
    menu._persist = opts.persist

    menu.ui = ui_mod.make(menu)

    if opts.host then
        require("refshell.host").attach(menu)
    end

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
        if (self.cfg.layout_rev or 0) < 4 then
            self.cfg.layout_rev = 4
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
        self.cfg.width = opts.width or 520
        self.pending_size = true
        self.apply_layout = true
        self.dirty = true
    end

    function menu:current_size()
        local margin = self.cfg.margin or 16
        if self._live_layout then
            local split = live_split(margin)
            return split.left.w, split.left.h
        end
        local dw = display_size()
        local w = self.cfg.width or 520
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

    function menu:select_tab(name)
        for i = 1, #self.tabs do
            if self.tabs[i].name == name then
                self.active_tab = i
                return true
            end
        end
        return false
    end

    function menu:restore_tab_before_live()
        if type(self._tab_before_live) == "number" and self.tabs[self._tab_before_live] then
            self.active_tab = self._tab_before_live
        end
        self._tab_before_live = nil
        self._live_shortcut = false
        self._logs_open = false
        self._ws_rect = nil
    end

    function menu:open_live()
        if not self:has_tab("Live") then
            return false
        end
        if self.cfg.open and self:is_live_tab() and self._live_shortcut then
            self:restore_tab_before_live()
            self:set_open(false)
            return true
        end
        if self.cfg.open and self:is_live_tab() then
            self:set_open(false)
            return true
        end
        if not self._live_shortcut then
            self._tab_before_live = self.active_tab
            self._live_shortcut = true
        end
        self:select_tab("Live")
        self._logs_open = true
        self:set_open(true)
        return true
    end

    local function draw_tabs(self)
        local n = #self.tabs
        if n == 0 then
            return
        end

        -- same_line() uses ItemSpacing.x (we push 8). Measure the row
        -- after the cursor is inset so left and right padding match.
        local pad_y = 10
        local gap = 8
        local tab_h = 28

        local origin_pos = imgui.get_cursor_pos()
        local left = (origin_pos and origin_pos.x) or 14
        imgui.set_cursor_pos({ left, ((origin_pos and origin_pos.y) or 0) + pad_y })

        local avail = content_width()
        local inner = avail - gap * (n - 1)
        if inner < n * 40 then
            inner = n * 40
        end
        local base_w = math.floor(inner / n)
        local leftover = inner - base_w * n

        for i, tab in ipairs(self.tabs) do
            if i > 1 then
                imgui.same_line()
            end
            -- Extra pixels go on earlier pills so the last one cannot
            -- spill past the right inset / scrollbar.
            local tab_w = base_w
            if leftover > 0 then
                tab_w = tab_w + 1
                leftover = leftover - 1
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
                if tab.name ~= "Live" then
                    self._live_shortcut = false
                    self._tab_before_live = nil
                end
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

    function menu:is_live_tab()
        local tab = self.tabs[self.active_tab]
        return tab ~= nil and tab.name == "Live"
    end

    -- Live reads left-to-right: menu on the left, workspace on the right.
    -- Do not persist this as the user's dock setting.
    function menu:sync_live_layout()
        if not self._liveview then
            return
        end
        local live = self:is_live_tab()
        if live and not self._live_layout then
            self._live_layout = true
            self._dock_before_live = self.cfg.dock
            self._dock_override = "left"
            self._logs_open = true
            self.apply_layout = true
        elseif (not live) and self._live_layout then
            self._live_layout = false
            self._dock_override = nil
            self._logs_open = false
            self._ws_rect = nil
            self.apply_layout = true
        end
    end

    function menu:draw_window()
        self:refresh_layout()
        self:sync_live_layout()
        local w, h = self:current_size()

        if self._live_layout then
            local split = live_split(self.cfg.margin or 16)
            imgui.set_next_window_pos({ split.left.x, split.left.y }, COND.Always)
            imgui.set_next_window_size({ split.left.w, split.left.h }, COND.Always)
            self.pending_dock = nil
            self.pending_size = false
            self.apply_layout = false
        elseif self.apply_layout or self.pending_dock then
            local side = self.pending_dock or self._dock_override or self.cfg.dock
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

        self._imgui_hover = false
        local color_n, var_n = push_theme(self.theme)
        local still_open = imgui.begin_window(self.title, true, WIN.NoCollapse + WIN.NoSavedSettings)
        if still_open then
            -- Safety net if ImGui or a lagged display size left us off-screen.
            local pos_ok, pos = pcall(imgui.get_window_pos)
            local size_ok, size = pcall(imgui.get_window_size)
            if pos_ok and size_ok and pos and size then
                self._win_rect = {
                    x = pos.x,
                    y = pos.y,
                    w = size.x,
                    h = size.y,
                }
                local dw, dh = display_size()
                local on_screen = pos.x + size.x > 16
                    and pos.y + size.y > 16
                    and pos.x < dw - 16
                    and pos.y < dh - 16
                if not on_screen then
                    self.apply_layout = true
                end
            end
            local ok, err = pcall(draw_tabs, self)

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
            local tab_ok, tab_err = true, nil
            local tab = self.tabs[self.active_tab]
            if tab and tab.draw then
                tab_ok, tab_err = pcall(tab.draw, self.ui, self)
            end
            imgui.end_child_window()

            if not ok or not tab_ok then
                local msg = tostring(tab_err or err)
                self.ui.muted(msg)
            end

            imgui.spacing()
            local avail = content_width()
            local gap = 8
            local btn_w = avail
            if self.show_logs then
                btn_w = (avail - gap) / 2
                local log_label
                if self._liveview then
                    if self._logs_open then
                        log_label = "Hide Workspace"
                    else
                        local unread = log_mod.unread()
                        if unread > 0 then
                            log_label = string.format("Show Workspace (%d)", unread)
                        else
                            log_label = "Show Workspace"
                        end
                    end
                else
                    log_label = self._logs_open and "Hide Logs" or log_mod.footer_label()
                end
                if imgui.button(log_label .. "##refshell_show_logs", { btn_w, 30 }) then
                    self._logs_open = not self._logs_open
                    if self._logs_open then
                        log_mod.mark_seen()
                    end
                end
                imgui.same_line()
            else
                self._logs_open = false
            end
            if imgui.button("Close", { btn_w, 30 }) then
                still_open = false
            end
            self:note_imgui_hover(true)
        end
        imgui.end_window()
        self:note_imgui_hover(false)
        pop_theme(color_n, var_n)

        if not still_open then
            self.cfg.open = false
            self.dirty = true
            self._win_rect = nil
            self._imgui_hover = false
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

    function menu:draw_confirm()
        local confirm = self._confirm
        if not confirm then
            return
        end

        local width = 360
        local rect = self._win_rect
        local x
        local y
        if rect then
            x = rect.x + (rect.w - width) * 0.5
            y = rect.y + 88
        else
            local dw, dh = display_size()
            x = (dw - width) * 0.5
            y = dh * 0.28
        end

        imgui.set_next_window_pos({ x, y }, COND.Always)
        imgui.set_next_window_size({ width, 0 }, COND.Always)
        local flags = WIN.NoResize + WIN.NoCollapse + WIN.AlwaysAutoResize + WIN.NoSavedSettings
        local color_n, var_n = push_theme(self.theme)
        local open = imgui.begin_window(confirm.title, nil, flags)
        if open then
            for _, line in ipairs(confirm.lines or {}) do
                imgui.text(tostring(line))
            end
            imgui.spacing()
            local btn_w = 150
            if imgui.button(confirm.no .. "##refshell_confirm_no", { btn_w, 30 }) then
                self._confirm = nil
                if confirm.on_no then
                    pcall(confirm.on_no)
                end
            else
                imgui.same_line()
                local yes_pushed = 0
                if push_color(COL.Button, self.theme.selected) then
                    yes_pushed = yes_pushed + 1
                end
                if imgui.button(confirm.yes .. "##refshell_confirm_yes", { btn_w, 30 }) then
                    self._confirm = nil
                    if confirm.on_yes then
                        local ok, err = pcall(confirm.on_yes)
                        if not ok then
                            log.info("[RefShell] confirm yes failed: " .. tostring(err))
                        end
                    end
                end
                if yes_pushed > 0 then
                    imgui.pop_style_color(yes_pushed)
                end
            end
            imgui.end_window()
        end
        pop_theme(color_n, var_n)
    end

    function menu:mouse_screen_pos()
        local ok, m = pcall(function()
            return imgui.get_mouse()
        end)
        if ok and m then
            local x = m.x or m[1]
            local y = m.y or m[2]
            if type(x) == "number" and type(y) == "number" then
                return x, y
            end
        end
        return nil, nil
    end

    -- Root+children while our window is current; AnyWindow after end so
    -- combo popups that hang outside the menu rect still count.
    function menu:note_imgui_hover(in_window)
        if not imgui.is_window_hovered then
            return
        end
        local flags = in_window and 3 or 4
        local hovered = false
        pcall(function()
            hovered = imgui.is_window_hovered(flags) and true or false
        end)
        if hovered then
            self._imgui_hover = true
        end
    end

    function menu:pointer_over_menu()
        if not self.cfg.open then
            return false
        end
        if self._imgui_hover then
            return true
        end
        local mx, my = self:mouse_screen_pos()
        if mx == nil then
            return false
        end
        local function inside(r)
            return r and mx >= r.x and my >= r.y and mx <= r.x + r.w and my <= r.y + r.h
        end
        return inside(self._win_rect) or inside(self._ws_rect)
    end

    function menu:has_refcursor()
        return type(refcursor) == "table" and type(refcursor.request) == "function"
    end

    function menu:sync_refcursor(want)
        if not self:has_refcursor() then
            self._refcursor_held = false
            return
        end
        want = want and true or false
        if want and not self._refcursor_held then
            pcall(function()
                refcursor.request(true)
            end)
            self._refcursor_held = true
        elseif (not want) and self._refcursor_held then
            pcall(function()
                refcursor.request(false)
            end)
            self._refcursor_held = false
        end
    end

    -- Plugin locks the engine cursor for the whole open session.
    -- Without it, HID only forces the pointer while over this window.
    function menu:wants_native_cursor()
        if not self.lock_cursor or not self.cfg.open then
            return false
        end
        if self:has_refcursor() then
            return true
        end
        return self:pointer_over_menu()
    end

    function menu:wants_game_cursor()
        return self:wants_native_cursor()
    end

    function menu:is_allowed_open()
        return true
    end

    function menu:set_open(want)
        want = want and true or false
        if self.cfg.open == want then
            return true
        end
        if self._host_prepare_open then
            self:_host_prepare_open(want)
        end
        self.cfg.open = want
        self.dirty = true
        if want then
            self._just_opened = true
        end
        self:sync_refcursor(want)
        return true
    end

    function menu:tick_auto_open()
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
                    self._vk_down = self._vk_down or {}
                    self._vk_down[key] = true
                end
            end
            return
        end

        local shift = reframework:is_key_down(0x10)
            or reframework:is_key_down(0xA0)
            or reframework:is_key_down(0xA1)
        local down = reframework:is_key_down(self.cfg.toggle_vk)
        if down and not self.key_was_down then
            if shift and self:has_tab("Live") then
                self:open_live()
            elseif self._live_shortcut then
                self:restore_tab_before_live()
                self:set_open(true)
            elseif self.cfg.open then
                self:set_open(false)
            else
                self:set_open(true)
            end
        end
        self.key_was_down = down
    end

    function menu:key_edge(vk)
        if type(vk) ~= "number" or vk <= 0x06 then
            return false
        end
        if vk == self.cfg.toggle_vk then
            return false
        end
        self._vk_edge = self._vk_edge or {}
        if self._vk_edge[vk] ~= nil then
            return self._vk_edge[vk]
        end
        self._vk_down = self._vk_down or {}
        local down = reframework:is_key_down(vk)
        local was = self._vk_down[vk] and true or false
        self._vk_down[vk] = down
        local edge = down and not was
        self._vk_edge[vk] = edge
        return edge
    end

    function menu:poll_toggle_table(tbl)
        if not tbl then
            return
        end
        local labels = self._toggle_labels and self._toggle_labels[tbl]
        for k, v in pairs(tbl) do
            if type(v) == "boolean" and k ~= "open" then
                local vk = tbl[k .. "_vk"]
                if self:key_edge(vk) then
                    tbl[k] = not tbl[k]
                    self.dirty = true
                    local name = labels and labels[k] or k
                    self:toast((tbl[k] and "On: " or "Off: ") .. name, "info", 1400)
                end
            end
        end
    end

    function menu:poll_feature_binds()
        self._vk_edge = {}
        if self.rebinding then
            return
        end
        self:poll_toggle_table(self.cfg)
        self:poll_toggle_table(self._persist)
    end

    function menu:bind()
        if self.bound then
            return self
        end
        self.bound = true
        self:load()
        if self._host_bind then
            self:_host_bind()
        end
        if self.lock_cursor and not self:has_refcursor() then
            if self._host then
                log.info(
                "[RefShell] ref_cursor.dll not loaded — copy reframework/plugins/ref_cursor.dll into the game plugins folder. HID fallback is active.")
            else
                log.info(
                "[RefShell] ref_cursor.dll not loaded — copy reframework/plugins/ref_cursor.dll into the game plugins folder.")
            end
        end
        if self.lock_camera and not self._host then
            log.info("[RefShell] lock_camera needs create({ host = true }).")
        end

        if not self:has_tab("Settings") then
            self:add_tab("Settings", function(ui)
                ui.shell_settings()
            end)
        end

        re.on_frame(function()
            log_mod.tick()
            self:poll_toggle()
            self:poll_feature_binds()
            self:tick_auto_open()
            if self.tick_cursor then
                self:tick_cursor()
            end
            if self.tick_camera then
                self:tick_camera()
            end
            if self.cfg.open then
                self:draw_window()
                if self._logs_open then
                    if self._draw_workspace then
                        self._draw_workspace(self)
                    else
                        log_mod.draw(self)
                    end
                else
                    self._ws_rect = nil
                end
            end
            self:draw_toast()
            self:draw_confirm()
            if self.tick_cursor then
                self:tick_cursor()
            end
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
            self:sync_refcursor(false)
            if self._host_reset then
                self:_host_reset()
            end
            self:save()
        end)

        return self
    end

    return menu
end

RefShell.themes = THEMES
RefShell.COL = COL
RefShell.Log = log_mod
RefShell.vk_name = vk_name
RefShell.attach_host = function(menu)
    return require("refshell.host").attach(menu)
end

return RefShell
