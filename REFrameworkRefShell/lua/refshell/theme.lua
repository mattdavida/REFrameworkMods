-- Colors, window flags, and style push/pop for REF ImGui.

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

local THEMES = {
    midnight = {
        window   = { 0.08, 0.08, 0.10, 0.94 },
        -- Child windows do not show WindowBg underneath. Alpha 0 punches
        -- through to the game — the workspace is almost all children.
        child    = { 0.08, 0.08, 0.10, 0.94 },
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
    -- DevTools workspace only. Trainer menu stays midnight.
    violet = {
        window   = { 0.07, 0.07, 0.09, 0.97 },
        child    = { 0.07, 0.07, 0.09, 0.97 },
        title    = { 0.10, 0.06, 0.12, 1.00 },
        border   = { 0.46, 0.24, 0.54, 0.90 },
        text     = { 0.94, 0.93, 0.96, 1.00 },
        muted    = { 0.64, 0.60, 0.70, 1.00 },
        frame    = { 0.12, 0.11, 0.15, 1.00 },
        frame_h  = { 0.24, 0.16, 0.28, 1.00 },
        button   = { 0.46, 0.24, 0.56, 1.00 },
        button_h = { 0.58, 0.32, 0.68, 1.00 },
        button_a = { 0.34, 0.16, 0.44, 1.00 },
        header   = { 0.28, 0.14, 0.36, 1.00 },
        header_h = { 0.40, 0.20, 0.50, 1.00 },
        accent   = { 0.80, 0.38, 0.90, 1.00 },
        accent_d = { 0.42, 0.18, 0.52, 1.00 },
        selected = { 0.52, 0.24, 0.62, 1.00 },
        check    = { 0.80, 0.38, 0.90, 1.00 },
        sep      = { 0.42, 0.28, 0.50, 0.70 },
        grab     = { 0.80, 0.38, 0.90, 1.00 },
    },
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

-- Live dual-pane: finder 40% left, DevTools 60% right, full display height.
local function live_split(margin)
    margin = margin or 16
    if margin < 8 then
        margin = 8
    end
    local dw, dh = display_size()
    local gap = 8
    local inner_w = dw - margin * 2 - gap
    if inner_w < 480 then
        gap = 4
        inner_w = math.max(320, dw - 16)
        margin = 8
    end
    local left_w = math.floor(inner_w * 0.40)
    if left_w < 280 then
        left_w = math.min(280, math.max(200, inner_w - 220))
    end
    local right_w = inner_w - left_w
    local h = fitted_height(margin)
    local y = margin
    return {
        left = { x = margin, y = y, w = left_w, h = h },
        right = { x = margin + left_w + gap, y = y, w = right_w, h = h },
    }
end

-- Remaining content width from the current cursor. Prefer ImGui's
-- region avail so a vertical scrollbar is not counted as usable space.
local function content_width()
    local ok, avail = pcall(imgui.get_content_region_avail)
    if ok and avail and type(avail.x) == "number" and avail.x > 0 then
        return math.max(120, avail.x)
    end
    local size = imgui.get_window_size()
    local cursor = imgui.get_cursor_pos()
    local left = 14
    if cursor and cursor.x then
        left = cursor.x
    end
    local scroll = 0
    local ok_s, max_y = pcall(imgui.get_scroll_max_y)
    if ok_s and type(max_y) == "number" and max_y > 1 then
        scroll = 14
    end
    local w = 320
    if size and size.x then
        w = size.x - left * 2 - scroll
    end
    if w < 120 then
        w = 120
    end
    return w
end

local theme = {
    COL = COL,
    WIN = WIN,
    COND = COND,
    SV = SV,
    themes = THEMES,
    as_vec4 = as_vec4,
    as_vec2 = as_vec2,
    push_color = push_color,
    push_theme = push_theme,
    pop_theme = pop_theme,
    display_size = display_size,
    dock_pos = dock_pos,
    fitted_height = fitted_height,
    live_split = live_split,
    content_width = content_width,
}

return theme
