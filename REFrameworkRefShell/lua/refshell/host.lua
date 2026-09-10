-- Optional RE Engine host: HID cursor fallback + look lock.
-- Onimusha types plus leftover Wilds names. Attach only when a game needs it:
--   RefShell.create({ host = true, lock_camera = true })

local host = {
    name = "re_engine",
}

function host.attach(menu)
    if menu._host then
        return menu
    end
    menu._host = host.name
    menu._mouse_write_ok = false
    menu._warp_skips = menu._warp_skips or 0
    menu._request_moves = menu._request_moves or 0

    -- Cursor: via.hid.Mouse ShowCursor + AbsoluteMode. No GUI mask,
    -- requestMask, or setMouseDeltaPos. Look lock is addRotationDegree skip.
    -- Onimusha uses EnableLocalMouseCursor / GUI090000 instead of
    -- Wilds isMouseCursorAvailable.
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

    -- Own writes must pass the setter hooks. Game writes are skipped
    -- while the menu is open so ShowCursor / clip cannot snap back.
    function menu:mouse_own(name, value)
        self._mouse_write_ok = true
        local result, ok = self:mouse_call(name, value)
        self._mouse_write_ok = false
        return result, ok
    end

    function menu:gui_manager()
        return sdk.get_managed_singleton("app.GUIManager")
    end

    -- Cursor: via.hid.Mouse ShowCursor + AbsoluteMode.
    -- Wilds: isMouseCursorAvailable + _VirtualMouseEnable + IsHighHudInput.
    -- Onimusha: EnableLocalMouseCursor + GUI090000 isEnableMouseCursor +
    -- IsHighHudInput / IsHighTitleInput. No isMouseCursorAvailable.
    -- Look: CAMERA / CAMERA_RESET button masks when those enums exist.
    -- Do not requestMask or setEnable(5).
    function menu:hook_bool_when_open(type_name, method_name, when_open)
        local td = sdk.find_type_definition(type_name)
        if not td then
            return false
        end
        local method = td:get_method(method_name)
        if not method then
            return false
        end
        local ok = pcall(sdk.hook, method, function()
            if self:wants_game_cursor() then
                return sdk.PreHookResult.SKIP_ORIGINAL
            end
        end, function(retval)
            if self:wants_game_cursor() then
                return sdk.to_ptr(when_open and 1 or 0)
            end
            return retval
        end)
        return ok
    end

    function menu:note_warp_skip()
        self._warp_skips = (self._warp_skips or 0) + 1
    end

    function menu:note_request_move()
        self._request_moves = (self._request_moves or 0) + 1
    end

    -- Count only. requestMove is the pause-menu software cursor, not the
    -- look recenter. Skipping it fights the path we want to copy.
    function menu:hook_count(type_name, method_name, on_call)
        local td = sdk.find_type_definition(type_name)
        if not td then
            return false
        end
        local method = td:get_method(method_name)
        if not method then
            return false
        end
        local ok = pcall(sdk.hook, method, function()
            if on_call then
                on_call(self)
            end
        end)
        return ok
    end

    function menu:hook_mouse_block_when_open(method_name, count_warp)
        local td = self:mouse_type()
        if not td then
            return false
        end
        local method = td:get_method(method_name)
        if not method then
            return false
        end
        local ok = pcall(sdk.hook, method, function()
            if self:wants_game_cursor() and not self._mouse_write_ok then
                if count_warp then
                    self:note_warp_skip()
                end
                return sdk.PreHookResult.SKIP_ORIGINAL
            end
        end)
        return ok
    end

    -- REF patches Win32 SetCursorPos only while its own overlay is open.
    -- Lua never gets that API. These managed setters are the warp path we
    -- can skip; warp_skips stays 0 if recenter is a raw SetCursorPos.
    function menu:hook_skip_when_open(type_name, method_name, count_warp)
        local td = sdk.find_type_definition(type_name)
        if not td then
            return false
        end
        local method = td:get_method(method_name)
        if not method then
            return false
        end
        local ok = pcall(sdk.hook, method, function()
            if self:wants_game_cursor() and not self._mouse_write_ok then
                if count_warp then
                    self:note_warp_skip()
                end
                return sdk.PreHookResult.SKIP_ORIGINAL
            end
        end)
        return ok
    end

    function menu:install_cursor_hooks()
        if not self.lock_cursor or self._cursor_hooks then
            return
        end
        self._cursor_hooks = true
        -- Wilds names stay so a later port can keep working.
        self:hook_bool_when_open("app.GUIManager", "isMouseCursorAvailable", true)
        self:hook_bool_when_open("app.GUIManager", "get_VirtualMouseEnable", true)
        self:hook_bool_when_open("app.GUIManager", "get_IsHighHudInput", true)
        self:hook_bool_when_open("app.GUIManager", "get_IsHighTitleInput", true)
        self:hook_bool_when_open("app.GUIManager", "get_EnableLocalMouseCursor", true)
        self:hook_bool_when_open("app.GUI090000", "isEnableMouseCursor", true)
        self:hook_bool_when_open("app.GUI090000", "isDisableMouseCursor", false)
        self:hook_bool_when_open("app.GUIManager", "isActiveMouse", true)
        self:hook_bool_when_open("app.GUIManager", "isActiveMouseOrKeybord", true)
        -- Block gameplay HID writes. Do not hook the getters — the probe
        -- needs the real ShowCursor / clip values.
        self:hook_mouse_block_when_open("set_ShowCursor")
        self:hook_mouse_block_when_open("set_AbsoluteMode")
        self:hook_mouse_block_when_open("set_ClipCursorToScreen")
        self:hook_mouse_block_when_open("set_ViewCursorPosition", true)
        self:hook_mouse_block_when_open("set_PresentRectCursorPosition", true)
        self:hook_count("app.GUIManager", "requestMoveMouseCursor", function(m)
            m:note_request_move()
        end)
        self:hook_count("app.GUI090000", "requestMove", function(m)
            m:note_request_move()
        end)
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

    function menu:gui_type(gui)
        if not gui then
            return nil
        end
        local ok, td = pcall(function()
            return gui:get_type_definition()
        end)
        if ok then
            return td
        end
        return nil
    end

    function menu:gui_bool(gui, names)
        if not gui then
            return nil
        end
        local td = self:gui_type(gui)
        for _, name in ipairs(names) do
            if td and td:get_method(name) then
                local ok, value = pcall(function()
                    return gui:call(name)
                end)
                if ok and value ~= nil then
                    return value and true or false
                end
            elseif td and td:get_field(name) then
                local ok, value = pcall(function()
                    return gui:get_field(name)
                end)
                if ok and value ~= nil then
                    return value and true or false
                end
            end
        end
        return nil
    end

    function menu:gui_set_bool(gui, names, value)
        if not gui then
            return
        end
        local td = self:gui_type(gui)
        if not td then
            return
        end
        for _, name in ipairs(names) do
            if td:get_method(name) then
                pcall(function()
                    gui:call(name, value)
                end)
            elseif td:get_field(name) then
                pcall(function()
                    gui:set_field(name, value)
                end)
            end
        end
    end

    function menu:gui_call(gui, name, ...)
        if not gui then
            return nil, false
        end
        local td = self:gui_type(gui)
        if not td or not td:get_method(name) then
            return nil, false
        end
        local a, b = ...
        local ok, result = pcall(function()
            if b ~= nil then
                return gui:call(name, a, b)
            end
            if a ~= nil then
                return gui:call(name, a)
            end
            return gui:call(name)
        end)
        if ok then
            return result, true
        end
        return nil, false
    end

    function menu:apply_virtual_mouse(want)
        local gui = self:gui_manager()
        -- Pause-menu input path (Wilds-style): EnableLocalMouseCursor +
        -- setEnableGameMenuInput -> setEnableCtrl. Do not openGameMenu
        -- (draws pause). Do not lockGameMenuOpen until a pause-menu
        -- probe says isLockGameMenuOpen actually flips with the cursor.
        local read_names = {
            "get_EnableLocalMouseCursor",
            "<EnableLocalMouseCursor>k__BackingField",
        }
        local write_names = {
            "set_EnableLocalMouseCursor",
            "<EnableLocalMouseCursor>k__BackingField",
        }
        if want then
            if not self._vmouse_owned then
                local prev = self:gui_bool(gui, read_names)
                self._prev_vmouse = prev and true or false
                self._vmouse_owned = true
            end
            self:gui_set_bool(gui, write_names, true)
            self:gui_call(gui, "setEnableGameMenuInput", true)
        elseif self._vmouse_owned then
            self:gui_set_bool(gui, write_names, self._prev_vmouse and true or false)
            self:gui_call(gui, "setEnableGameMenuInput", false)
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
            self:mouse_own("set_ShowCursor", true)
            self:mouse_own("set_AbsoluteMode", true)
            self:mouse_own("set_ClipCursorToScreen", false)
        elseif self._cursor_shown then
            local prev_show = self._prev_show_cursor
            if prev_show == nil then
                prev_show = false
            end
            local prev_abs = self._prev_absolute
            if prev_abs == nil then
                prev_abs = false
            end
            self:mouse_own("set_ShowCursor", prev_show)
            self:mouse_own("set_AbsoluteMode", prev_abs)
            local prev_clip = self._prev_clip
            if prev_clip == nil then
                prev_clip = true
            end
            self:mouse_own("set_ClipCursorToScreen", prev_clip)
            self._cursor_shown = false
        end
    end

    function menu:tick_cursor()
        if self.lock_cursor then
            self:apply_cursor(self:wants_native_cursor())
        end
    end

    -- DMC5: forbidCameraControl. Wilds look lives on cPlayerCameraOperator
    -- (mouseRotation / padRotation), not AutoRotator and not event camera.
    -- Do not hook GUI, requestMask, setMouseDeltaPos, or markEventCamera.
    function menu:wants_camera_lock()
        return self.lock_camera and self.cfg.open and self:pointer_over_menu()
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
        local names = {
            "snow.player.PlayerManager",
            "app.PlayerManager",
        }
        if sdk.game_namespace then
            pcall(function()
                names[#names + 1] = sdk.game_namespace("player.PlayerManager")
                names[#names + 1] = sdk.game_namespace("PlayerManager")
            end)
        end
        local pm = nil
        for i = 1, #names do
            pcall(function()
                if not pm then
                    pm = sdk.get_managed_singleton(names[i])
                end
            end)
            if pm then
                break
            end
        end
        if not pm then
            return nil
        end
        return self:try_obj_call(pm, "findMasterPlayer")
            or self:try_obj_call(pm, "getControllingPlayer")
            or self:try_obj_call(pm, "getMasterPlayer")
            or self:try_obj_call(pm, "get_MasterPlayer")
            or self:try_obj_call(pm, "get_CurrentPlayer")
            or self:try_obj_call(pm, "get_manualPlayer")
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
            local obj = nil
            pcall(function()
                obj = sdk.to_managed_object(args[2])
            end)
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

        -- Onimusha look. Wilds names above stay for the later port.
        local ig_td = sdk.find_type_definition("app.cInGameCameraOperator")
        hook_skip(ig_td, "addGameCameraRotationDegree")
        hook_skip(ig_td, "setGameCameraRotationDegree")
    end

    function menu:_host_prepare_open(want)
        if want and not self._cursor_shown then
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
    end

    function menu:_host_reset()
        self:apply_cursor(false)
        self:apply_camera_lock(false)
    end

    function menu:_host_bind()
        self:install_camera_hooks()
        self:install_cursor_hooks()
        for _, entry in ipairs({
            "UpdateHID",
            "EndUpdateHID",
            "BeginUpdateHID",
            "BeginRendering",
            "PrepareRendering",
        }) do
            pcall(re.on_application_entry, entry, function()
                self:tick_cursor()
            end)
        end
    end

    return menu
end

return host
