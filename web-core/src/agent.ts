/**
 * The agent bridge: the Oberik browser SDK inside a hidden WKWebView. Swift owns the conversation
 * state and the tools; this file forwards stream events up and tool calls, token requests, approvals
 * and questions across the bridge. Nothing here keeps the project key: tokens are minted in Swift.
 */
import { createClient, type AgentFramework, type Attachment, type Citation, type PendingApproval, type PendingQuestions, type QuestionAnswer, type StreamHandle, type TodoItem, type DocumentOut } from "@oberik/sdk";
import { TOOL_SPECS, UI_SPECS } from "./shared/tools";
import { summarize } from "./shared/summarize";
import { ask, post, errorText } from "./bridge";

const REPO_BASE = "studio-app://repo/";

let ai: AgentFramework | null = null;
const handles = new Map<string, StreamHandle>();
const approvals = new Map<string, (r: { approved: boolean; note: string | null }) => void>();
const questions = new Map<string, (a: QuestionAnswer) => void>();

function client(): AgentFramework {
  if (ai) return ai;
  ai = createClient({
    getToken: async ({ expired }) => {
      const r = await ask<{ token?: string; error?: string }>("token", { expired });
      if (!r?.token) throw new Error(r?.error ?? "no token");
      return r.token;
    },
    tools: TOOL_SPECS.map((spec) => ({
      ...spec,
      handler: async (args: Record<string, unknown>) => {
        const r = await ask<{ ok?: boolean; result?: unknown; error?: string }>("tool", { name: spec.name, args });
        if (r?.error) throw new Error(r.error);
        return r?.result;
      },
    })),
    ui: UI_SPECS.map((spec) => ({ ...spec, render: (args: Record<string, unknown>) => post("studio", { type: "ui", name: spec.name, args }) })),
  });
  return ai;
}

export interface SendInput {
  message: string;
  context?: string;
  session_id?: string | null;
  model?: string;
  tags: string[];
  /** Files the user attached: data: URIs built by Swift. */
  attachments?: Attachment[];
}

interface DoneOut {
  session_id?: string | null;
  content: string;
  attachments: Attachment[];
  citations: Citation[];
  model?: string | null;
  /** Mid-turn corrections the agent read, in order (empty on an ordinary turn). */
  steered: string[];
}

/**
 * Token posts are coalesced. The SDK reports every token; each post re-renders the transcript in
 * Swift, and doing that per token on a long reply froze the app (2026-09-09). One post per tick
 * carries the whole text so far (replace, not append: a reconnect can restart the text). A post goes
 * out at once when the last one is older than a tick, so throttled timers cannot stall the stream.
 */
const TOKEN_TICK_MS = 80;
const pendingTokens = new Map<string, { full: string; timer: ReturnType<typeof setTimeout> | null }>();
const lastTokenPost = new Map<string, number>();

function flushTokens(id: string) {
  const p = pendingTokens.get(id);
  if (!p) return;
  if (p.timer) clearTimeout(p.timer);
  pendingTokens.delete(id);
  lastTokenPost.set(id, Date.now());
  post("studio", { type: "chat", id, event: "token", full: p.full });
}

function queueToken(id: string, full: string) {
  const p = pendingTokens.get(id);
  if (p) p.full = full;
  else pendingTokens.set(id, { full, timer: null });
  const due = Date.now() - (lastTokenPost.get(id) ?? 0) >= TOKEN_TICK_MS;
  if (due) flushTokens(id);
  else if (!pendingTokens.get(id)!.timer) pendingTokens.get(id)!.timer = setTimeout(() => flushTokens(id), TOKEN_TICK_MS);
}

function chat(id: string, event: string, data: Record<string, unknown> = {}) {
  // Text posted so far lands before any other event of the turn, so steps, citations and the end of
  // the turn keep their order relative to the reply.
  flushTokens(id);
  post("studio", { type: "chat", id, event, ...data });
  if (event === "done" || event === "error") lastTokenPost.delete(id);
}

