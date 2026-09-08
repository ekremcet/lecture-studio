"use client";
/** Thin wrappers over the local repo API. Paths are repo-relative. */

async function json<T>(res: Response): Promise<T> {
  const body = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error((body as { error?: string }).error ?? `${res.status} ${res.statusText}`);
  return body as T;
}

export type FileKind = "deck" | "md" | "pdf" | "docx" | "xlsx" | "pptx" | "image" | "text" | "other";
export interface FileInfo { path: string; course: string; unit: string; name: string; kind: FileKind; title: string; size: number }
export const TEXT_KINDS: FileKind[] = ["deck", "md", "text"];
export interface LectureMeta { title?: string; code?: string; term?: string; kind?: "course" | "talk"; unitPrefix?: string; language?: string }
export interface Profile { name: string; affiliation?: string; unit?: string; email?: string; contact?: string[]; language?: string; style?: string; unitLabel?: string }
export type SourceScope = "global" | "lecture" | "unit";
export interface DiskSource { path: string; name: string; size: number; scope: SourceScope }

export interface GitStatus {
  root: string;
  branch: string;
  upstream: string | null;
  ahead: number;
  behind: number;
  changes: Array<{ status: string; path: string }>;
  lastCommit: { hash: string; date: string; subject: string } | null;
  fetchError?: string | null;
}

export const api = {
  files: () => fetch("/api/repo/files").then((r) => json<{ files: FileInfo[]; lectures: Record<string, LectureMeta>; sources: number }>(r)),
  tree: (path: string) => fetch(`/api/repo/tree?path=${encodeURIComponent(path)}`).then((r) => json<{ entries: Array<{ name: string; kind: "file" | "dir"; size?: number }> }>(r)),
  read: (path: string, from?: number, to?: number) => {
    const q = new URLSearchParams({ path });
    if (from) q.set("from", String(from));
    if (to) q.set("to", String(to));
    return fetch(`/api/repo/file?${q}`).then((r) => json<{ text: string; lines: number; from: number; to: number }>(r));
  },
  create: (path: string, content: string) => fetch("/api/repo/file", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ op: "create", path, content }) }).then((r) => json<{ ok: true }>(r)),
  overwrite: (path: string, content: string) => fetch("/api/repo/file", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ op: "overwrite", path, content }) }).then((r) => json<{ ok: true }>(r)),
  append: (path: string, content: string) => fetch("/api/repo/file", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ op: "append", path, content }) }).then((r) => json<{ ok: true }>(r)),
  replace: (path: string, oldText: string, newText: string) => fetch("/api/repo/file", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ op: "replace", path, old: oldText, new: newText }) }).then((r) => json<{ ok: true; line: number }>(r)),
  saveAsset: (week_dir: string, filename: string, source: string, overwrite = false) => fetch("/api/repo/asset", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ week_dir, filename, source, overwrite }) }).then((r) => json<{ path: string; bytes: number; markdown: string }>(r)),
  render: (path: string) => fetch(`/api/repo/render?path=${encodeURIComponent(path)}`).then((r) => json<{ kind: "docx"; html: string; warnings: string[] } | { kind: "xlsx"; sheets: Array<{ name: string; html: string; truncated: boolean }> }>(r)),
  courseMeta: (course: string) => fetch(`/api/repo/scaffold?course=${encodeURIComponent(course)}`).then((r) => json<{ code: string; courseName: string; unitPrefix: string; kind: "course" | "talk"; weeks: number[]; topics: Record<number, string> }>(r)),
  scaffold: (body: Record<string, unknown>) => fetch("/api/repo/scaffold", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify(body) }).then((r) => json<{ ok: true; course?: string; unit?: string; deck?: string; path?: string; created?: string[] }>(r)),
  models: () => fetch("/api/oberik/models").then((r) => json<{ models: Array<{ id: string; provider: string; input: string[] }>; defaultModel: string | null; tiers?: { mode: "off" | "auto"; simple: string | null; normal: string | null; complex: string | null } }>(r)),
  uploadSource: (course: string, unit: string, file: File) => {
    const form = new FormData();
    form.set("course", course);
    form.set("unit", unit);
    form.set("file", file);
    return fetch("/api/repo/upload", { method: "POST", body: form }).then((r) => json<{ ok: true; path: string; size: number }>(r));
  },
  sources: (course: string, unit: string) => fetch(`/api/repo/sources?course=${encodeURIComponent(course)}&unit=${encodeURIComponent(unit)}`).then((r) => json<{ sources: DiskSource[] }>(r)),
  profile: () => fetch("/api/repo/profile").then((r) => json<{ exists: boolean; profile: Profile }>(r)),
  saveProfile: (profile: Profile) => fetch("/api/repo/profile", { method: "PUT", headers: { "content-type": "application/json" }, body: JSON.stringify(profile) }).then((r) => json<{ ok: true; profile: Profile }>(r)),
  deleteSource: (path: string) => fetch(`/api/repo/upload?path=${encodeURIComponent(path)}`, { method: "DELETE" }).then((r) => json<{ ok: true }>(r)),
  git: (fetchFirst = false) => fetch(`/api/repo/git${fetchFirst ? "?fetch=1" : ""}`).then((r) => json<GitStatus>(r)),
  gitOp: (op: "commit" | "push" | "pull", message?: string) => fetch("/api/repo/git", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ op, message }) }).then((r) => json<{ ok: true; hash?: string; files?: number; output?: string }>(r)),
};

export function deckDir(path: string): string {
  return path.includes("/") ? path.slice(0, path.lastIndexOf("/")) : ".";
}

export function rawUrl(path: string): string {
  return "/api/repo/raw/" + path.split("/").map(encodeURIComponent).join("/");
}
