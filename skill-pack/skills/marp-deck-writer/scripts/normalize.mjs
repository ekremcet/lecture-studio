#!/usr/bin/env node

import fs from "node:fs";

// Typography hygiene for Marp decks: em/en dashes, smart quotes, decorative emoji, bold spacing.
//   node normalize.mjs <deck.md>...            rewrite in place
//   node normalize.mjs --check <deck.md>...    report what would change, change nothing
const argv = process.argv.slice(2);
const check = argv.includes("--check");
const files = argv.filter((a) => a !== "--check");
if (!files.length) {
  console.error("Usage: normalize.mjs [--check] <slide.md>...");
  process.exit(1);
}

const decorativeEmoji = /[🔄👥🏗👤🎨🧠💡📊🎦♻🧪🔧🚀📰👎🍅🧑👨📅⏳💼🌊🛒🔴🎓👍📜📒⚙🎬📝🪾💻🏆🎯🌱🔍]/gu;

function normalizeStrongSpacing(line) {
  const parts = line.split("**");
  if (parts.length < 3) return line;

  let result = parts[0];
  for (let index = 1; index < parts.length; index += 1) {
    const isOpeningMarker = index % 2 === 1;
    if (isOpeningMarker && /[A-Za-z0-9]$/u.test(result)) result += " ";
    result += "**";
    if (!isOpeningMarker && /^[A-Za-z0-9]/u.test(parts[index])) result += " ";
    result += parts[index];
  }
  return result;
}

for (const file of files) {
  const before = fs.readFileSync(file, "utf8");
  const after = before
    .replace(/—{2,}/gu, (match) => "─".repeat(match.length))
    .replaceAll("—", " - ")
    .replaceAll("–", "-")
    .replace(/[“”]/gu, '"')
    .replace(/[‘’]/gu, "'")
    .replace(decorativeEmoji, "")
    .replace(/[\uFE0F\u200D]/gu, "")
    .split("\n")
    .map((line) => line
      .replace(/[ \t]+$/u, "")
      .replace(/^(#{1,6})\s{2,}/u, "$1 ")
      .replace(/\*\*\s+([A-Za-z])/gu, "**$1"))
    .map(normalizeStrongSpacing)
    .join("\n");

  if (after === before) {
    if (check) console.log(`${file}: clean`);
    continue;
  }
  if (check) {
    const a = before.split("\n"), b = after.split("\n");
    let changed = 0;
    for (let i = 0; i < Math.max(a.length, b.length); i++) {
      if (a[i] !== b[i]) {
        changed++;
        if (changed <= 40) console.log(`${file}:${i + 1}\n  - ${a[i] ?? ""}\n  + ${b[i] ?? ""}`);
      }
    }
    console.log(`${file}: ${changed} line(s) would change`);
  } else {
    fs.writeFileSync(file, after);
    console.log(`${file}: normalized`);
  }
}
