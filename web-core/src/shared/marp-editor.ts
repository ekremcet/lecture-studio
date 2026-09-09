/**
 * Editor language support for Marp decks: markdown with highlighted code fences, plus
 * decorations for what Marp adds on top of markdown (front matter, slide separators,
 * directive comments, image directives).
 */
import { markdown, markdownLanguage } from "@codemirror/lang-markdown";
import { languages } from "@codemirror/language-data";
import { HighlightStyle, syntaxHighlighting, defaultHighlightStyle } from "@codemirror/language";
import { tags as t } from "@lezer/highlight";
import { Decoration, type DecorationSet, EditorView, ViewPlugin, type ViewUpdate, showTooltip, type Tooltip } from "@codemirror/view";
import { RangeSetBuilder, StateField, type EditorState } from "@codemirror/state";

/** Prose colours on a light background. */
const markdownHighlight = HighlightStyle.define([
  { tag: t.heading1, fontWeight: "700", color: "#1d4ed8", fontSize: "1.15em" },
  { tag: t.heading2, fontWeight: "700", color: "#1d4ed8" },
  { tag: [t.heading3, t.heading4, t.heading5, t.heading6], fontWeight: "600", color: "#1e40af" },
  { tag: t.strong, fontWeight: "700" },
  { tag: t.emphasis, fontStyle: "italic" },
  { tag: t.strikethrough, textDecoration: "line-through" },
  { tag: t.link, color: "#0f766e", textDecoration: "underline" },
  { tag: t.url, color: "#0f766e" },
  { tag: t.monospace, color: "#9a3412", backgroundColor: "rgba(0,0,0,0.04)" },
  { tag: t.quote, color: "#6b7280", fontStyle: "italic" },
  { tag: t.processingInstruction, color: "#9ca3af" },
  { tag: t.contentSeparator, color: "#9ca3af", fontWeight: "700" },
  { tag: t.comment, color: "#6b7280", fontStyle: "italic" },
  { tag: t.meta, color: "#6b7280" },
  { tag: t.labelName, color: "#7c3aed" },
  { tag: t.tagName, color: "#be185d" },
  { tag: t.attributeName, color: "#92400e" },
  { tag: t.attributeValue, color: "#065f46" },
]);

/** The same roles on a dark background: lighter, less saturated, readable on #1e1e22. */
const markdownHighlightDark = HighlightStyle.define([
  { tag: t.heading1, fontWeight: "700", color: "#93c5fd", fontSize: "1.15em" },
  { tag: t.heading2, fontWeight: "700", color: "#93c5fd" },
  { tag: [t.heading3, t.heading4, t.heading5, t.heading6], fontWeight: "600", color: "#bfdbfe" },
  { tag: t.strong, fontWeight: "700", color: "#f4f4f5" },
  { tag: t.emphasis, fontStyle: "italic" },
  { tag: t.strikethrough, textDecoration: "line-through" },
  { tag: t.link, color: "#5eead4", textDecoration: "underline" },
  { tag: t.url, color: "#5eead4" },
  { tag: t.monospace, color: "#fdba74", backgroundColor: "rgba(255,255,255,0.06)" },
  { tag: t.quote, color: "#a1a1aa", fontStyle: "italic" },
  { tag: t.processingInstruction, color: "#71717a" },
  { tag: t.contentSeparator, color: "#71717a", fontWeight: "700" },
  { tag: t.comment, color: "#8b8b93", fontStyle: "italic" },
  { tag: t.meta, color: "#a1a1aa" },
  { tag: t.labelName, color: "#c4b5fd" },
  { tag: t.tagName, color: "#f9a8d4" },
  { tag: t.attributeName, color: "#fcd34d" },
  { tag: t.attributeValue, color: "#86efac" },
  { tag: t.keyword, color: "#c4b5fd" },
  { tag: [t.string, t.special(t.string)], color: "#86efac" },
  { tag: [t.number, t.bool, t.null], color: "#fdba74" },
  { tag: [t.function(t.variableName), t.function(t.propertyName)], color: "#93c5fd" },
  { tag: [t.typeName, t.className], color: "#5eead4" },
  { tag: t.operator, color: "#d4d4d8" },
  { tag: t.variableName, color: "#e4e4e7" },
  { tag: t.propertyName, color: "#bfdbfe" },
]);

const frontMatterLine = Decoration.line({ class: "cm-marp-frontmatter" });
const frontMatterFence = Decoration.line({ class: "cm-marp-frontmatter cm-marp-fence" });
const separatorLine = Decoration.line({ class: "cm-marp-separator" });
const directiveMark = Decoration.mark({ class: "cm-marp-directive" });
const keyMark = Decoration.mark({ class: "cm-marp-key" });
const imageDirectiveMark = Decoration.mark({ class: "cm-marp-image" });

