/**
 * The editor WKWebView: CodeMirror with the Marp language support of the web app. Swift sets the text
 * and hears about edits (debounced), the line at the top or under the cursor, and ⌘S.
 */
import { EditorState, Compartment } from "@codemirror/state";
import { EditorView, keymap, lineNumbers, highlightActiveLine } from "@codemirror/view";
import { defaultKeymap, history, historyKeymap } from "@codemirror/commands";
import { syntaxHighlighting, defaultHighlightStyle, bracketMatching } from "@codemirror/language";
import { marpMarkdown, plainDark, selectionToolbar, wrapSelection } from "./shared/marp-editor";
import { post } from "./bridge";

const language = new Compartment();
let changeTimer = 0;
let suppress = false;
let dark = false;
let kind: "markdown" | "plain" = "markdown";

function langExt() {
  if (kind === "markdown") return [...marpMarkdown({ dark }), ...selectionToolbar()];
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
      bracketMatching(),
      EditorView.lineWrapping,
      keymap.of([{ key: "Mod-s", run: () => (post("studio", { type: "save" }), true) }, ...defaultKeymap, ...historyKeymap]),
      EditorView.updateListener.of((u) => {
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
  setDark(d: boolean) {
    dark = d;
    document.documentElement.style.colorScheme = d ? "dark" : "light";
    document.body.style.background = d ? "#1e1e22" : "#ffffff";
    view.dispatch({ effects: language.reconfigure(langExt()) });
  },
};

(window as unknown as { studioEditor: typeof api }).studioEditor = api;
post("studio", { type: "ready" });
