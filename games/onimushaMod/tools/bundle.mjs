/**
 * Pack sibling RefShell + the Onimusha menu into one autorun script.
 *
 * Usage: npm run bundle
 *        node tools/bundle.mjs <out.lua>
 * Default output: dist/cache/onimusha_qol.lua
 *
 * RefShell is ../../REFrameworkRefShell (or REFSHELL_DIR). Not vendored here.
 * Submodules go on package.preload so require() works in the single file.
 */

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(__dirname, "..");
const OUT = path.resolve(process.argv[2] || path.join(ROOT, "dist", "cache", "onimusha_qol.lua"));
const REFSHELL_ROOT = path.resolve(
  process.env.REFSHELL_DIR || path.join(ROOT, "..", "..", "REFrameworkRefShell"),
);

const REFSHELL_MODULES = [
  ["refshell.util", "lua/refshell/util.lua"],
  ["refshell.config", "lua/refshell/config.lua"],
  ["refshell.input", "lua/refshell/input.lua"],
  ["refshell.theme", "lua/refshell/theme.lua"],
  ["refshell.host", "lua/refshell/host.lua"],
  ["refshell.log", "lua/refshell/log.lua"],
  ["refshell.ui", "lua/refshell/ui.lua"],
  ["refshell", "lua/refshell.lua"],
];

const IIFE_FILES = [
  "reframework/autorun/appearance.lua",
  "reframework/autorun/give.lua",
  "reframework/autorun/main.lua",
];

function readLua(absPath) {
  if (!fs.existsSync(absPath)) {
    throw new Error(`Missing source: ${absPath}`);
  }
  return fs.readFileSync(absPath, "utf8").replace(/^\uFEFF/, "");
}

function wrapPreload(name, label, source) {
  const body = source.replace(/\s*$/, "");
  return `-- ${label}\npackage.preload[${JSON.stringify(name)}] = function(...)\n${body}\nend\n`;
}

function wrapIife(relPath, source) {
  const body = source.replace(/\s*$/, "");
  return `-- ${relPath}\ndo\n(function()\n${body}\nend)()\nend\n`;
}

function main() {
  if (!fs.existsSync(path.join(REFSHELL_ROOT, "lua", "refshell.lua"))) {
    throw new Error(`RefShell not found at ${REFSHELL_ROOT}. Set REFSHELL_DIR.`);
  }

  const parts = [
    ...REFSHELL_MODULES.map(([name, rel]) => {
      const file = path.join(REFSHELL_ROOT, rel);
      return wrapPreload(name, rel, readLua(file));
    }),
    `require("refshell")\n`,
    ...IIFE_FILES.map((relPath) => wrapIife(relPath, readLua(path.join(ROOT, relPath)))),
  ];

  const listed = [...REFSHELL_MODULES.map(([, rel]) => rel), ...IIFE_FILES];
  const bundled = `--[[
  onimusha_qol.lua — generated release bundle. Do not edit.

  Build: npm run bundle
  Install as: reframework/autorun/onimusha_qol.lua

  Self-contained: ${listed.join(", then ")}.
]]
${parts.join("\n")}`;

  if (!bundled.includes("_G.RefShell")) {
    throw new Error("Bundle must assign _G.RefShell");
  }
  if (!bundled.includes('package.preload["refshell.host"]')) {
    throw new Error("Bundle must preload refshell.host");
  }
  if (!bundled.includes("host = true")) {
    throw new Error("Bundle must attach the RE Engine host");
  }
  if (!bundled.includes("ONIMUSHA QOL")) {
    throw new Error("Bundle must include the Onimusha menu");
  }
  if (!bundled.includes("_G.OnimushaAppearance")) {
    throw new Error("Bundle must include the Appearance module");
  }
  if (!bundled.includes("_G.OnimushaGive")) {
    throw new Error("Bundle must include the Give module");
  }
  if (!bundled.includes('package.preload["refshell.log"]')) {
    throw new Error("Bundle must preload refshell.log");
  }
  if (!bundled.includes('package.preload["refshell.ui"]')) {
    throw new Error("Bundle must preload refshell.ui");
  }
  if (!bundled.includes("Show Logs")) {
    throw new Error("Bundle must include the Show Logs button");
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
