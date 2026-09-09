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
```

If REFramework is already installed, you can drop only `reframework/autorun/mhwilds_qol.lua`.

Open the menu with **~** (tilde). Settings persist in `reframework/data/refshell_mhwilds.json`.

## Ship files

| File | Why |
|---|---|
| `dinput8.dll` | REFramework (optional if already installed) |
| `reframework/autorun/mhwilds_qol.lua` | Menu, health bars, cheats (bundled) |

Do not ship `ref_live.dll` or leftover `health_bars.lua` beside the bundle (bars stack).

## Features

**Gameplay** (party-safe unless noted)

- Health bars — overlay on large monsters (name, fill, optional HP / distance). Not a cheat.
- Move Fast — play speed. Solo only.
- Return to Title — same as pause → Return to Title (turns Move Fast off first)
- Add Zenny / Hunter Points. Solo only.

**Hunter** (solo lobby only)

- God Mode, Infinite Stamina, Always Sharp, More Damage

Cheats stay off if another human hunter is in the session.

## Develop

From this folder:

```
npm run bundle
npm run deploy
```

`deploy` writes `mhwilds_qol.lua` into the Wilds install. It does not touch `dinput8.dll`.

Set `GAME_DIR` if the game is not under the usual Steam paths.

This menu still vendors `autorun/refshell.lua` (the older one-file shell). The release script is one bundled file; do not copy `main.lua` / `refshell.lua` / `healthbars.lua` into `autorun` beside it.
