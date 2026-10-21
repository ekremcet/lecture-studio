/**
 * The editor WKWebView: CodeMirror with Marp language support. Swift sets the text
 * and hears about edits (debounced), the line at the top or under the cursor, ⌘S, and passages sent to the chat.
 * Find and replace run here too; the find bar itself is native (FindBar.swift) and drives them.
 */
import { EditorState, Compartment } from "@codemirror/state";
import { EditorView, keymap, lineNumbers, highlightActiveLine } from "@codemirror/view";
import { defaultKeymap, history, historyKeymap } from "@codemirror/commands";
import { search, SearchQuery, setSearchQuery, getSearchQuery, searchPanelOpen, openSearchPanel, closeSearchPanel, findNext, findPrevious, replaceNext, replaceAll } from "@codemirror/search";
import { syntaxHighlighting, defaultHighlightStyle, bracketMatching } from "@codemirror/language";
import { marpMarkdown, plainDark, selectionToolbar, wrapSelection } from "./shared/marp-editor";
import { post } from "./bridge";

const language = new Compartment();
let changeTimer = 0;
let suppress = false;
let dark = false;
let kind: "markdown" | "plain" = "markdown";

type FindSpec = { search: string; replace: string; caseSensitive: boolean; regexp: boolean; wholeWord: boolean };
/** Counting stops here, so a one-letter query on a long deck stays quick. */
const MAX_MATCHES = 1000;

/** How many matches the query has, and which one (1-based) the selection sits on. */
function findStatus(state: EditorState, limit = MAX_MATCHES) {
  const query = getSearchQuery(state);
  if (!query.search) return { count: 0, current: 0, invalid: false, capped: false };
  if (!query.valid) return { count: 0, current: 0, invalid: true, capped: false };
  const sel = state.selection.main;
  let count = 0;
  let current = 0;
  const cursor = query.getCursor(state) as Iterator<{ from: number; to: number }>;
  for (let r = cursor.next(); !r.done; r = cursor.next()) {
    count++;
    if (r.value.from === sel.from && r.value.to === sel.to) current = count;
    if (count >= limit) return { count, current, invalid: false, capped: true };
  }
  return { count, current, invalid: false, capped: false };
}

function langExt() {
  if (kind === "markdown") return [...marpMarkdown({ dark }), ...selectionToolbar({ onAddToChat: (text, from, to) => post("studio", { type: "addToChat", text, from, to }) })];
  return dark ? plainDark() : [syntaxHighlighting(defaultHighlightStyle)];
}

const view = new EditorView({
  state: EditorState.create({
    doc: "",
    extensions: [
      lineNumbers(),
      highlightActiveLine(),
      history(),
      language.of(langExt()),
      // CodeMirror's search state and match highlighting, with an empty panel: the bar is native.
      search({ createPanel: () => { const dom = document.createElement("div"); dom.style.display = "none"; return { dom }; } }),
      bracketMatching(),
      EditorView.lineWrapping,
      keymap.of([
        { key: "Mod-s", run: () => (post("studio", { type: "save" }), true) },
        { key: "Escape", run: (v) => (searchPanelOpen(v.state) ? (post("studio", { type: "findClose" }), true) : false) },
        ...defaultKeymap,
        ...historyKeymap,
      ]),
      EditorView.updateListener.of((u) => {
        if (searchPanelOpen(u.state) && (u.docChanged || u.selectionSet || u.transactions.some((t) => t.effects.some((e) => e.is(setSearchQuery))))) {
          post("studio", { type: "find", ...findStatus(u.state) });
        }
        if (u.docChanged && !suppress) {
          clearTimeout(changeTimer);
          changeTimer = window.setTimeout(() => post("studio", { type: "change", text: u.state.doc.toString() }), 120);
        }
        if (u.selectionSet && !u.docChanged) {
          const line = u.state.doc.lineAt(u.state.selection.main.head).number - 1;
          post("studio", { type: "line", line, source: "cursor" });
        }
      }),
      EditorView.domEventHandlers({
        scroll: (_e, v) => {
          const block = v.lineBlockAtHeight(v.scrollDOM.scrollTop + 4);
          const line = v.state.doc.lineAt(block.from).number - 1;
          post("studio", { type: "line", line, source: "scroll" });
        },
      }),
      EditorView.theme({
        "&": { height: "100vh", fontSize: "13px" },
        ".cm-scroller": { fontFamily: "ui-monospace, SFMono-Regular, Menlo, monospace" },
        ".cm-gutters": { backgroundColor: "transparent", borderRight: "1px solid rgba(0,0,0,0.1)" },
      }),
    ],
  }),
  parent: document.body,
});

