// Bundles the browser-side core (Marp preview, overflow scan, CodeMirror editor, Oberik agent bridge)
// for the macOS app's WKWebViews. scripts/build.sh copies dist/ into Sources/LectureStudio/Resources.
import { build, context } from "esbuild";
import { fileURLToPath } from "node:url";
import path from "node:path";
import { mkdir, cp, readdir } from "node:fs/promises";

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, "..");
const out = path.join(here, "dist");
const watch = process.argv.includes("--watch");

const entries = {
  "studio-preview": "src/preview.ts",
  "studio-editor": "src/editor.ts",
  "studio-agent": "src/agent.ts",
};

const options = {
  entryPoints: Object.fromEntries(Object.entries(entries).map(([k, v]) => [k, path.join(here, v)])),
  outdir: out,
  bundle: true,
  format: "iife",
  platform: "browser",
  target: ["safari17"],
  minify: !watch,
  sourcemap: watch ? "inline" : false,
  define: { "process.env.NODE_ENV": '"production"' },
  loader: { ".css": "text" },
  absWorkingDir: here,
};

await mkdir(path.join(out, "themes"), { recursive: true });
for (const f of await readdir(path.join(root, "themes"))) {
  if (f.endsWith(".css")) await cp(path.join(root, "themes", f), path.join(out, "themes", f));
}

if (watch) {
  const ctx = await context(options);
  await ctx.watch();
  console.log("watching", Object.keys(entries).join(", "));
} else {
  const r = await build({ ...options, metafile: true });
  for (const [file, meta] of Object.entries(r.metafile.outputs)) console.log(file, (meta.bytes / 1024).toFixed(0) + " KB");
}
