# MH Rise QoL

Lua trainer for Monster Hunter Rise (Sunbreak). Extract into the game folder. No extra runtimes.

## Install

Needs [REFramework](https://github.com/praydog/REFramework) (`dinput8.dll` in the game folder). You do **not** need `csharp-api` / REFramework.NET.

Unzip onto the folder that contains `MonsterHunterRise.exe`:

```
MonsterHunterRise/
  dinput8.dll
  reframework/
    autorun/
      mhrise_qol.lua
    plugins/
      ref_cursor.dll
```

If REFramework is already installed, you can drop only `reframework/autorun/mhrise_qol.lua` (and `ref_cursor.dll` if you want mouse lock in the menu).

Open the menu with **~** (tilde). Settings persist in `reframework/data/refshell_mhrise.json`.

## Ship files

| File | Why |
|---|---|
| `dinput8.dll` | REFramework |
| `reframework/autorun/mhrise_qol.lua` | Menu, cheats, health bars, smithy (bundled) |
| `reframework/plugins/ref_cursor.dll` | Menu cursor lock |

Do not ship `plugins/source/*.cs`, REFramework.NET, or `ref_live.dll`.

## Features

**Gameplay** (any session)

- Health bars
- Free Smithy Crafts — materials, category pts, and zenny go to 0 on the selected recipe (and the current list once when you open / change tab). Do not mash Confirm.
- Unlock All Armor — lists forgeable sets on Low / High / Master / Special. Gift / arena leftovers with no cookbook recipe stay hidden. Switch tabs if a rank is empty.
- Max / add Zenny and Kamura points

**Cheats** (solo lobby only)

- God Mode, infinite items / wirebugs / stamina, always sharp, bow range, more damage, move speed
- Give tab — add armor pieces or full sets to the Item Box

## Develop

From this repo:

```
npm run bundle
npm run deploy
```

`deploy` writes `mhrise_qol.lua` into the Rise install and copies `ref_cursor.dll`. It removes leftover `plugins/source/FreeTree.cs` if an old build left one there.

Set `GAME_DIR` if the game is not under the usual Steam paths.

Smithy logic lives in `reframework/autorun/freetree.lua`. The release script is one bundled file; do not copy `main.lua` / `freetree.lua` into `autorun` beside it.