const api = {
  /** Replace the document without echoing a change event back. */
  setValue(text: string, k: "markdown" | "plain" = "markdown") {
    kind = k;
    const current = view.state.doc.toString();
    suppress = true;
    try {
      view.dispatch({
        changes: current !== text ? { from: 0, to: current.length, insert: text } : undefined,
        effects: language.reconfigure(langExt()),
      });
    } finally {
      suppress = false;
    }
  },
  getValue(): string {
    return view.state.doc.toString();
  },
  scrollToLine(line: number) {
    const n = Math.min(Math.max(1, line + 1), view.state.doc.lines);
    view.dispatch({ effects: EditorView.scrollIntoView(view.state.doc.line(n).from, { y: "start", yMargin: 6 }) });
  },
  focus() {
    view.focus();
  },
  /** Select whole lines (1-based, inclusive). Used by the smoke walk. */
  selectLines(from: number, to: number) {
    const doc = view.state.doc;
    const a = doc.line(Math.min(Math.max(1, from), doc.lines));
    const b = doc.line(Math.min(Math.max(from, to), doc.lines));
    view.dispatch({ selection: { anchor: a.from, head: b.to }, scrollIntoView: true });
  },
  /**
   * Insert a Marp block at the cursor. The block starts on its own line; `{cursor}` marks where the
   * caret goes afterwards (else the end of the block). Selected text replaces `{selection}`.
   */
  insertBlock(snippet: string) {
    const { from, to } = view.state.selection.main;
    const selected = view.state.sliceDoc(from, to);
    const line = view.state.doc.lineAt(from);
    const atLineStart = from === line.from;
    const prefix = atLineStart ? "" : "\n";
    let text = prefix + snippet.replace("{selection}", selected);
    let cursor = text.indexOf("{cursor}");
    if (cursor >= 0) text = text.replace("{cursor}", ""); else cursor = text.length;
    view.dispatch({ changes: { from, to, insert: text }, selection: { anchor: from + cursor }, scrollIntoView: true });
    view.focus();
  },
  /** Wrap the selection (or insert a placeholder) with inline markers, e.g. ** for bold. */
  wrap(before: string, after: string, placeholder = "text") {
    wrapSelection(view, before, after, placeholder);
  },
  /** The text to search for when the find bar opens: the selection, if it is short and on one line. */
  selectionForFind(): string {
    const { from, to } = view.state.selection.main;
    const text = view.state.sliceDoc(from, to);
    return text.length > 0 && text.length <= 200 && !text.includes("\n") ? text : "";
  },
  /** Set the query and highlight its matches. The status comes back as a "find" message. */
  find(spec: FindSpec) {
    if (!searchPanelOpen(view.state)) openSearchPanel(view);
    const query = new SearchQuery({ ...spec, literal: !spec.regexp });
    // Find as you type: the first match from the cursor on (wrapping) is selected and scrolled to.
    let match: { from: number; to: number } | undefined;
    if (query.search && query.valid) {
      const from = view.state.selection.main.from;
      const after = query.getCursor(view.state, from).next();
      match = after.done ? undefined : after.value;
      if (!match) {
        const first = query.getCursor(view.state).next();
        match = first.done ? undefined : first.value;
      }
    }
    view.dispatch({
      effects: [setSearchQuery.of(query), ...(match ? [EditorView.scrollIntoView(match.from, { y: "center" })] : [])],
      selection: match ? { anchor: match.from, head: match.to } : undefined,
      userEvent: "select.search",
    });
  },
  /** Step to the next (or previous) match, wrapping around the document. */
  findNext(backwards = false) {
    (backwards ? findPrevious : findNext)(view);
  },
  /** Replace the selected match and move on to the next one. */
  replaceNext() {
    replaceNext(view);
  },
  /** Replace every match in one undoable step; answers how many were replaced. */
  replaceAll(): number {
    const n = findStatus(view.state, Infinity).count;
    return replaceAll(view) ? n : 0;
  },
  /** Drop the highlights. `focus` hands the keyboard back to the text. */
  endFind(focus: boolean) {
    closeSearchPanel(view);
    if (focus) view.focus();
  },
  setDark(d: boolean) {
    dark = d;
    document.documentElement.style.colorScheme = d ? "dark" : "light";
    document.body.style.background = d ? "#1e1e22" : "#ffffff";
    view.dispatch({ effects: language.reconfigure(langExt()) });
  },
};

(window as unknown as { studioEditor: typeof api }).studioEditor = api;
post("studio", { type: "ready" });