const api = {
  /** Start a turn. Events arrive on the `studio` channel with this id until `done` or `error`. */
  send(id: string, input: SendInput): void {
    const c = client();
    const h = c.chat.stream(
      { message: input.message + (input.context ? `\n\n(${input.context})` : ""), session_id: input.session_id ?? null, enable_ask_user: true, enable_approvals: true, model: input.model || undefined, tags: input.tags, enable_rag: true, attachments: input.attachments?.length ? input.attachments : undefined },
      {
        onReconnect: (attempt) => chat(id, "reconnect", { attempt }),
        onGuardrail: (stage, flags) => chat(id, "guardrail", { stage, flags }),
        onToken: (_d, full) => queueToken(id, full),
        onReasoning: (_d, full) => chat(id, "reasoning", { chars: full.length }),
        onToolStart: (name, inp) => chat(id, "toolStart", { name, summary: summarize(inp) }),
        onToolEnd: (name) => chat(id, "toolEnd", { name }),
        onToolCalls: (calls) => chat(id, "toolCalls", { calls: calls.map((x) => ({ name: x.name, summary: summarize(x.args) })) }),
        onAttachments: (files) => chat(id, "attachments", { attachments: files }),
        onCitations: (cs) => chat(id, "citations", { citations: cs }),
        onTodos: (items: TodoItem[]) => chat(id, "todos", { todos: items }),
        onCommandOutput: (chunk) => chat(id, "command", { command: chunk.command, delta: chunk.delta }),
        onApproval: (req: PendingApproval) => new Promise<{ approved: boolean; note: string | null }>((resolve) => {
          approvals.set(req.tool_call_id, resolve);
          chat(id, "approval", { request: { ...req, summary: req.tool ? `${req.tool}(${summarize(req.arguments, 600)})` : req.action } });
        }),
        onQuestion: (pending: PendingQuestions) => new Promise<QuestionAnswer>((resolve) => {
          questions.set(pending.tool_call_id, resolve);
          chat(id, "question", { pending });
        }),
      },
    );
    handles.set(id, h);
    h.done
      .then((res) => {
        const out: DoneOut = { session_id: res.session_id, content: res.content ?? "", attachments: res.attachments ?? [], citations: res.citations ?? [], model: res.model ?? null, steered: res.steered ?? [] };
        chat(id, "done", { result: out });
      })
      .catch((e) => chat(id, "error", { message: errorText(e) }))
      .finally(() => handles.delete(id));
  },
  async cancel(id: string): Promise<void> {
    await handles.get(id)?.cancel();
  },
  /** A message into the running turn; the agent reads it at its next step. The SDK can only hand it to
   *  a server run that is under way, and a turn spends much of its time between runs (client tools run
   *  here, then the next round starts), so keep offering it until a run takes it or the turn ends. False
   *  when the turn ended first: send it as a normal message then. Needs the `steer` capability. */
  async steer(id: string, message: string): Promise<boolean> {
    let attempts = 0;
    while (handles.has(id)) {
      const h = handles.get(id)!;
      if (await h.steer(message)) { post("studio", { type: "log", level: "info", message: `steer landed after ${attempts + 1} attempt(s)` }); return true; }
      if (attempts++ === 0) post("studio", { type: "log", level: "warn", message: `steer not taken yet (run=${h.runId() ?? "none"}); retrying until a step takes it or the turn ends` });
      await new Promise((r) => setTimeout(r, 600));
    }
    post("studio", { type: "log", level: "warn", message: `steer never taken (${attempts} attempts); sent as the next message` });
    return false;
  },
  resolveApproval(toolCallId: string, approved: boolean): boolean {
    const r = approvals.get(toolCallId);
    if (!r) return false;
    approvals.delete(toolCallId);
    r({ approved, note: approved ? null : "refused by the user" });
    return true;
  },
  answerQuestion(toolCallId: string, answer: QuestionAnswer): boolean {
    const r = questions.get(toolCallId);
    if (!r) return false;
    questions.delete(toolCallId);
    r(answer);
    return true;
  },
  documents: {
    /** Every document under any of the tags, once each. */
    async list(tags: string[]): Promise<DocumentOut[]> {
      const c = client();
      const pages = await Promise.all(tags.map((tag) => c.documents.list({ tag, limit: 200 })));
      const seen = new Set<string>();
      return pages.flatMap((p) => p.items).filter((d) => (seen.has(d.id) ? false : (seen.add(d.id), true)));
    },
    /** Index a file that is already in the repo. The bytes come through the app's URL scheme. */
    async upload(repoPath: string, name: string, tags: string[]): Promise<DocumentOut> {
      const res = await fetch(REPO_BASE + repoPath.split("/").map(encodeURIComponent).join("/"));
      if (!res.ok) throw new Error(`could not read ${repoPath}`);
      const blob = await res.blob();
      const file = new File([blob], name, { type: blob.type || undefined });
      return client().documents.uploadSimple(file, { filename: name, contentType: blob.type || undefined, tags, visibility: "private" });
    },
    delete: (id: string) => client().documents.delete(id),
    reingest: (id: string) => client().documents.reingest(id),
  },
  /** A cheap round trip to prove the bridge and the origin allow-list: one short turn, no tools. */
  async ping(): Promise<string> {
    const r = await client().chat.stream({ message: "Reply with the single word: pong" }, {}).done;
    return r.content ?? "";
  },
};

// Console errors and unhandled rejections are invisible in a hidden web view; forward them.
window.addEventListener("error", (e) => post("studio", { type: "log", level: "error", message: String(e.message) }));
window.addEventListener("unhandledrejection", (e) => post("studio", { type: "log", level: "error", message: "unhandled: " + errorText(e.reason) }));
const origError = console.error.bind(console);
console.error = (...args: unknown[]) => { origError(...args); post("studio", { type: "log", level: "error", message: args.map((a) => errorText(a)).join(" ") }); };
const origWarn = console.warn.bind(console);
console.warn = (...args: unknown[]) => { origWarn(...args); post("studio", { type: "log", level: "warn", message: args.map((a) => errorText(a)).join(" ") }); };

(window as unknown as { studioAgent: typeof api }).studioAgent = api;
post("studio", { type: "ready" });
