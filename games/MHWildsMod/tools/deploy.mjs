/**
 * Bundle the Wilds menu and copy it into the game install.
 *
 * Usage: npm run deploy
 *        GAME_DIR="D:\\path\\to\\MonsterHunterWilds" npm run deploy
 *
 * Work in this repo. Deploy writes:
 *   <game>/reframework/autorun/mhwilds_qol.lua
 *   <game>/reframework/plugins/ref_cursor.dll
 *
 * Does not touch dinput8.dll, REF config, or type dumps.
 */

import fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(__dirname, "..");
const DIST = path.join(ROOT, "dist");
const BUNDLE_OUT = path.join(DIST, "cache", "mhwilds_qol.lua");
const SCRIPT_NAME = "mhwilds_qol.lua";
const REFSHELL_ROOT = path.resolve(
  process.env.REFSHELL_DIR || path.join(ROOT, "..", "..", "REFrameworkRefShell"),
);

const GAME_DIR_CANDIDATES = [
  process.env.GAME_DIR,
  process.env.MHWILDS_DIR,
  "D:\\SteamLibrary\\steamapps\\common\\MonsterHunterWilds",
  "C:\\Program Files (x86)\\Steam\\steamapps\\common\\MonsterHunterWilds",
  "C:\\SteamLibrary\\steamapps\\common\\MonsterHunterWilds",
  "E:\\SteamLibrary\\steamapps\\common\\MonsterHunterWilds",
].filter(Boolean);

function run(cmd, args, opts = {}) {
  const result = spawnSync(cmd, args, { stdio: "inherit", ...opts });
  if (result.error) throw result.error;
  if (result.status !== 0) {
    throw new Error(`${cmd} ${args.join(" ")} exited with ${result.status}`);
  }
}

function isGameDir(dir) {
  return fs.existsSync(path.join(dir, "MonsterHunterWilds.exe"));
}

function resolveGameDir() {
  for (const candidate of GAME_DIR_CANDIDATES) {
    if (candidate && isGameDir(candidate)) {
      return path.resolve(candidate);
    }
  }
  throw new Error(
    "Monster Hunter Wilds folder not found. Set GAME_DIR to the folder that contains MonsterHunterWilds.exe.",
  );
}

function main() {
  const gameDir = resolveGameDir();
  const autorun = path.join(gameDir, "reframework", "autorun");
  const dest = path.join(autorun, SCRIPT_NAME);

  run(process.execPath, [path.join(ROOT, "tools", "bundle.mjs"), BUNDLE_OUT], {
    cwd: ROOT,
  });

  if (!fs.existsSync(BUNDLE_OUT)) {
    throw new Error(`Bundle missing after build: ${BUNDLE_OUT}`);
  }

  fs.mkdirSync(autorun, { recursive: true });
  fs.copyFileSync(BUNDLE_OUT, dest);

  function copyPlugin(name) {
    const srcs = [
      path.join(REFSHELL_ROOT, "reframework", "plugins", name),
      path.join(
        "D:\\SteamLibrary\\steamapps\\common\\MonsterHunterRise",
        "reframework",
        "plugins",
        name,
      ),
    ];
    const src = srcs.find((p) => fs.existsSync(p));
    const destPlugin = path.join(gameDir, "reframework", "plugins", name);
    if (!src) {
      console.log(`Skipped ${name} (not found — menu still loads, cursor lock off)`);
      return;
    }
    fs.mkdirSync(path.dirname(destPlugin), { recursive: true });
    try {
      fs.copyFileSync(src, destPlugin);
      console.log(`Copied ${name} -> ${destPlugin}`);
    } catch (err) {
      if (err && (err.code === "EBUSY" || err.code === "EPERM")) {
        console.log(`Skipped ${name} (locked — close the game to update)`);
        return;
      }
      throw err;
    }
  }

  copyPlugin("ref_cursor.dll");

  // Avoid a second menu if leftover live-edit copies are still in autorun.
  for (const leftover of ["main.lua", "refshell.lua", "healthbars.lua"]) {
    const leftoverPath = path.join(autorun, leftover);
    if (fs.existsSync(leftoverPath)) {
      fs.rmSync(leftoverPath);
      console.log(`Removed leftover ${leftover}`);
    }
  }
  const leftoverDir = path.join(autorun, "refshell");
  if (fs.existsSync(leftoverDir)) {
    fs.rmSync(leftoverDir, { recursive: true, force: true });
    console.log("Removed leftover refshell/");
  }

  const kb = (fs.statSync(dest).size / 1024).toFixed(1);
  console.log(`Copied ${SCRIPT_NAME} -> ${dest} (${kb} KiB)`);
}

try {
  main();
} catch (err) {
  console.error(`deploy failed: ${err.message}`);
  process.exit(1);
}
