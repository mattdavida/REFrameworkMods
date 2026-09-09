-- Trainer widget kit: section, toggle, filter_dropdown, shell_settings.
-- RefShell.create calls Ui.make(menu). Do not draw the menu window here.

local input = require("refshell.input")
local theme_mod = require("refshell.theme")

local COL = theme_mod.COL
local COND = theme_mod.COND
local push_color = theme_mod.push_color
local content_width = theme_mod.content_width
local vk_name = input.vk_name

local Ui = {}

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
        local header_id = default_open and "##sec" or "##sec_closed"
        if imgui.collapsing_header(title .. header_id) then
            imgui.indent(6)
            draw_fn()
            imgui.unindent(6)
            imgui.spacing()
        end
    end

    function ui.label(text)
        imgui.text(text)
    end

    -- Label above, hint inside the box when empty. REFramework has no InputTextWithHint.
    function ui.input_text(id, value, opts)
        opts = opts or {}
        local label = opts.label
        local placeholder = opts.placeholder or ""
        local width = opts.width
        if width == nil then
            width = -1
        end
        if type(label) == "string" and label ~= "" then
            imgui.text(label)
        end
        value = tostring(value or "")
        if width ~= false then
            imgui.push_item_width(width)
        end
        local screen = imgui.get_cursor_screen_pos()
        local changed, text = imgui.input_text("##" .. id, value)
        if width ~= false then
            imgui.pop_item_width()
        end
        local current = value
        if changed and type(text) == "string" then
            current = text
        end
        local focused = imgui.is_item_active and imgui.is_item_active()
        if current == "" and placeholder ~= "" and not focused then
            local dl = imgui.get_window_draw_list()
            if dl and dl.add_text and screen then
                local x = (screen.x or screen[1] or 0) + 6
                local y = (screen.y or screen[2] or 0) + 3
                dl:add_text({ x, y }, 0xFF7A7D86, placeholder)
            end
        end
        return changed, text
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
        if type(tbl[key .. "_vk"]) ~= "number" then
            tbl[key .. "_vk"] = 0
        end
        menu._toggle_labels = menu._toggle_labels or {}
        menu._toggle_labels[tbl] = menu._toggle_labels[tbl] or {}
        menu._toggle_labels[tbl][key] = label

        local changed, value = imgui.checkbox(label, tbl[key] and true or false)
        if changed then
            tbl[key] = value
            menu.dirty = true
        end
        return changed, value
    end

    function ui.bind_hotkey(label, tbl, key)
        if type(key) == "string" and key:sub(-3) == "_vk" then
            local bool_key = key:sub(1, -4)
            menu._toggle_labels = menu._toggle_labels or {}
            menu._toggle_labels[tbl] = menu._toggle_labels[tbl] or {}
            if not menu._toggle_labels[tbl][bool_key] then
                menu._toggle_labels[tbl][bool_key] = label
            end
        end
        local vk = tbl[key]
        local name = (type(vk) == "number" and vk > 0) and vk_name(vk) or "None"
        local dest = menu.rebinding
        local waiting = dest and dest.tbl == tbl and dest.key == key
        imgui.text(label .. ":  " .. name)
        if waiting then
            ui.muted("Press a key...  (Esc to cancel)")
            return
        end
        local has = type(vk) == "number" and vk > 0
        local avail = content_width()
        local btn_w = has and ((avail - 8) / 2) or -1
        if imgui.button("Rebind##" .. tostring(label) .. tostring(key), { btn_w, 28 }) then
            menu.rebinding = { tbl = tbl, key = key }
        end
        if has then
            imgui.same_line()
            if imgui.button("Clear##" .. tostring(label) .. tostring(key), { btn_w, 28 }) then
                tbl[key] = 0
                menu.dirty = true
            end
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

    -- Floating confirm. Drawn outside the tab child so it cannot
    -- trip ImGui EndChild. opts: title, lines, yes, no, on_yes, on_no.
    function ui.confirm(opts)
        opts = opts or {}
        local lines = opts.lines
        if type(lines) ~= "table" then
            lines = { tostring(opts.body or "") }
        end
        menu._confirm = {
            title = opts.title or "Confirm",
            lines = lines,
            yes = opts.yes or "Confirm",
            no = opts.no or "Cancel",
            on_yes = opts.on_yes,
            on_no = opts.on_no,
        }
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

    -- Green Pick... button that expands an inline filter list.
    -- items: labels, or {value, label}. selected is 1-based, 0 means none.
    -- state: { open = bool, filter = string } owned by the caller.
    function ui.filter_dropdown(id, button_label, items, selected, state, opts)
        opts = opts or {}
        state = state or {}
        if state.open == nil then
            state.open = false
        end
        if type(state.filter) ~= "string" then
            state.filter = ""
        end

        local function clean_label(text)
            if type(text) ~= "string" then
                return ""
            end
            local out = text
                :gsub("</?%s*[Cc][Oo][Ll][Oo][Rr][^>]*>", "")
                :gsub("</?%s*[%w_]+[^>]*>", "")
                :gsub("%s+", " ")
                :gsub("^%s+", "")
                :gsub("%s+$", "")
            if out:find("#Rejected#", 1, true) or out:find("ItemData", 1, true) then
                return ""
            end
            return (out:gsub("##", "  "))
        end

        local labels = {}
        for i, item in ipairs(items or {}) do
            if type(item) == "table" then
                labels[i] = clean_label(item[2] or item.label or tostring(item[1] or item.value or i))
            else
                labels[i] = clean_label(item)
            end
        end

        local caption = clean_label(button_label)
        if caption == "" then
            if selected and labels[selected] and labels[selected] ~= "" then
                caption = labels[selected]
            else
                caption = opts.placeholder or "Pick..."
            end
        end
        imgui.begin_group()

        local pick_pushed = 0
        if push_color(COL.Button, theme.selected) then
            pick_pushed = pick_pushed + 1
        end
        if push_color(COL.ButtonHovered, theme.button_a) then
            pick_pushed = pick_pushed + 1
        end
        local arrow_w = 28
        local btn_w = content_width() - arrow_w - 8
        if btn_w < 80 then
            btn_w = 80
        end
        local opened = false
        if imgui.button(caption .. "##" .. id .. "_pick", { btn_w, 30 }) then
            opened = true
        end
        imgui.same_line()
        -- ImGuiDir 3 = down. Stay down so this matches native combos.
        if imgui.arrow_button("##" .. id .. "_arrow", 3) then
            opened = true
        end
        if opened then
            state.open = not state.open
            state._ignore_click = true
        end
        if pick_pushed > 0 then
            imgui.pop_style_color(pick_pushed)
        end

        local changed = false
        local result = selected or 0

        if state.open then
            local needle = state.filter:lower()
            local filtered = {}
            for i, label in ipairs(labels) do
                if label ~= "" and (needle == "" or label:lower():find(needle, 1, true)) then
                    table.insert(filtered, { i = i, label = label })
                end
            end

            imgui.spacing()
            imgui.text(string.format("%s (%d)", opts.header or "Items", #filtered))

            local avail = content_width()
            local clear_w = 64
            local filter_w = avail - clear_w - 8
            if filter_w < 80 then
                filter_w = 80
            end
            local frame_pushed = 0
            if push_color(COL.Border, theme.selected) then
                frame_pushed = frame_pushed + 1
            end
            local typed, text = ui.input_text(id .. "_filter", state.filter, {
                label = "Filter",
                placeholder = opts.filter_placeholder or "Type to filter…",
                width = filter_w,
            })
            if frame_pushed > 0 then
                imgui.pop_style_color(frame_pushed)
            end
            if typed and type(text) == "string" then
                state.filter = text
            end
            imgui.same_line()
            if imgui.button("Clear##" .. id, { clear_w, 0 }) then
                state.filter = ""
            end

            local list_h = opts.height or 240
            imgui.begin_child_window("##" .. id .. "_list", { 0, list_h }, true)
            if #filtered == 0 then
                ui.muted("No matches.")
            else
                for _, row in ipairs(filtered) do
                    local is_sel = row.i == result
                    local sel_pushed = 0
                    if is_sel then
                        if push_color(COL.Button, theme.selected) then
                            sel_pushed = sel_pushed + 1
                        end
                        if push_color(COL.ButtonHovered, theme.selected) then
                            sel_pushed = sel_pushed + 1
                        end
                    end
                    imgui.push_id(id .. "_row_" .. tostring(row.i))
                    if imgui.button(row.label, { -1, 26 }) then
                        result = row.i
                        changed = true
                        state.open = false
                        menu.dirty = true
                    end
                    imgui.pop_id()
                    if sel_pushed > 0 then
                        imgui.pop_style_color(sel_pushed)
                    end
                    imgui.separator()
                end
            end
            imgui.end_child_window()
        end

        imgui.end_group()

        if state._ignore_click then
            state._ignore_click = false
        elseif state.open and imgui.is_mouse_clicked and imgui.is_mouse_clicked(0) and imgui.is_item_hovered and not imgui.is_item_hovered() then
            state.open = false
        end

        return result, changed
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
            ui.muted("Shift + this key opens Live View. The key alone leaves Live and returns to the tab you were on. Cheat binds are below.")
            if type(menu.extra_keybinds) == "function" then
                menu.extra_keybinds(ui)
            end
        end, true)
    end

    return ui
end

function Ui.make(menu)
    return make_ui(menu)
end

return Ui
