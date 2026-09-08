"use client";
import type { ClientToolDef, UiComponent } from "@oberik/sdk";
import { api } from "./api";
import type { QaResult } from "./qa";

/** What the tools need from the page: a way to run QA on a deck and to react to file changes. */
export interface ToolHost {
  qaDeck: (path: string) => Promise<QaResult>;
  showPreview: (path: string, page?: number) => void;
  onFileChanged: (path: string) => void;
  /** Directory of the open file, for "save to assets" defaults. */
  currentDir?: () => string;
  /** Source materials the current conversation can search, with their index status. */
  listSources: () => Promise<Array<{ name: string; path?: string; scope: string; status: string }>>;
}

const str = (v: unknown) => (typeof v === "string" ? v : String(v ?? ""));
const num = (v: unknown) => (typeof v === "number" ? v : v == null || v === "" ? undefined : Number(v));

/** A tool as the agent sees it: name, description, schema. The handler is what differs per host. */
export interface ToolSpec {
  name: string;
  description: string;
  parameters: ClientToolDef["parameters"];
  requiresApproval?: boolean;
}

/** The ten client tools, host-independent. The web app and the macOS app attach their own handlers. */
export const TOOL_SPECS: ToolSpec[] = [
  {
    name: "list_dir",
    description: "List one directory of the LECTURE REPO (not the sandbox). Path is relative to the repo root; use '.' for the root. Returns name, kind, size.",
    parameters: { type: "object", properties: { path: { type: "string", description: "repo-relative directory, e.g. 'yzm2021-fall26/week3'" } }, required: ["path"] },
  },
  {
    name: "read_file",
    description: "Read a text file from the LECTURE REPO, optionally a 1-based inclusive line range. Decks are 800-2600 lines: read the front matter first, then ranges. Returns text plus total line count.",
    parameters: {
      type: "object",
      properties: {
        path: { type: "string" },
        from: { type: "integer", description: "first line, 1-based" },
        to: { type: "integer", description: "last line, inclusive" },
      },
      required: ["path"],
    },
  },
  {
    name: "create_file",
    description: "Create a NEW text file in the LECTURE REPO. Fails if the file exists (use overwrite_file, append_file or replace_in_file then). For a long deck: create it with the front matter and the first slides, then append_file the rest in sections of 10-15 slides.",
    parameters: { type: "object", properties: { path: { type: "string" }, content: { type: "string" } }, required: ["path", "content"] },
  },
  {
    name: "overwrite_file",
    description: "Replace the WHOLE content of an existing file in the LECTURE REPO. Needs the user's approval. Prefer replace_in_file for edits.",
    parameters: { type: "object", properties: { path: { type: "string" }, content: { type: "string" } }, required: ["path", "content"] },
    requiresApproval: true,
  },
  {
    name: "append_file",
    description: "Append text to the end of an existing file in the LECTURE REPO. Use it to write a deck in sections. Start the content with a newline and the '---' slide separator when you continue a deck.",
    parameters: { type: "object", properties: { path: { type: "string" }, content: { type: "string" } }, required: ["path", "content"] },
  },
  {
    name: "replace_in_file",
    description: "Replace exactly one occurrence of `old` with `new` in a file of the LECTURE REPO. `old` must match once: include enough surrounding lines to be unique. Returns the line where the change starts.",
    parameters: { type: "object", properties: { path: { type: "string" }, old: { type: "string" }, new: { type: "string" } }, required: ["path", "old", "new"] },
  },
  {
    name: "save_asset",
    description: "Save an image into `<week_dir>/assets/<filename>` of the LECTURE REPO. `source` is an https URL (downloaded server-side) or a data: URI (base64, for a diagram made in the sandbox under 2 MB). Refuses to overwrite. Returns the repo path and the markdown to reference it.",
    parameters: {
      type: "object",
      properties: {
        week_dir: { type: "string", description: "e.g. 'yzm2021-fall26/week3'" },
        filename: { type: "string", description: "kebab-case with extension, e.g. 'waterfall-meme.jpg'" },
        source: { type: "string", description: "https URL or data:image/...;base64,..." },
      },
      required: ["week_dir", "filename", "source"],
    },
  },
  {
    name: "list_sources",
    description: "List the SOURCE MATERIALS (readings, papers, notes, slides) the user has attached to the open lecture and unit, plus the global ones, with their index status. Call it before you plan or write content, then search them with rag_search and cite them. A file whose status is not 'ready' cannot be searched yet.",
    parameters: { type: "object", properties: {} },
  },
  {
    name: "qa_deck",
    description: "Render a deck of the LECTURE REPO in the user's preview and check every slide for overflow (elements outside the 1280x720 slide), missing images, and scoped styles. Returns per-slide reports and the lists of failing pages. Run it after every write and fix what it reports.",
    parameters: { type: "object", properties: { path: { type: "string" } }, required: ["path"] },
  },
];

export const UI_SPECS = [
  {
    name: "show_preview",
    description: "Show a deck of the LECTURE REPO in the user's preview panel, scrolled to a slide. Use it to point the user at what you changed.",
    parameters: { type: "object", properties: { path: { type: "string" }, page: { type: "integer", description: "1-based slide number" } }, required: ["path"] },
  },
];

/** The QA payload kept small for the model: only failing slides in detail. */
export function compactQa(r: QaResult) {
  const failing = r.slides.filter((s) => s.offenders.length || s.missingImages.length || s.scrollOverflowY > 2);
  return {
    slides: r.slides.length,
    overflowPages: r.overflowPages,
    missingImagePages: r.missingImagePages,
    scopedStylePages: r.slides.filter((s) => s.warnings.includes("scoped style present")).map((s) => s.page),
    details: failing.map((s) => ({ page: s.page, title: s.title, words: s.words, scrollOverflowY: s.scrollOverflowY, offenders: s.offenders.slice(0, 5), missingImages: s.missingImages, warnings: s.warnings })),
  };
}

type Handler = ClientToolDef["handler"];

export function makeTools(host: ToolHost): ClientToolDef[] {
  const changed = <T,>(path: unknown, r: T): T => {
    host.onFileChanged(str(path));
    return r;
  };
  const handlers: Record<string, Handler> = {
    list_dir: async ({ path }) => (await api.tree(str(path) || ".")).entries,
    read_file: async ({ path, from, to }) => api.read(str(path), num(from), num(to)),
    create_file: async ({ path, content }) => changed(path, await api.create(str(path), str(content))),
    overwrite_file: async ({ path, content }) => changed(path, await api.overwrite(str(path), str(content))),
    append_file: async ({ path, content }) => changed(path, await api.append(str(path), str(content))),
    replace_in_file: async ({ path, old, new: newText }) => changed(path, await api.replace(str(path), str(old), str(newText))),
    save_asset: async ({ week_dir, filename, source }) => api.saveAsset(str(week_dir), str(filename), str(source)),
    list_sources: async () => host.listSources(),
    qa_deck: async ({ path }) => compactQa(await host.qaDeck(str(path))),
  };
  return TOOL_SPECS.map((spec) => ({ ...spec, handler: handlers[spec.name] }));
}

export function makeUi(host: ToolHost): UiComponent[] {
  return UI_SPECS.map((spec) => ({ ...spec, render: (args) => host.showPreview(str(args.path), num(args.page)) }));
}
