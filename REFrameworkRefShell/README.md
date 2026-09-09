# RefShell

Reusable ImGui trainer shell for [REFramework](https://github.com/praydog/REFramework).

Window chrome for the menus in this repo: tabs, settings, cursor lock, logs. It is not Live View.

Live View lives in sibling [REFrameworkTools](../../REFrameworkTools). Game QoL bundles this shell.

```
lua/refshell.lua                 require("refshell") / _G.RefShell
lua/refshell/*.lua               config, theme, input, host, log, ui
reframework/plugins/             ref_cursor.dll
examples/minimal.lua
```

## Loose files

```
<game>/reframework/autorun/refshell.lua
<game>/reframework/autorun/refshell/*.lua
<game>/reframework/plugins/ref_cursor.dll
```

```lua
local RefShell = require("refshell")

local menu = RefShell.create({
    id = "MyMod",
    title = "MY MOD",
    toggle_vk = 0xC0,
    persist = features,
    host = true,
    lock_camera = true,
})

menu:add_tab("Cheats", function(ui)
    ui.bind_toggle("God mode", features, "god_mode")
end)

menu:bind()
```

`lock_cursor` defaults on (needs the dll). `host` / `lock_camera` are opt-in RE Engine look-lock.

`RefShell.Log.info("src", "msg")` writes a 400-line ring buffer. **Show Logs** is on the footer.

## Bundle from a host

Rise and Onimusha read `../../REFrameworkRefShell` at `npm run bundle` and inline it. Live View (Tools) reads `../../REFrameworkMods/REFrameworkRefShell`. `REFSHELL_DIR` overrides. Wilds and DMC5 still vendor a copy in `autorun`.

## Rebuild the cursor plugin

C++ lives in the **REFramework** fork (`examples/ref_cursor`). After a Release build:

```
powershell -File tools/sync-refcursor.ps1
```

The script looks for `../../REFramework/build64_all` (sibling of this Mods repo). Pass `-From <dll>` if the build is elsewhere.