const DIRECTIVE = /<!--\s*_?[a-zA-Z]+\s*:[\s\S]*?-->/g;
const IMAGE_DIRECTIVE = /!\[(bg[^\]]*|[^\]]*\b(?:w|h|width|height):\s*[^\]]*)\]/g;
const YAML_KEY = /^(\s*)([A-Za-z_][\w-]*)(\s*:)/;

function marpDecorations(view: EditorView): DecorationSet {
  const builder = new RangeSetBuilder<Decoration>();
  const doc = view.state.doc;
  // Front matter: only when the document starts with a fence.
  let fmEnd = -1;
  if (doc.lines > 1 && doc.line(1).text.trim() === "---") {
    for (let n = 2; n <= Math.min(doc.lines, 400); n++) {
      if (doc.line(n).text.trim() === "---") {
        fmEnd = n;
        break;
      }
    }
  }
  let inFence = false;
  for (const { from, to } of view.visibleRanges) {
    let n = doc.lineAt(from).number;
    const last = doc.lineAt(to).number;
    // Fences that opened before the visible range.
    for (let k = 1; k < n; k++) if (/^\s*(```|~~~)/.test(doc.line(k).text)) inFence = !inFence;
    for (; n <= last; n++) {
      const line = doc.line(n);
      const text = line.text;
      if (fmEnd > 0 && n <= fmEnd) {
        builder.add(line.from, line.from, n === 1 || n === fmEnd ? frontMatterFence : frontMatterLine);
        const m = text.match(YAML_KEY);
        if (m && n !== 1 && n !== fmEnd) builder.add(line.from + m[1].length, line.from + m[1].length + m[2].length, keyMark);
        continue;
      }
      if (/^\s*(```|~~~)/.test(text)) {
        inFence = !inFence;
        continue;
      }
      if (inFence) continue;
      if (text.trim() === "---") {
        builder.add(line.from, line.from, separatorLine);
        continue;
      }
      const marks: Array<[number, number, Decoration]> = [];
      for (const m of text.matchAll(DIRECTIVE)) marks.push([line.from + m.index!, line.from + m.index! + m[0].length, directiveMark]);
      for (const m of text.matchAll(IMAGE_DIRECTIVE)) marks.push([line.from + m.index!, line.from + m.index! + m[0].length, imageDirectiveMark]);
      marks.sort((a, b) => a[0] - b[0]);
      for (const [a, b, d] of marks) builder.add(a, b, d);
    }
    inFence = false;
  }
  return builder.finish();
}

const marpPlugin = ViewPlugin.fromClass(
  class {
    decorations: DecorationSet;
    constructor(view: EditorView) {
      this.decorations = marpDecorations(view);
    }
    update(u: ViewUpdate) {
      if (u.docChanged || u.viewportChanged) this.decorations = marpDecorations(u.view);
    }
  },
  { decorations: (v) => v.decorations },
);

const marpTheme = EditorView.baseTheme({
  ".cm-marp-frontmatter": { backgroundColor: "rgba(59,130,246,0.06)" },
  ".cm-marp-fence": { color: "#9ca3af" },
  ".cm-marp-key": { color: "#1d4ed8", fontWeight: "600" },
  ".cm-marp-separator": {
    backgroundColor: "rgba(0,0,0,0.05)",
    color: "#9ca3af",
    borderTop: "1px solid rgba(0,0,0,0.12)",
    borderBottom: "1px solid rgba(0,0,0,0.12)",
  },
  ".cm-marp-directive": { color: "#b45309", backgroundColor: "rgba(245,158,11,0.10)", borderRadius: "3px" },
  ".cm-marp-image": { color: "#0f766e", backgroundColor: "rgba(20,184,166,0.10)", borderRadius: "3px" },
});

const marpThemeDark = EditorView.theme(
  {
    "&": { color: "#e4e4e7", backgroundColor: "transparent" },
    ".cm-content": { caretColor: "#f4f4f5" },
    ".cm-cursor, .cm-dropCursor": { borderLeftColor: "#f4f4f5" },
    "&.cm-focused .cm-selectionBackground, .cm-selectionBackground, ::selection": { backgroundColor: "rgba(96,165,250,0.30)" },
    ".cm-activeLine": { backgroundColor: "rgba(255,255,255,0.05)" },
    ".cm-gutters": { backgroundColor: "transparent", color: "#71717a", borderRight: "1px solid rgba(255,255,255,0.10)" },
    ".cm-activeLineGutter": { backgroundColor: "rgba(255,255,255,0.05)", color: "#a1a1aa" },
    ".cm-matchingBracket": { backgroundColor: "rgba(96,165,250,0.25)", outline: "none" },
    ".cm-marp-frontmatter": { backgroundColor: "rgba(96,165,250,0.08)" },
    ".cm-marp-fence": { color: "#71717a" },
    ".cm-marp-key": { color: "#93c5fd", fontWeight: "600" },
    ".cm-marp-separator": {
      backgroundColor: "rgba(255,255,255,0.06)",
      color: "#71717a",
      borderTop: "1px solid rgba(255,255,255,0.12)",
      borderBottom: "1px solid rgba(255,255,255,0.12)",
    },
    ".cm-marp-directive": { color: "#fcd34d", backgroundColor: "rgba(245,158,11,0.14)", borderRadius: "3px" },
    ".cm-marp-image": { color: "#5eead4", backgroundColor: "rgba(20,184,166,0.14)", borderRadius: "3px" },
  },
  { dark: true },
);

