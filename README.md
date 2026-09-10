# REFramework Mods

Shippable QoL menus for RE Engine games. One zip per game. Shared window chrome is **RefShell**.

This is not Live View. Dev tools live in sibling [REFrameworkTools](../REFrameworkTools). The REFramework C++ fork stays in its own repo.

```
REFrameworkRefShell/          window chrome (tabs, settings, cursor lock)
games/MHRiseMod/              MH Rise (Sunbreak)
games/MHWildsMod/             MH Wilds
games/onimushaMod/            Onimusha: Way of the Sword
games/DMC5CheatMenu/          Devil May Cry 5
```

## Build / deploy

From a game folder:

```
cd games/MHRiseMod
npm run bundle
npm run deploy
```

Rise, Wilds, and Onimusha inline `../../REFrameworkRefShell` at bundle time (`REFSHELL_DIR` overrides). DMC5 still vendors a copy of `refshell.lua` in `autorun`.

`deploy` writes the bundled lua (and `ref_cursor.dll` for Rise / Onimusha / Wilds) into the Steam install. It does not touch `dinput8.dll`.

## Ship (Nexus)

Each game is still its own extract. Typical layout:

```
<Game>/
  dinput8.dll                 REFramework (if the zip includes it)
  reframework/autorun/*.lua
  reframework/plugins/ref_cursor.dll   Rise / Onimusha / Wilds
```

See each game's `nexus.txt` and `README.md`.

## Open a menu

Default toggle is **~** (tilde). Settings persist under `reframework/data/refshell_<game>.json`.

## Later

- Point DMC5 at the shared RefShell folder (same as Rise / Wilds).
- Rename game folders to `rise`, `wilds`, `onimusha`, `dmc5` if you want them shorter.
- Do not edit the old standalone repos (`MHRiseMod`, …) once this tree is the source of truth.
