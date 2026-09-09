/**
 * Stream-extract method catalogs from Rise il2cpp_dump.json.
 * Does not load the full 1.4 GB JSON.
 */
import fs from "node:fs";
import readline from "node:readline";

const DUMP =
  process.env.DUMP ||
  "D:\\SteamLibrary\\steamapps\\common\\MonsterHunterRise\\il2cpp_dump.json";

const WANT = new Set(
  (process.env.TYPES || "").split(",").filter(Boolean).length
    ? (process.env.TYPES || "").split(",")
    : [
        "snow.player.PlayerBase",
        "snow.player.PlayerQuestBase",
        "snow.player.PlayerLobbyBase",
        "snow.player.PlayerData",
        "snow.player.PlayerManager",
      ],
);

const KEYWORDS = [
  "sharp",
  "kireaji",
  "vital",
  "stamina",
  "damage",
  "speed",
  "move",
  "attack",
  "muteki",
  "armor",
  "die",
  "hit",
  "nohit",
  "nodamage",
  "enemy",
  "boss",
  "name",
  "pos",
  "position",
  "hp",
  "health",
  "list",
  "anger",
  "angry",
  "target",
];

function interesting(name) {
  const n = name.toLowerCase();
  return KEYWORDS.some((k) => n.includes(k));
}

function stripId(key) {
  return key.replace(/\d+$/, "");
}

async function main() {
  const rl = readline.createInterface({
    input: fs.createReadStream(DUMP, { encoding: "utf8" }),
    crlfDelay: Infinity,
  });

  let type = null;
  let section = null;
  let methodKey = null;
  let method = null;
  let depth = 0;
  let typeDepth = 0;
  let capturing = false;
  const out = {};

  const flushMethod = () => {
    if (!type || !methodKey || !method) return;
    const name = stripId(methodKey);
    if (!interesting(name) && !interesting(methodKey)) return;
    const bucket = out[type];
    bucket.methods.push({
      key: methodKey,
      name,
      flags: method.flags || "",
      function: method.function || "",
      params: method.params || [],
      returns: method.returns || "",
    });
  };

  for await (const line of rl) {
    const typeOpen = line.match(/^    "([^"]+)": \{/);
    if (typeOpen && !capturing) {
      if (WANT.has(typeOpen[1])) {
        capturing = true;
        type = typeOpen[1];
        typeDepth = 2;
        section = null;
        methodKey = null;
        method = null;
        out[type] = { parent: null, methods: [], fields: [] };
      }
      continue;
    }

    if (!capturing) continue;

    const open = (line.match(/\{/g) || []).length;
    const close = (line.match(/\}/g) || []).length;
    depth = (depth || typeDepth) + open - close;

    const parent = line.match(/^\s+"parent": "([^"]+)"/);
    if (parent) out[type].parent = parent[1];

    if (/^\s+"methods": \{/.test(line)) {
      section = "methods";
      continue;
    }
    if (/^\s+"fields": \{/.test(line)) {
      section = "fields";
      continue;
    }
    if (
      section &&
      /^\s+"(properties|reflection_properties|name_hierarchy|RSZ|deserializer_chain)":/.test(
        line,
      )
    ) {
      if (section === "methods") flushMethod();
      section = null;
      methodKey = null;
      method = null;
    }

    if (section === "methods") {
      const mopen = line.match(/^\s{12}"([^"]+)": \{/);
      if (mopen) {
        flushMethod();
        methodKey = mopen[1];
        method = { params: [] };
        continue;
      }
      const flags = line.match(/^\s+"flags": "([^"]+)"/);
      if (flags && method) method.flags = flags[1];
      const fn = line.match(/^\s+"function": "([^"]+)"/);
      if (fn && method) method.function = fn[1];
      const ret = line.match(/^\s+"type": "([^"]+)"/);
      if (ret && method && /returns/.test(section) === false) {
        // handled below via looking at last param/return blocks — keep simple
      }
      if (method && /^\s+"name": "([^"]+)"/.test(line)) {
        const pname = line.match(/"name": "([^"]+)"/)[1];
        method._pendingParam = pname;
      }
      if (method && method._pendingParam && /^\s+"type": "([^"]+)"/.test(line)) {
        const ptype = line.match(/"type": "([^"]+)"/)[1];
        if (method._inReturns) {
          method.returns = ptype;
        } else {
          method.params.push({ name: method._pendingParam, type: ptype });
        }
        method._pendingParam = null;
      }
      if (method && /^\s+"returns": \{/.test(line)) {
        method._inReturns = true;
      }
    }

    if (section === "fields") {
      const fopen = line.match(/^\s{12}"([^"]+)": \{/);
      if (fopen && interesting(fopen[1])) {
        out[type].fields.push(fopen[1]);
      }
    }

    // End of this top-level type (indent 4 close after we started at 2)
    if (/^    \},?$/.test(line) && capturing) {
      flushMethod();
      capturing = false;
      type = null;
      section = null;
      if (Object.keys(out).length >= WANT.size) break;
    }
  }

  const dest = new URL(
    "../dist/" + (process.env.OUT || "type-catalog.json"),
    import.meta.url,
  );
  fs.mkdirSync(new URL(".", dest), { recursive: true });
  fs.writeFileSync(dest, JSON.stringify(out, null, 2));
  for (const [name, info] of Object.entries(out)) {
    console.log(
      `${name} parent=${info.parent || "?"} methods=${info.methods.length} fields=${info.fields.length}`,
    );
  }
  console.log(`Wrote ${dest.pathname}`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
