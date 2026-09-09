-- In-menu ring buffer. Collection is always on; the Show Logs button
-- draws this. os.clock() is 0 in REF Lua — stamp with a frame counter.

local theme = require("refshell.theme")

local COL = theme.COL
local WIN = theme.WIN
local COND = theme.COND
local push_color = theme.push_color
local push_theme = theme.push_theme
local pop_theme = theme.pop_theme
local display_size = theme.display_size
local content_width = theme.content_width

local Log = {}

local MAX = 2000
local entries = {}
local frame = 0
local seq = 0
local seen = 0

local ui_state = {
    filter = "",
    autoscroll = true,
    kind = 1,
}

local KIND_LABELS = { "All", "Info", "Warn", "Error", "Found", "Skip" }
local KIND_KEYS = { "all", "info", "warn", "error", "found", "skip" }

local KIND_COLOR = {
    info = 0xFFE8E8EE,
    warn = 0xFF66C8E6,
    error = 0xFF5A5AE6,
    found = 0xFF6EE66E,
    skip = 0xFFA0A3AD,
    done = 0xFFE0D133,
}

local function trim(s)
    if s == nil then
        return ""
    end
    return tostring(s):match("^%s*(.-)%s*$") or ""
end

function Log.tick()
    frame = frame + 1
end

function Log.frame()
    return frame
end

function Log.count()
    return #entries
end

function Log.unread()
    local n = seq - seen
    if n < 0 then
        return 0
    end
    return n
end

function Log.mark_seen()
    seen = seq
end

function Log.entries()
    return entries
end

function Log.clear()
    entries = {}
    seq = 0
    seen = 0
end

