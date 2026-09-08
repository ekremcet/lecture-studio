"use client";
import { Marp } from "@marp-team/marp-core";

let themesPromise: Promise<Record<string, string>> | null = null;

async function loadThemes(): Promise<Record<string, string>> {
  if (!themesPromise) {
    themesPromise = fetch("/api/themes").then(async (r) => ((await r.json()).themes ?? {}) as Record<string, string>);
  }
  return themesPromise;
}

/** Rewrite relative asset references to the local raw route so the preview can load them. */
export function rewriteAssets(markdown: string, deckDir: string, assetBase = "/api/repo/raw/"): string {
  const base = assetBase + deckDir.split("/").map(encodeURIComponent).join("/") + "/";
  return markdown
    // ![alt](./assets/x.png) and ![bg right](assets/x.png)
    .replace(/(!\[[^\]]*\]\()(?:\.\/)?(assets\/[^)\s]+)/g, (_m, open: string, rel: string) => open + base + rel)
    // <img src="assets/x.png">
    .replace(/(src=["'])(?:\.\/)?(assets\/[^"']+)/g, (_m, open: string, rel: string) => open + base + rel);
}

export interface Rendered {
  html: string;
  css: string;
  slideCount: number;
}

export async function renderDeck(markdown: string, deckDir: string): Promise<Rendered> {
  return renderDeckWith(await loadThemes(), "/api/repo/raw/", markdown, deckDir);
}

/**
 * The same render with the themes and the asset root given, for hosts that have no `/api`:
 * the macOS app passes the theme files it bundles and its own asset URL scheme.
 */
export function renderDeckWith(themes: Record<string, string>, assetBase: string, markdown: string, deckDir: string): Rendered {
  const marp = new Marp({ html: true, inlineSVG: true });
  for (const css of Object.values(themes)) {
    try {
      marp.themeSet.add(css);
    } catch (e) {
      console.warn("theme rejected", e);
    }
  }
  const { html, css } = marp.render(rewriteAssets(markdown, deckDir, assetBase));
  const slideCount = (html.match(/<svg data-marpit-svg/g) ?? []).length;
  return { html, css, slideCount };
}

/** The full document put into the preview iframe. */
export function previewDocument(r: Rendered): string {
  return `<!doctype html><html><head><meta charset="utf-8">
<style>${r.css}</style>
<style>
  html,body{margin:0;background:#4a4a4a}
  body{padding:12px 0 40px}
  .marpit{display:flex;flex-direction:column;gap:14px;align-items:center}
  .marpit > svg{width:min(100%,1280px);height:auto;display:block;box-shadow:0 2px 10px rgba(0,0,0,.4);background:#fff;scroll-margin-top:12px}
  .marpit > svg.qa-overflow{outline:4px solid #e5484d}
  .marpit > svg.qa-missing{outline:4px solid #f5a524}
  .qa-page{position:fixed;left:8px;top:8px;color:#fff;font:12px system-ui;background:#0008;padding:2px 6px;border-radius:4px}
</style></head><body>${r.html}</body></html>`;
}
