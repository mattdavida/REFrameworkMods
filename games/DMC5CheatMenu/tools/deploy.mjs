/**
 * Build a player-ready DMC5CheatMenu zip (manual install into the game folder).
 *
 * Usage: npm run deploy
 *
 * Outputs:
 *   dist/release/dinput8.dll
 *   dist/release/reframework/autorun/simpleCheats.lua
 *   dist/release/reframework/data/...
 *   dist/DMC5CheatMenu.zip
 *
 * Extract the zip into the Devil May Cry 5 folder (next to the exe).
 * Does not copy anything into a game install.
 */

import fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(__dirname, "..");
const DIST = path.join(ROOT, "dist");
const RELEASE_ROOT = path.join(DIST, "release");
const INSTALL_LUA = path.join(RELEASE_ROOT, "reframework", "autorun", "simpleCheats.lua");
const SRC_DATA = path.join(ROOT, "reframework", "data");
const INSTALL_DATA = path.join(RELEASE_ROOT, "reframework", "data");
const ZIP = path.join(DIST, "DMC5CheatMenu.zip");
const VENDOR_DLL = path.join(ROOT, "vendor", "dinput8.dll");
const CACHE_DLL = path.join(DIST, "cache", "dinput8.dll");

const REF_DMC5_ZIP =
  "https://github.com/praydog/REFramework/releases/download/v1.5.9.1/DMC5.zip";

const GAME_DLL_CANDIDATES = [
  "D:\\SteamLibrary\\steamapps\\common\\Devil May Cry 5\\dinput8.dll",
  "C:\\Program Files (x86)\\Steam\\steamapps\\common\\Devil May Cry 5\\dinput8.dll",
  "C:\\SteamLibrary\\steamapps\\common\\Devil May Cry 5\\dinput8.dll",
  "E:\\SteamLibrary\\steamapps\\common\\Devil May Cry 5\\dinput8.dll",
];

function run(cmd, args, opts = {}) {
  const result = spawnSync(cmd, args, { stdio: "inherit", ...opts });
  if (result.error) throw result.error;
  if (result.status !== 0) {
    throw new Error(`${cmd} ${args.join(" ")} exited with ${result.status}`);
  }
}

function psQuote(value) {
  return `'${String(value).replace(/'/g, "''")}'`;
}

function copyDll(src, dest) {
  fs.mkdirSync(path.dirname(dest), { recursive: true });
  fs.copyFileSync(src, dest);
  return dest;
}

function findExtractedDll(root) {
  const direct = path.join(root, "dinput8.dll");
  if (fs.existsSync(direct)) {
    return direct;
  }
  for (const name of fs.readdirSync(root, { withFileTypes: true })) {
    if (name.isDirectory()) {
      const nested = path.join(root, name.name, "dinput8.dll");
      if (fs.existsSync(nested)) {
        return nested;
      }
    }
  }
  throw new Error(`dinput8.dll not found in ${root}`);
}

async function downloadRefDll(dest) {
  console.log(`Downloading REFramework DMC5.zip for dinput8.dll`);
  const res = await fetch(REF_DMC5_ZIP, { redirect: "follow" });
  if (!res.ok) {
    throw new Error(`download failed: ${res.status} ${res.statusText}`);
  }

  const zipPath = path.join(DIST, "cache", "DMC5-REFramework.zip");
  fs.mkdirSync(path.dirname(zipPath), { recursive: true });
  fs.writeFileSync(zipPath, Buffer.from(await res.arrayBuffer()));

  const extractRoot = fs.mkdtempSync(path.join(DIST, "cache", "ref-"));
  try {
    if (process.platform === "win32") {
      run("powershell", [
        "-NoProfile",
        "-Command",
        `Expand-Archive -LiteralPath ${psQuote(zipPath)} -DestinationPath ${psQuote(extractRoot)} -Force`,
      ]);
    } else {
      run("unzip", ["-o", zipPath, "-d", extractRoot]);
    }
    copyDll(findExtractedDll(extractRoot), dest);
  } finally {
    fs.rmSync(extractRoot, { recursive: true, force: true });
  }
}

async function resolveDinput8() {
  if (fs.existsSync(VENDOR_DLL)) {
    return VENDOR_DLL;
  }

  const envPath = process.env.DINPUT8_DLL;
  if (envPath && fs.existsSync(envPath)) {
    return copyDll(envPath, VENDOR_DLL);
  }

  for (const candidate of GAME_DLL_CANDIDATES) {
    if (fs.existsSync(candidate)) {
      return copyDll(candidate, VENDOR_DLL);
    }
  }

  if (fs.existsSync(CACHE_DLL)) {
    return CACHE_DLL;
  }

  await downloadRefDll(CACHE_DLL);
  return CACHE_DLL;
}

function zipRelease() {
  fs.rmSync(ZIP, { force: true });

  if (process.platform === "win32") {
    const ps = [
      "Compress-Archive",
      "-Path",
      path.join(RELEASE_ROOT, "*"),
      "-DestinationPath",
      ZIP,
      "-Force",
    ];
    run("powershell", ["-NoProfile", "-Command", ps.join(" ")]);
    return;
  }

  run("zip", ["-r", ZIP, "."], { cwd: RELEASE_ROOT });
}

async function main() {
  const dinput8 = await resolveDinput8();

  if (!fs.existsSync(SRC_DATA)) {
    throw new Error(`Missing reframework/data: ${SRC_DATA}`);
  }

  fs.rmSync(RELEASE_ROOT, { recursive: true, force: true });
  fs.rmSync(path.join(DIST, "simpleCheats.lua"), { force: true });
  fs.mkdirSync(path.dirname(INSTALL_LUA), { recursive: true });
  run(process.execPath, [path.join(ROOT, "tools", "bundle.mjs"), INSTALL_LUA], {
    cwd: ROOT,
  });

  if (!fs.existsSync(INSTALL_LUA)) {
    throw new Error(`Bundle missing after build: ${INSTALL_LUA}`);
  }

  fs.cpSync(SRC_DATA, INSTALL_DATA, { recursive: true });
  fs.copyFileSync(dinput8, path.join(RELEASE_ROOT, "dinput8.dll"));

  zipRelease();

  const kb = (fs.statSync(ZIP).size / 1024).toFixed(1);
  console.log(`Wrote ${path.relative(ROOT, INSTALL_DATA)}`);
  console.log(`Wrote ${path.relative(ROOT, ZIP)} (${kb} KiB)`);
}

try {
  await main();
} catch (err) {
  console.error(`deploy failed: ${err.message}`);
  process.exit(1);
}
