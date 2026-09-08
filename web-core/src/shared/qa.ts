"use client";
/**
 * Overflow scan on the rendered Marp DOM. Port of a Node script that ran against exported HTML,
 * with one change: geometry comes from getBoundingClientRect relative to the section, scaled back to
 * slide pixels, so it does not depend on offsetParent.
 */

export interface Offender {
  tag: string;
  text: string;
  rightOverflow: number;
  bottomOverflow: number;
}

export interface SlideReport {
  page: number;
  title: string;
  characters: number;
  words: number;
  scrollOverflowX: number;
  scrollOverflowY: number;
  offenders: Offender[];
  missingImages: string[];
  warnings: string[];
}

export interface QaResult {
  slides: SlideReport[];
  overflowPages: number[];
  missingImagePages: number[];
}

const SELECTOR = "h1,h2,h3,h4,p,li,pre,table,blockquote,img,svg,.two-columns,.column,.columns,.columns-3";
const TOLERANCE = 2;

async function waitForImages(doc: Document, timeoutMs = 8000): Promise<void> {
  const imgs = Array.from(doc.images);
  const pending = imgs.filter((i) => !i.complete).map(
    (i) => new Promise<void>((resolve) => {
      i.addEventListener("load", () => resolve(), { once: true });
      i.addEventListener("error", () => resolve(), { once: true });
    }),
  );
  await Promise.race([Promise.all(pending), new Promise((r) => setTimeout(r, timeoutMs))]);
}

export async function scanDocument(doc: Document): Promise<QaResult> {
  await waitForImages(doc);
  const roots = Array.from(doc.querySelectorAll<SVGSVGElement>("svg[data-marpit-svg]"));
  const slides: SlideReport[] = roots.map((root, index) => {
    const sections = Array.from(root.querySelectorAll<HTMLElement>("foreignObject > section"));
    const section = sections.find((s) => !s.hasAttribute("data-marpit-advanced-background")) ?? sections.at(-1);
    root.classList.remove("qa-overflow", "qa-missing");
    if (!section) {
      return { page: index + 1, title: "", characters: 0, words: 0, scrollOverflowX: 0, scrollOverflowY: 0, offenders: [], missingImages: [], warnings: ["no content section"] };
    }
    const width = section.clientWidth;
    const height = section.clientHeight;
    const rect = section.getBoundingClientRect();
    const scale = rect.width > 0 ? width / rect.width : 1;
    const offenders: Offender[] = [];
    for (const el of Array.from(section.querySelectorAll<HTMLElement>(SELECTOR))) {
      if (el.closest("header,footer")) continue;
      const r = el.getBoundingClientRect();
      if (r.width === 0 && r.height === 0) continue;
      const right = (r.right - rect.left) * scale;
      const bottom = (r.bottom - rect.top) * scale;
      const rightOverflow = Math.max(0, right - width);
      const bottomOverflow = Math.max(0, bottom - height);
      if (rightOverflow > TOLERANCE || bottomOverflow > TOLERANCE) {
        offenders.push({
          tag: el.tagName.toLowerCase(),
          text: (el.textContent ?? "").trim().replace(/\s+/g, " ").slice(0, 140),
          rightOverflow: Math.round(rightOverflow),
          bottomOverflow: Math.round(bottomOverflow),
        });
      }
    }
    const text = (section.innerText || section.textContent || "").replace(/\s+/g, " ").trim();
    const missingImages = Array.from(section.querySelectorAll("img"))
      .filter((img) => img.complete && img.naturalWidth === 0)
      .map((img) => img.getAttribute("src") ?? "?");
    // The background images of advanced backgrounds live in a sibling section.
    for (const bg of sections.filter((s) => s !== section)) {
      for (const img of Array.from(bg.querySelectorAll("img"))) {
        if (img.complete && img.naturalWidth === 0) missingImages.push(img.getAttribute("src") ?? "?");
      }
      // Marp renders `![bg]` as figure with background-image; a 404 there is silent. Probe it.
      for (const fig of Array.from(bg.querySelectorAll<HTMLElement>("figure[style*='background-image']"))) {
        const url = fig.style.backgroundImage.match(/url\(["']?([^"')]+)/)?.[1];
        if (url) missingImages.push(`bg:${url}`);
      }
    }
    const warnings: string[] = [];
    if (section.querySelector("style")) warnings.push("scoped style present");
    const report: SlideReport = {
      page: index + 1,
      title: section.querySelector("h1,h2")?.textContent?.trim() ?? "",
      characters: text.length,
      words: text ? text.split(/\s+/).length : 0,
      scrollOverflowX: Math.max(0, section.scrollWidth - width),
      scrollOverflowY: Math.max(0, section.scrollHeight - height),
      offenders: offenders.slice(0, 10),
      missingImages: [],
      warnings,
    };
    // bg probes are resolved async below; keep the raw list for now
    (report as SlideReport & { _missing: string[] })._missing = missingImages;
    return report;
  });

  // Resolve background image probes with HEAD requests (same origin, cheap).
  await Promise.all(
    slides.map(async (s) => {
      const raw = (s as SlideReport & { _missing?: string[] })._missing ?? [];
      const out: string[] = [];
      for (const m of raw) {
        if (!m.startsWith("bg:")) {
          out.push(m);
          continue;
        }
        const url = m.slice(3);
        try {
          const r = await fetch(url, { method: "HEAD" });
          if (!r.ok) out.push(url);
        } catch {
          out.push(url);
        }
      }
      s.missingImages = out;
      delete (s as SlideReport & { _missing?: string[] })._missing;
    }),
  );

  const overflowPages: number[] = [];
  const missingImagePages: number[] = [];
  slides.forEach((s, i) => {
    const bad = s.offenders.length > 0 || s.scrollOverflowY > TOLERANCE || s.scrollOverflowX > TOLERANCE;
    if (bad) {
      overflowPages.push(s.page);
      roots[i]?.classList.add("qa-overflow");
    }
    if (s.missingImages.length) {
      missingImagePages.push(s.page);
      roots[i]?.classList.add("qa-missing");
    }
  });
  return { slides, overflowPages, missingImagePages };
}
