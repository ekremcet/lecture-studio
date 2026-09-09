/**
 * The preview WKWebView. Renders a Marp deck into this document, reports the visible slide while the
 * user scrolls, runs the overflow scan, and jumps to a slide on request. Themes come from Swift once;
 * assets resolve through the app's URL scheme.
 */
import { renderDeckWith } from "./shared/marp";
import { scanDocument, type QaResult } from "./shared/qa";
import { slideStarts } from "./shared/slides";
import MarkdownIt from "markdown-it";
import { post, errorText } from "./bridge";

const ASSET_BASE = "studio-app://repo/";
let themes: Record<string, string> = {};
let raf = 0;

function deckRoot(): HTMLElement {
  let el = document.getElementById("deck");
  if (!el) {
    el = document.createElement("div");
    el.id = "deck";
    document.body.appendChild(el);
  }
  return el;
}

function themeStyle(): HTMLStyleElement {
  let el = document.getElementById("theme") as HTMLStyleElement | null;
  if (!el) {
    el = document.createElement("style");
    el.id = "theme";
    document.head.appendChild(el);
  }
  return el;
}

function visibleSlide(): number {
  const svgs = Array.from(document.querySelectorAll<SVGSVGElement>("svg[data-marpit-svg]"));
  return svgs.findIndex((s) => s.getBoundingClientRect().bottom > 48);
}

/**
 * WebKit lays out a CSS-scaled inline-SVG slide correctly but paints the foreignObject content at
 * 1:1 (CSS `zoom` behaves the same). A transform on the svg itself keeps Marpit's
 * `div.marpit > svg` selectors intact, with no wrapper element.
 */
function fit() {
  const root = deckRoot();
  const available = Math.max(200, root.clientWidth);
  for (const svg of Array.from(root.querySelectorAll<SVGSVGElement>("svg[data-marpit-svg]"))) {
    const vb = svg.viewBox.baseVal;
    const w = vb && vb.width ? vb.width : 1280;
    const h = vb && vb.height ? vb.height : 720;
    const s = Math.min(1, available / w);
    // A transform is applied at paint time, which WebKit gets right; negative margins shrink the
    // layout box to the scaled size so the slides stack and centre as if they were that size.
    svg.style.width = `${w}px`;
    svg.style.height = `${h}px`;
    svg.style.transformOrigin = "top left";
    svg.style.transform = `scale(${s})`;
    svg.style.marginRight = `${-(w - w * s)}px`;
    svg.style.marginBottom = `${-(h - h * s)}px`;
  }
}

/** Presenter mode: one slide fills the viewport on a black ground. -1 shows the whole deck again. */
let presentIndex = -1;

function fitPresent() {
  const root = deckRoot();
  const svgs = Array.from(root.querySelectorAll<SVGSVGElement>("svg[data-marpit-svg]"));
  svgs.forEach((svg, i) => {
    const on = i === presentIndex;
    svg.style.display = on ? "block" : "none";
    if (!on) return;
    const vb = svg.viewBox.baseVal;
    const w = vb && vb.width ? vb.width : 1280;
    const h = vb && vb.height ? vb.height : 720;
    const s = Math.min(window.innerWidth / w, window.innerHeight / h);
    svg.style.width = `${w}px`;
    svg.style.height = `${h}px`;
    svg.style.transformOrigin = "top left";
    svg.style.transform = `translate(${(window.innerWidth - w * s) / 2}px, ${(window.innerHeight - h * s) / 2}px) scale(${s})`;
    svg.style.marginRight = "0";
    svg.style.marginBottom = "0";
  });
}

function layout() {
  if (presentIndex >= 0) fitPresent(); else fit();
}

window.addEventListener("resize", layout);

window.addEventListener("scroll", () => {
  if (raf) return;
  raf = requestAnimationFrame(() => {
    raf = 0;
    const idx = visibleSlide();
    if (idx >= 0) post("studio", { type: "visible", index: idx });
  });
}, { passive: true });

const api = {
  setThemes(t: Record<string, string>) {
    themes = t;
  },
  /** Render and report; keeps the scroll position, as the web preview does. */
  render(markdown: string, deckDir: string): { slideCount: number; starts: number[] } {
    try {
      const r = renderDeckWith(themes, ASSET_BASE, markdown, deckDir);
      const keep = window.scrollY;
      document.body.classList.remove("doc");
      themeStyle().textContent = r.css;
      deckRoot().innerHTML = r.html;
      layout();
      if (keep) window.scrollTo(0, keep);
      const starts = slideStarts(markdown);
      post("studio", { type: "rendered", slideCount: r.slideCount, starts });
      return { slideCount: r.slideCount, starts };
    } catch (e) {
      post("studio", { type: "error", message: errorText(e) });
      throw e;
    }
  },
  async scan(): Promise<QaResult> {
    const r = await scanDocument(document);
    post("studio", { type: "qa", result: r });
    return r;
  },
  /** Show one slide (0-based) full-viewport, or the scrolling deck when index is -1. */
  present(index: number) {
    presentIndex = index;
    document.body.classList.toggle("present", index >= 0);
    layout();
    if (index < 0) window.scrollTo(0, 0);
  },
  scrollTo(page: number, smooth = true) {
    const svg = document.querySelectorAll("svg[data-marpit-svg]")[page - 1];
    svg?.scrollIntoView({ behavior: smooth ? "smooth" : "instant", block: "start" });
  },
  starts(markdown: string): number[] {
    return slideStarts(markdown);
  },
  /** A markdown or plain-text document instead of a deck (the document preview). */
  renderDocument(markdown: string, deckDir: string, plain: boolean) {
    themeStyle().textContent = "";
    document.body.classList.add("doc");
    const root = deckRoot();
    if (plain) {
      const pre = document.createElement("pre");
      pre.className = "plain";
      pre.textContent = markdown;
      root.innerHTML = '<article class="md-view"></article>';
      root.firstElementChild!.appendChild(pre);
      return;
    }
    const md = new MarkdownIt({ html: true, linkify: true });
    // Relative images resolve against the file's folder through the app's URL scheme.
    const base = ASSET_BASE + (deckDir === "." ? "" : deckDir.split("/").map(encodeURIComponent).join("/") + "/");
    const defaultImage = md.renderer.rules.image!;
    md.renderer.rules.image = (tokens, idx, opts, env, self) => {
      const t = tokens[idx];
      const src = t.attrGet("src") ?? "";
      if (!/^(https?:|mailto:|#|\/|data:)/i.test(src)) t.attrSet("src", base + src.replace(/^\.\//, ""));
      return defaultImage(tokens, idx, opts, env, self);
    };
    root.innerHTML = '<article class="md-view">' + md.render(markdown) + "</article>";
  },
};

(window as unknown as { studioPreview: typeof api }).studioPreview = api;
post("studio", { type: "ready" });
