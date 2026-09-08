/** A short, single-line form of a tool input or output for the step list. Shared by the web app and the Mac bridge. */
export function summarize(v: unknown, max = 120): string {
  if (v == null) return "";
  const s = typeof v === "string" ? v : JSON.stringify(v);
  return s.length > max ? s.slice(0, max - 1) + "…" : s;
}
