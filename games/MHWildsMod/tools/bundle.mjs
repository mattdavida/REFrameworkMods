/**
 * Pack RefShell + the Wilds menu into one autorun script.
 *
 * Usage: npm run bundle
 *        node tools/bundle.mjs <out.lua>
 * Default output: dist/cache/mhwilds_qol.lua
 *
 * Source stays as autorun files for live-edit. Release wraps each file
 * in an IIFE so refshell.lua's top-level `return` does not skip the menu.
 * Each IIFE sits in a do/end so Lua does not parse the next `(function`
 * as a call on the previous return value (RefShell is a table).
 */

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(__dirname, "..");
const OUT = path.resolve(process.argv[2] || path.join(ROOT, "dist", "cache", "mhwilds_qol.lua"));

const REFSHELL = "reframework/autorun/refshell.lua";
const HEALTHBARS = "reframework/autorun/healthbars.lua";
const MENU = "reframework/autorun/main.lua";

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
  const healthbars = readLua(HEALTHBARS);
  const menu = readLua(MENU);

  const bundled = `--[[
  mhwilds_qol.lua — generated release bundle. Do not edit.

  Build: npm run bundle
  Install as: reframework/autorun/mhwilds_qol.lua

  Self-contained: refshell.lua, healthbars.lua, then main.lua.
]]
${wrapIife(REFSHELL, refshell)}
${wrapIife(HEALTHBARS, healthbars)}
${wrapIife(MENU, menu)}`;

  if (!bundled.includes("_G.RefShell")) {
    throw new Error("Bundle must assign _G.RefShell");
  }
  if (!bundled.includes("_G.MHHealthBars")) {
    throw new Error("Bundle must assign _G.MHHealthBars");
  }
  if (!bundled.includes("MH WILDS QOL")) {
    throw new Error("Bundle must include the Wilds menu");
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
