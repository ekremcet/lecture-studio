#!/usr/bin/env node
// Density check for a Marp deck. No dependencies.
//   node density.mjs <deck.md> [--summary]
// Splits slides on lines that are exactly "---" after the front matter, counts prose words,
// bullets, code lines, tables, h3 headings, and computes the house budget:
//   budget = words/15 + bullets + codeLines/2 + 3*tables + 2*h3   (limit 22, p90 of real slides is 20)
import fs from "node:fs";

// Calibrated on 4,262 non-scoped slides from the existing decks (2026-09-03): each limit is
// about the 90th percentile of what the reference decks ship. Because the rules are independent, about one
// existing slide in three trips at least one of them; a new slide should trip none.
const LIMITS = {
  words: 120, wordsWithCode: 90, wordsWithBigImage: 95,
  bullets: 9, bulletsPerColumn: 7, bulletWords: 20,
  codeLinesSingle: 25, codeLinesEach: 18, codeBlocks: 2,
  h3: 3, tableRows: 6, budget: 22,
};

const args = process.argv.slice(2);
const summaryOnly = args.includes("--summary");
const file = args.find((a) => !a.startsWith("--"));
if (!file) { console.error("Usage: node density.mjs <deck.md> [--summary]"); process.exit(1); }

const src = fs.readFileSync(file, "utf8").replace(/\r\n/g, "\n");
let lines = src.split("\n");
// strip front matter
if (lines[0] === "---") {
  const end = lines.indexOf("---", 1);
  if (end > 0) lines = lines.slice(end + 1);
}
const slides = [];
let cur = [];
for (const l of lines) {
  if (l === "---") { slides.push(cur); cur = []; } else cur.push(l);
}
slides.push(cur);

function analyse(body, page) {
  let inCode = false, codeLines = 0, codeBlocks = 0, words = 0, bullets = 0, h3 = 0, tables = 0, tableRows = 0;
  let longBullets = 0, inTable = false, hasScoped = false, inScoped = false, inHtmlComment = false;
  let title = "";
  const columnBullets = [];
  let colIdx = -1;
  const hasBgImage = /!\[bg[^\]]*\]/.test(body.join("\n"));
  const bigImage = /!\[bg (?!right:[123]\d%|left:[123]\d%)[^\]]*\]/.test(body.join("\n")) && hasBgImage;
  for (const raw of body) {
    const l = raw.trim();
    if (l.startsWith("```")) { if (inCode) inCode = false; else { inCode = true; codeBlocks++; } continue; }
    if (inCode) { codeLines++; continue; }
    if (l.includes("<style scoped>")) { hasScoped = true; inScoped = true; }
    if (inScoped) { if (l.includes("</style>")) inScoped = false; continue; }
    if (l.startsWith("<!--")) { if (!l.includes("-->")) inHtmlComment = true; continue; }
    if (inHtmlComment) { if (l.includes("-->")) inHtmlComment = false; continue; }
    if (/^<div class="column/.test(l)) { colIdx++; columnBullets[colIdx] = 0; continue; }
    if (/^<\/?div/.test(l) || /^<\/?style/.test(l)) continue;
    if (/^!\[/.test(l)) continue;
    if (/^# /.test(l)) { if (!title) title = l.slice(2).trim(); words += l.slice(2).split(/\s+/).filter(Boolean).length; continue; }
    if (/^### /.test(l)) h3++;
    if (/^\|/.test(l)) {
      if (!inTable) { tables++; inTable = true; tableRows = 0; }
      if (!/^\|\s*:?-+/.test(l)) tableRows++;
      words += l.replace(/[|*_`]/g, " ").split(/\s+/).filter(Boolean).length;
      continue;
    } else inTable = false;
    if (/^([-*]|\d+\.)\s+/.test(l)) {
      bullets++;
      if (colIdx >= 0) columnBullets[colIdx]++;
      const w = l.replace(/^([-*]|\d+\.)\s+/, "").replace(/[*_`>]/g, "").split(/\s+/).filter(Boolean).length;
      if (w > LIMITS.bulletWords) longBullets++;
      words += w;
      continue;
    }
    if (l) words += l.replace(/^#+\s*/, "").replace(/[*_`>]/g, " ").split(/\s+/).filter(Boolean).length;
  }
  const budget = Math.round((words / 15 + bullets + codeLines / 2 + 3 * tables + 2 * h3) * 10) / 10;
  const over = [];
  const wordLimit = codeBlocks ? LIMITS.wordsWithCode : bigImage ? LIMITS.wordsWithBigImage : LIMITS.words;
  if (words > wordLimit) over.push(`words ${words} > ${wordLimit}`);
  if (bullets > LIMITS.bullets) over.push(`bullets ${bullets} > ${LIMITS.bullets}`);
  const maxCol = Math.max(0, ...columnBullets);
  if (maxCol > LIMITS.bulletsPerColumn) over.push(`bullets in one column ${maxCol} > ${LIMITS.bulletsPerColumn}`);
  if (longBullets) over.push(`${longBullets} bullet(s) longer than ${LIMITS.bulletWords} words`);
  if (codeBlocks > LIMITS.codeBlocks) over.push(`code blocks ${codeBlocks} > ${LIMITS.codeBlocks}`);
  if (codeBlocks === 1 && codeLines > LIMITS.codeLinesSingle) over.push(`code lines ${codeLines} > ${LIMITS.codeLinesSingle}`);
  if (codeBlocks === 2 && codeLines > 2 * LIMITS.codeLinesEach) over.push(`code lines ${codeLines} > ${2 * LIMITS.codeLinesEach} for two blocks`);
  if (h3 > LIMITS.h3) over.push(`h3 ${h3} > ${LIMITS.h3}`);
  if (tableRows > LIMITS.tableRows) over.push(`table rows ${tableRows} > ${LIMITS.tableRows}`);
  if (budget > LIMITS.budget) over.push(`budget ${budget} > ${LIMITS.budget}`);
  return { page, title, words, bullets, codeLines, codeBlocks, tables, h3, hasBgImage, hasScoped, budget, over };
}

const report = slides.map((s, i) => analyse(s, i + 1)).filter((r) => r.words + r.codeLines + r.tables > 0 || r.hasBgImage);
const overPages = report.filter((r) => r.over.length).map((r) => r.page);
const scopedPages = report.filter((r) => r.hasScoped).map((r) => r.page);
const summary = {
  file, slides: report.length, overBudget: overPages.length, overPages, scopedPages,
  medianWords: report.map((r) => r.words).sort((a, b) => a - b)[Math.floor(report.length / 2)] ?? 0,
};
console.log(JSON.stringify(summaryOnly ? summary : { summary, slides: report }, null, 2));
