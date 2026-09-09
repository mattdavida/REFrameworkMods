/**
 * Pack RefShell + the DMC5 menu into one autorun script.
 *
 * Usage: npm run bundle
 *        node tools/bundle.mjs <out.lua>
 * Default output: dist/cache/simpleCheats.lua
 *
 * Source stays as two autorun files for live-edit. Release wraps each file
 * in an IIFE so refshell.lua's top-level `return` does not skip the menu.
 * Each IIFE sits in a do/end so Lua does not parse the next `(function`
 * as a call on the previous return value (RefShell is a table).
 */

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(__dirname, "..");
const OUT = path.resolve(process.argv[2] || path.join(ROOT, "dist", "cache", "simpleCheats.lua"));

const REFSHELL = "reframework/autorun/refshell.lua";
const MENU = "reframework/autorun/dmc5_menu.lua";

function readLua(relPath) {
  const absPath = path.join(ROOT, relPath);
  if (!fs.existsSync(absPath)) {
    throw new Error(`Missing source: ${absPath}`);
  }
  return fs.readFileSync(absPath, "utf8").replace(/^\uFEFF/, "");
}

/** Keep top-level `return` inside the wrapper so the rest of the bundle runs. */
function wrapIife(relPath, source) {
  const body = source.replace(/\s*$/, "");
  return `-- ${relPath}\ndo\n(function()\n${body}\nend)()\nend\n`;
}

function main() {
  const refshell = readLua(REFSHELL);
  const menu = readLua(MENU);

  const bundled = `--[[
  simpleCheats.lua — generated release bundle. Do not edit.

  Build: npm run bundle
  Install as: reframework/autorun/simpleCheats.lua

  Self-contained: refshell.lua then dmc5_menu.lua.
]]
${wrapIife(REFSHELL, refshell)}
${wrapIife(MENU, menu)}`;

  if (!bundled.includes("_G.RefShell")) {
    throw new Error("Bundle must assign _G.RefShell");
  }
  if (!bundled.includes("DMC5 CHEATS")) {
    throw new Error("Bundle must include the DMC5 menu");
  }
  if (/end\)\(\)\s*\(function/.test(bundled)) {
    throw new Error("Adjacent IIFEs would be parsed as a call");
  }

  fs.mkdirSync(path.dirname(OUT), { recursive: true });
  fs.writeFileSync(OUT, bundled, "utf8");

  const kb = (Buffer.byteLength(bundled, "utf8") / 1024).toFixed(1);
  console.log(`Wrote ${path.relative(ROOT, OUT)} (${kb} KiB)`);
}

try {
  main();
} catch (err) {
  console.error(`bundle failed: ${err.message}`);
  process.exit(1);
}
