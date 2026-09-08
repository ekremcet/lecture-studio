"use client";
import { Marp } from "@marp-team/marp-core";

let parser: Marp | null = null;

/**
 * 0-based source line where each slide starts (the separator line, or 0 for the first slide).
 * Comes from Marpit's slide tokens, so separators inside code fences and the front matter fence
 * are not miscounted.
 */
export function slideStarts(markdown: string): number[] {
  parser ??= new Marp({ html: true });
  try {
    const tokens = parser.markdown.parse(markdown, {}) as Array<{ type: string; map?: [number, number] | null }>;
    return tokens.filter((t) => t.type === "marpit_slide_open").map((t) => t.map?.[0] ?? 0);
  } catch {
    return [0];
  }
}

/** 0-based slide index that contains the 0-based line. */
export function slideForLine(starts: number[], line: number): number {
  let lo = 0;
  let hi = starts.length - 1;
  while (lo < hi) {
    const mid = (lo + hi + 1) >> 1;
    if (starts[mid] <= line) lo = mid;
    else hi = mid - 1;
  }
  return lo;
}

/**
 * Presenter notes of one slide: the HTML comments of the slide that are not Marp directives
 * (`<!-- _class: lead -->`, `<!-- footer: ... -->`). Marp shows these in presenter view; the
 * studio shows them under the preview so a speaker can rehearse.
 */
const DIRECTIVE = /^_?(marp|theme|style|headingDivider|lang|size|math|paginate|header|footer|class|backgroundColor|backgroundImage|backgroundPosition|backgroundRepeat|backgroundSize|background\w*|color|title|description|author|keywords|url|image|transition)\s*:/i;

export function slideNotes(markdown: string, starts: number[], index: number): string[] {
  const lines = markdown.split("\n");
  const from = starts[index] ?? 0;
  const to = starts[index + 1] ?? lines.length;
  const text = lines.slice(from, to).join("\n");
  const out: string[] = [];
  const re = /<!--([\s\S]*?)-->/g;
  let m: RegExpExecArray | null;
  while ((m = re.exec(text))) {
    const body = m[1].trim();
    if (!body || DIRECTIVE.test(body)) continue;
    out.push(body);
  }
  return out;
}
