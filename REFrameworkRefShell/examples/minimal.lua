-- Install the module tree + plugin, then this file:
--   reframework/autorun/refshell.lua
--   reframework/autorun/refshell/*.lua
--   reframework/plugins/ref_cursor.dll
-- ~ (VK 0xC0) toggles the window.
-- Look lock: add host = true, lock_camera = true (Onimusha / other RE Engine games).

local RefShell = _G.RefShell
if not RefShell then
    local ok, mod = pcall(require, "refshell")
    if ok then
        RefShell = mod
    end
end

if not RefShell then
    log.error("[example] refshell.lua missing — put it in reframework/autorun/")
    return
end

local menu = RefShell.create({
    id = "refshell_example",
    title = "REF SHELL",
    toggle_vk = 0xC0,
    persist = {},
})

menu:add_tab("Demo", function(ui)
    ui.muted("Replace this tab with your mod.")
    if ui.button("Hello") then
        menu:toast("Hello from RefShell", "success", 1400)
        if RefShell.Log then
            RefShell.Log.info("demo", "Hello from RefShell")
        end
    end
end)

menu:bind()