/** Markdown with Marp awareness. Code fences use the language named after the fence. */
export function marpMarkdown(opts: { dark?: boolean } = {}) {
  return [
    markdown({ base: markdownLanguage, codeLanguages: languages, addKeymap: true }),
    // Both active: the markdown style for prose tokens, the default style for code inside fences
    // (the dark palette covers the code tags itself).
    ...(opts.dark ? [syntaxHighlighting(markdownHighlightDark)] : [syntaxHighlighting(markdownHighlight), syntaxHighlighting(defaultHighlightStyle)]),
    marpPlugin,
    opts.dark ? marpThemeDark : marpTheme,
  ];
}

/** Plain text on a dark background: the dark code palette only. */
export function plainDark() {
  return [syntaxHighlighting(markdownHighlightDark), marpThemeDark];
}

/** Wrap the main selection (or a placeholder) with inline markers. */
export function wrapSelection(view: EditorView, before: string, after: string, placeholder = "text") {
  const { from, to } = view.state.selection.main;
  const selected = view.state.sliceDoc(from, to) || placeholder;
  view.dispatch({
    changes: { from, to, insert: before + selected + after },
    selection: { anchor: from + before.length, head: from + before.length + selected.length },
    scrollIntoView: true,
  });
  view.focus();
}

const FORMATS: Array<{ label: string; title: string; before: string; after: string; placeholder?: string; style?: string }> = [
  { label: "B", title: "Bold", before: "**", after: "**", style: "font-weight:700" },
  { label: "I", title: "Italic", before: "*", after: "*", style: "font-style:italic" },
  { label: "S", title: "Strikethrough", before: "~~", after: "~~", style: "text-decoration:line-through" },
  { label: "<>", title: "Inline code", before: "`", after: "`", placeholder: "code", style: "font-family:ui-monospace,Menlo,monospace" },
  { label: "Link", title: "Link", before: "[", after: "](https://)", placeholder: "text" },
];

function selectionTooltip(state: EditorState): Tooltip | null {
  const sel = state.selection.main;
  if (sel.empty) return null;
  return {
    pos: Math.min(sel.from, sel.to),
    above: true,
    strictSide: true,
    arrow: false,
    create: (view) => {
      const dom = document.createElement("div");
      dom.className = "cm-marp-format";
      for (const f of FORMATS) {
        const b = document.createElement("button");
        b.type = "button";
        b.textContent = f.label;
        b.title = f.title;
        if (f.style) b.setAttribute("style", f.style);
        // mousedown, not click: a click would first move the selection and lose it.
        b.addEventListener("mousedown", (e) => {
          e.preventDefault();
          wrapSelection(view, f.before, f.after, f.placeholder);
        });
        dom.appendChild(b);
      }
      return { dom };
    },
  };
}

const selectionTooltipField = StateField.define<Tooltip | null>({
  create: selectionTooltip,
  update(value, tr) {
    return tr.docChanged || tr.selection ? selectionTooltip(tr.state) : value;
  },
  provide: (f) => showTooltip.from(f),
});

const formatTheme = EditorView.baseTheme({
  ".cm-tooltip:has(> .cm-marp-format)": { border: "none", background: "transparent" },
  ".cm-marp-format": {
    display: "flex",
    gap: "2px",
    padding: "3px",
    borderRadius: "8px",
    background: "rgba(30,30,34,0.96)",
    boxShadow: "0 4px 16px rgba(0,0,0,0.35)",
    border: "1px solid rgba(255,255,255,0.12)",
  },
  ".cm-marp-format button": {
    all: "unset",
    cursor: "pointer",
    color: "#e4e4e7",
    font: "12px -apple-system, system-ui, sans-serif",
    minWidth: "24px",
    height: "22px",
    padding: "0 6px",
    borderRadius: "5px",
    textAlign: "center",
    lineHeight: "22px",
  },
  ".cm-marp-format button:hover": { background: "rgba(255,255,255,0.12)" },
});

/** A small formatting bubble above the selection: bold, italic, strike, code, link. */
export function selectionToolbar() {
  return [selectionTooltipField, formatTheme];
}
