/**
 * Mermaid diagrams in decks: a ```mermaid fence is drawn as the diagram. Mermaid itself is a separate
 * bundle (studio-mermaid.js, ~5 MB) loaded the first time a deck has a mermaid fence, so decks without
 * diagrams never pay for it.
 *
 * Labels are plain SVG text (`htmlLabels: false`): HTML labels would put a second foreignObject inside
 * Marp's slide foreignObject, which WebKit paints badly when the slide is scaled, and they vanish when
 * the SVG is used as an image in the export.
 */
import { Marp } from "@marp-team/marp-core";

interface MermaidApi {
  initialize(config: Record<string, unknown>): void;
  render(id: string, text: string): Promise<{ svg: string }>;
}

declare global {
  interface Window {
    mermaid?: MermaidApi;
  }
}

/** The theme's own font stack (Marp's default theme), so diagram text sits with the slide text. */
const FONT = "-apple-system, BlinkMacSystemFont, 'Segoe UI', Helvetica, Arial, sans-serif";

/** Diagram size on a slide: never wider than the slide's content, never taller than two thirds of a 720px slide. */
export const DIAGRAM_CSS = "width:auto;height:auto;max-width:100%;max-height:480px;display:block;margin:0 auto";

let loading: Promise<MermaidApi> | null = null;

function load(src: string): Promise<MermaidApi> {
  loading ??= new Promise<MermaidApi>((resolve, reject) => {
    if (window.mermaid) return resolve(window.mermaid);
    const s = document.createElement("script");
    s.src = src;
    s.onload = () => (window.mermaid ? resolve(window.mermaid) : reject(new Error("mermaid did not load")));
    s.onerror = () => reject(new Error(`could not load ${src}`));
    document.head.appendChild(s);
  }).then((m) => {
    m.initialize({
      startOnLoad: false,
      securityLevel: "strict",
      theme: "default",
      fontFamily: FONT,
      htmlLabels: false,
      flowchart: { htmlLabels: false },
      themeVariables: { fontFamily: FONT, edgeLabelBackground: "#ffffff" },
      // SVG labels get a half-transparent box, so the edge line shows through the text; make it solid.
      themeCSS: ".edgeLabel rect, .labelBkg { opacity: 1 !important; fill: #ffffff !important; }",
    });
    return m;
  });
  // A failed load may be retried on the next render.
  loading.catch(() => (loading = null));
  return loading;
}

/** source → SVG. Diagrams render once; every later render of the deck (each keystroke) reuses them. */
const cache = new Map<string, string>();
let counter = 0;
/** Mermaid's render is not safe to run twice at once; one chain for every caller. */
let queue: Promise<unknown> = Promise.resolve();

/**
 * One diagram as an SVG string sized by its own viewBox (width/height in px), so it lays out the same
 * inline in the preview and as an image in the export. Throws Mermaid's parse error for bad source.
 */
export function renderDiagram(source: string, scriptSrc: string): Promise<string> {
  const hit = cache.get(source);
  if (hit) return Promise.resolve(hit);
  const run = queue.then(async () => {
    const again = cache.get(source);
    if (again) return again;
    const m = await load(scriptSrc);
    const id = `studio-mermaid-${++counter}`;
    try {
      const { svg } = await m.render(id, mermaidEntities(source));
      const sized = withNaturalSize(svg);
      if (cache.size > 200) cache.delete(cache.keys().next().value!);
      cache.set(source, sized);
      return sized;
    } finally {
      // Mermaid leaves its scratch element (or an error drawing) in the body when a render fails.
      document.getElementById(id)?.remove();
      document.getElementById(`d${id}`)?.remove();
    }
  });
  queue = run.catch(() => undefined);
  return run;
}

/**
 * HTML character references (`&#34;`, `&#x22;`), as editors and chat tools write the quotes of a label
 * (`Organizer[&#34;Organizer&#34;]`), turned back into the characters. With SVG labels Mermaid would print
 * them literally, and its own `#34;` codes do not decode in subgraph titles either.
 */
export function mermaidEntities(source: string): string {
  return source
    .replace(/&#(\d+);/g, (m, dec: string) => safeChar(Number(dec)) ?? m)
    .replace(/&#x([0-9a-f]+);/gi, (m, hex: string) => safeChar(parseInt(hex, 16)) ?? m);
}

function safeChar(code: number): string | undefined {
  return code > 31 && code <= 0x10ffff ? String.fromCodePoint(code) : undefined;
}

/** Mermaid writes `width="100%" style="max-width: Npx"`; replace both with the viewBox size. */
function withNaturalSize(svg: string): string {
  const doc = new DOMParser().parseFromString(svg, "image/svg+xml");
  const el = doc.documentElement;
  const vb = (el.getAttribute("viewBox") ?? "").split(/[\s,]+/).map(Number);
  if (vb.length === 4 && vb[2] > 0 && vb[3] > 0) {
    el.setAttribute("width", String(Math.ceil(vb[2])));
    el.setAttribute("height", String(Math.ceil(vb[3])));
    el.style.removeProperty("max-width");
    if (!el.getAttribute("style")) el.removeAttribute("style");
  }
  return new XMLSerializer().serializeToString(el);
}

export function cachedDiagram(source: string): string | undefined {
  return cache.get(source);
}

/** The ```mermaid code blocks in rendered Marp HTML, with their source text. */
export function diagramBlocks(root: ParentNode): Array<{ pre: HTMLElement; source: string }> {
  return Array.from(root.querySelectorAll<HTMLElement>("pre > code.language-mermaid")).map((code) => ({
    pre: code.parentElement as HTMLElement,
    source: code.textContent ?? "",
  }));
}

/** The diagram element that replaces a code block. */
export function diagramElement(svg: string, error?: string): HTMLElement {
  const fig = document.createElement("div");
  fig.className = "studio-mermaid";
  fig.innerHTML = svg;
  if (error) {
    const note = document.createElement("div");
    note.className = "studio-mermaid-error";
    note.textContent = error;
    fig.appendChild(note);
  }
  return fig;
}

let parser: Marp | null = null;

export interface DiagramFence {
  /** 0-based line range of the whole fence, closing line excluded by `end`. */
  start: number;
  end: number;
  /** What precedes the fence marker on its line (indent, `> `), kept on the replacement line. */
  prefix: string;
  source: string;
}

/** The mermaid fences of a deck by source line, from Marp's own tokens (not a regex), as slides.ts does. */
export function diagramFences(markdown: string): DiagramFence[] {
  parser ??= new Marp({ html: true });
  const lines = markdown.split("\n");
  const tokens = parser.markdown.parse(markdown, {}) as Array<{ type: string; info: string; content: string; map?: [number, number] | null }>;
  const out: DiagramFence[] = [];
  for (const t of tokens) {
    if (t.type !== "fence" || !t.map || t.info.trim().split(/\s+/)[0] !== "mermaid") continue;
    const [start, end] = t.map;
    const prefix = lines[start]?.match(/^(.*?)(`{3,}|~{3,})/)?.[1] ?? "";
    out.push({ start, end, prefix, source: t.content });
  }
  return out;
}

export function errorMessage(e: unknown): string {
  const text = String((e as Error)?.message ?? e).trim();
  return text.split("\n").slice(0, 3).join(" ").slice(0, 240);
}