function Log.add(kind, source, text)
    kind = kind or "info"
    if KIND_COLOR[kind] == nil then
        kind = "info"
    end
    seq = seq + 1
    local line = {
        seq = seq,
        frame = frame,
        kind = kind,
        source = trim(source),
        text = trim(text),
    }
    entries[#entries + 1] = line
    if #entries > MAX then
        table.remove(entries, 1)
    end
    pcall(function()
        local prefix = "[DevTools]"
        if line.source ~= "" then
            prefix = prefix .. "[" .. line.source .. "]"
        end
        log.info(prefix .. " " .. line.text)
    end)
    return line
end

function Log.info(source, text)
    return Log.add("info", source, text)
end

function Log.warn(source, text)
    return Log.add("warn", source, text)
end

function Log.error(source, text)
    return Log.add("error", source, text)
end

function Log.found(source, text)
    return Log.add("found", source, text)
end

function Log.skipped(source, text)
    return Log.add("skip", source, text)
end

function Log.done(source, count)
    local n = tonumber(count) or 0
    if n == 1 then
        return Log.add("done", source, "Done — 1 result.")
    end
    return Log.add("done", source, string.format("Done — %d result(s).", n))
end

--- Same console shape as the UE4SS DevTools kit.
function Log.skipped_reason(source, reason)
    return Log.skipped(source, "Skipped: " .. tostring(reason))
end

function Log.found_path(source, full_name)
    return Log.found(source, "Found: " .. tostring(full_name))
end

function Log.not_found(source, what)
    return Log.add("skip", source, "Not found: " .. tostring(what))
end

local function matches(entry, needle, kind_key)
    if kind_key ~= "all" and entry.kind ~= kind_key then
        if not (kind_key == "info" and entry.kind == "done") then
            return false
        end
    end
    if needle == "" then
        return true
    end
    local hay = (entry.source .. " " .. entry.text):lower()
    return hay:find(needle, 1, true) ~= nil
end

local function format_line(entry)
    local src = entry.source
    if src ~= "" then
        return string.format("[%d] [%s] %s", entry.frame, src, entry.text)
    end
    return string.format("[%d] %s", entry.frame, entry.text)
end

local function place_window(menu, width, height)
    local dw, dh = display_size()
    local margin = (menu.cfg and menu.cfg.margin) or 16
    local rect = menu._win_rect
    local x = margin
    local y = margin
    if rect then
        local dock = menu.cfg and menu.cfg.dock or "right"
        if dock == "right" then
            x = rect.x - width - 8
            y = rect.y
            if x < margin then
                x = rect.x
                y = rect.y + rect.h + 8
            end
        elseif dock == "left" then
            x = rect.x + rect.w + 8
            y = rect.y
            if x + width > dw - margin then
                x = rect.x
                y = rect.y + rect.h + 8
            end
        else
            x = rect.x
            y = rect.y + rect.h + 8
        end
    end
    if y + height > dh - 8 then
        y = math.max(8, dh - height - 8)
    end
    if x < 8 then
        x = 8
    end
    return x, y
end

function Log.place(menu, width, height)
    return place_window(menu, width, height)
end

function Log.draw_contents(menu, opts)
    local kind = ui_state.kind
    if kind < 1 or kind > #KIND_LABELS then
        kind = 1
    end
    local next_kind = kind
    if menu and menu.ui and menu.ui.choice_grid then
        next_kind = menu.ui.choice_grid(KIND_LABELS, kind, 3)
    end
    if next_kind ~= kind then
        ui_state.kind = next_kind
    end

    local avail = content_width()
    local clear_w = 72
    local filter_w = avail - clear_w - 8
    if filter_w < 80 then
        filter_w = 80
    end
    local typed, text
    if menu and menu.ui and menu.ui.input_text then
        typed, text = menu.ui.input_text("devtools_log_filter", ui_state.filter, {
            label = "Filter logs",
            placeholder = "text in a line…",
            width = filter_w,
        })
    else
        imgui.push_item_width(filter_w)
        typed, text = imgui.input_text("##devtools_log_filter", ui_state.filter)
        imgui.pop_item_width()
    end
    if typed and type(text) == "string" then
        ui_state.filter = text
    end
    imgui.same_line()
    if imgui.button("Clear##devtools_log", { clear_w, 0 }) then
        Log.clear()
    end

    local changed_scroll, scroll_on = imgui.checkbox("Autoscroll", ui_state.autoscroll)
    if changed_scroll then
        ui_state.autoscroll = scroll_on and true or false
    end
    imgui.same_line()
    imgui.text_colored(string.format("%d / %d", #entries, MAX), 0xFFA0A3AD)

    local needle = trim(ui_state.filter):lower()
    local kind_key = KIND_KEYS[ui_state.kind] or "all"
    local shown = 0

    opts = opts or {}
    local list_h = opts.list_h
    if type(list_h) ~= "number" then
        local win = imgui.get_window_size()
        local cursor = imgui.get_cursor_pos()
        list_h = 260
        if win and cursor and win.y and cursor.y then
            list_h = win.y - cursor.y - 18
        end
    end
    if list_h < 80 then
        list_h = 80
    end

    imgui.begin_child_window("##devtools_log_list", { 0, list_h }, true)
    if #entries == 0 then
        imgui.text_colored("No log lines yet. Dev tab scans and gameplay traces land here.", 0xFFA0A3AD)
    else
        for i = 1, #entries do
            local entry = entries[i]
            if matches(entry, needle, kind_key) then
                shown = shown + 1
                imgui.text_colored(format_line(entry), KIND_COLOR[entry.kind] or KIND_COLOR.info)
            end
        end
        if shown == 0 then
            imgui.text_colored("No lines match this filter.", 0xFFA0A3AD)
        elseif ui_state.autoscroll then
            pcall(function()
                if imgui.set_scroll_here_y then
                    imgui.set_scroll_here_y(1.0)
                elseif imgui.set_scroll_y and imgui.get_scroll_max_y then
                    imgui.set_scroll_y(imgui.get_scroll_max_y())
                end
            end)
        end
    end
    imgui.end_child_window()
end

function Log.draw(menu)
    if not menu or not menu._logs_open then
        return
    end

    Log.mark_seen()

    local width = 960
    local height = 420
    local rect = menu._win_rect
    if rect and rect.h and rect.h > 240 then
        height = math.min(rect.h, 560)
    end
    local x, y = place_window(menu, width, height)
    imgui.set_next_window_pos({ x, y }, COND.Always)
    imgui.set_next_window_size({ width, height }, COND.Always)

    local color_n, var_n = push_theme(menu.theme)
    local open = imgui.begin_window("DevTools Logs", true, WIN.NoCollapse + WIN.NoSavedSettings)
    if open then
        Log.draw_contents(menu)
        menu:note_imgui_hover(true)
    end
    imgui.end_window()
    menu:note_imgui_hover(false)
    pop_theme(color_n, var_n)

    if not open then
        menu._logs_open = false
    end
end

function Log.footer_label()
    local n = Log.unread()
    if n > 0 then
        return string.format("Show Logs (%d)", n)
    end
    return "Show Logs"
end

return Log
