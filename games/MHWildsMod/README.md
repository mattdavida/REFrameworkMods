# MH Wilds QoL

Lua trainer for Monster Hunter Wilds. Extract into the game folder. No extra runtimes.

## Install

Needs [REFramework](https://github.com/praydog/REFramework) (`dinput8.dll` in the game folder).

Unzip onto the folder that contains `MonsterHunterWilds.exe`:

```
MonsterHunterWilds/
  dinput8.dll
  reframework/
    autorun/
      mhwilds_qol.lua
    plugins/
      ref_cursor.dll
```

If REFramework is already installed, drop `mhwilds_qol.lua` and `ref_cursor.dll`.

Open the menu with **~** (tilde). Settings persist in `reframework/data/refshell_mhwilds.json`.

## Ship files

| File | Why |
|---|---|
| `dinput8.dll` | REFramework (optional if already installed) |
| `reframework/autorun/mhwilds_qol.lua` | Menu, health bars, cheats (bundled) |
| `reframework/plugins/ref_cursor.dll` | Menu cursor lock |

Do not ship `ref_live.dll` or leftover `health_bars.lua` beside the bundle (bars stack).

## Features

**Gameplay** (party-safe unless noted)

- Health bars — overlay on large monsters (name, fill, optional HP / distance, floating hits). Crits tick when the hit lands. Small monsters stay off unless you turn them on. Not a cheat.
- Move Fast — play speed. Solo only.
- Return to Title — same as pause → Return to Title (turns Move Fast off first)
- Add Zenny / Hunter Points. Solo only.

**Smithy** (solo lobby only)

- Free Smithy Crafts — weapon tree, hunter armor, Palico sets, and special upgrade. Materials and zenny stay. Artian and kinsect stay paid.
- Unlock All Armor — every forgeable hunter series. Wilds tabs are Low / High (MAIN / EX), not Rise Master / Special.
- Unlock All Palico Armor — same for Palico sets.
- Unlock All Weapons — reveals hidden names (`?????`) on nodes already on the tree. Does not inject locked story columns.

**Hunter** (solo lobby only)

- God Mode, Infinite Stamina, Infinite Items (pouch use), Free Craft (item recipes), Always Sharp, More Damage

Cheats stay off if another human hunter is in the session.

## Develop

From this folder:

```
npm run bundle
npm run deploy
```

`deploy` writes `mhwilds_qol.lua` and copies `ref_cursor.dll` into the Wilds install. It does not touch `dinput8.dll`.

Set `GAME_DIR` if the game is not under the usual Steam paths.

`bundle` inlines `../../REFrameworkRefShell`. The release script is one file; do not copy `main.lua` / `healthbars.lua` into `autorun` beside it.
