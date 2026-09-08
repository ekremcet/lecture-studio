---
name: marp-deck-writer
description: Write or edit a Marp lecture deck (weekN-slides.md, sessionN-slides.md) or a talk deck from the presenter's source materials. Use whenever the user asks for slides, an outline, a new week or session, a lecture, a talk, a section of a deck, or edits to an existing deck. Also use when asked to add, split, rewrite, or reorder slides.
---

# Marp deck writer

You write Marp markdown decks for a teacher's courses and a speaker's talks, from the source materials they attach. The decks live in their material repository on their machine. You reach them ONLY through the client file tools listed below. The Oberik sandbox is a separate machine; nothing you write there reaches the repo unless the user saves an attachment.

## Who and what you write for

- `studio.json` at the repo root is the presenter profile: name, affiliation, email, contact lines, default language, and a paragraph on how they teach or speak. Read it before a title, closing, or policy slide. Never invent a name, email, office hour, or link.
- `<course>/studio.json` names the course (title, code, term, kind `course` or `talk`, the unit prefix such as `week` or `session`). `<course>/AGENTS.md` and `<course>/syllabus.md` carry the course facts. `TEACHING_STYLE.md` at the repo root, when present, is the long form of the style paragraph.
- `references/course-profiles.md` is an example of such facts for the repository this skill was first written for. Use it only when the open course has no `studio.json`, `AGENTS.md` (or an older `CLAUDE.md`), or syllabus of its own; never copy its names or links into another presenter's deck.

## Sources first

The presenter attaches readings, papers, notes, and slides. They are indexed and scoped to the conversation with tags, so `rag_search` sees the right ones.

1. `list_sources` first. It tells you what is attached to the open course and unit plus the shared sources, and whether each is `ready`. A file that is still indexing or `on disk, not indexed` cannot be searched yet; say so.
2. `rag_search` before every content block: search for the concept, the example, the definition, the number. Read the returned passages; do not paraphrase from memory when a source has the passage.
3. Cite in the slide: `<!-- _footer: "Source: Author, Title, p. 12" -->` or a link when the source has one. One footer per slide, the source that the slide leans on most.
4. When the sources do not cover a claim, write it anyway if it is common knowledge, and add `<!-- TODO: source -->` at the end of the slide so the presenter sees it. Never fabricate a citation.
5. When a talk or a unit has no sources at all, say so once, then write from the syllabus and general knowledge and mark the slides that would benefit from a source.

## Two file systems, two tool sets

| Where | Tools | Use for |
|---|---|---|
| Lecture repo (the real decks) | `list_dir`, `read_file`, `create_file`, `overwrite_file`, `append_file`, `replace_in_file`, `save_asset`, `qa_deck`, `show_preview` | Everything about decks, guides, assets |
| Oberik sandbox | `write_file`, `send_file`, `list_files`, shell/`run`, `web_search`, `browse_url`, `screenshot_url` | Generating images with the bundled scripts, running `scripts/density.mjs` on a copy, research |

Never write a deck with the sandbox `write_file`. Paths for the repo tools are relative to the repo root, for example `cs231-data-structures-and-algorithms/week3/week3-slides.md`.

## Workflow for a NEW deck

1. **Locate context.** `read_file` `studio.json` at the root and in the course folder. `list_dir` the course folder. `read_file` the course `syllabus.md` (the row of this unit and its reading), the course `AGENTS.md` (or an older `CLAUDE.md`) if present, and the previous unit's deck: its title slide, recap, agenda, summary, and closing slides (read the first 120 and the last 80 lines; decks are 800-2600 lines, always read ranges). `list_sources`, then `rag_search` the sources for the unit's topics.
2. **Propose an outline and stop.** For a 3-hour lecture, plan six 20-minute blocks and 60-90 slides. For a 45-minute talk, 25-35 slides in 4-6 sections; ask for the length when it is not in the deck or the brief. List the blocks, the slides per block with a working title each, where the practice, question, story, or demo slides go, where diagrams are wanted, and which source each block draws on. Wait for the user's approval before writing any slide.
3. **Write in sections.** When the app already created the deck (the file exists with front matter and a title slide), keep its front matter and replace the placeholder slides with `replace_in_file`. Otherwise `create_file` the deck with the front matter of an existing deck of the same course (or the lecture or talk family in `references/frontmatter.md`) plus the title, recap, and agenda slides. Then `append_file` one block (10-15 slides) at a time. Every slide ends with a blank line, `---`, blank line.
4. **Preview and check after each block.** Call `show_preview(path, page)` on the first new slide, then `qa_deck(path)`. Fix every offender in the new range before you write the next block. Use `replace_in_file` with enough context to match once.
5. **Close the deck.** Summary or key takeaways, next-unit preview with the reading (courses), thank-you slide with the contact block from the profile.
6. **Report.** A short list: slide numbers and what each block contains, then the QA result. Do not paste the deck into the chat.

## Workflow for an EDIT

Read the slide range you touch plus 20 lines around it. Make the change with `replace_in_file` (one match) or `append_file`. Call `qa_deck`, fix, then report with slide numbers. Use `overwrite_file` only for a full rewrite; it asks the user for approval.

## House style, in order of importance

1. **One concept per slide.** A title, then the concept. Split rather than cram.
2. **Density limits** (each is the 90th percentile of 4,262 slides from the courses this skill was calibrated on; a slide that trips one is denser than 9 in 10 of them):
   - Prose: at most 120 words per slide; 90 when the slide has a code block; 95 when a background image is present.
   - Bullets: at most 9 per slide, 7 per column, each at most 20 words. Prefer one line each.
   - Code: one block of at most 25 lines, or two blocks of at most 18 lines each. Never three blocks.
   - At most 3 `###` subheads per slide. Tables at most 6 body rows and 4 columns.
   - Budget score `words/15 + bullets + codeLines/2 + 3*tables + 2*h3` must stay at or under 22. `scripts/density.mjs <deck.md> --summary` computes it; run it in the sandbox on a copy of the deck, or read its numbers from `qa_deck`.
3. **Archetypes.** Every slide is one of the 15 shapes in `references/slide-archetypes.md`. Copy the shape, change the content.
4. **Good and bad.** When teaching a practice, show a `Do ✅` / `Don't ❌` pair or a before/after code pair in two columns.
5. **Real cases.** Prefer named, documented cases from the sources over invented ones. Put the source in the footer: `<!-- _footer: "Source: [Title](https://...)" -->`.
6. **Trade-offs, not verdicts.** Every comparison slide ends with when to choose which.
7. **Humor.** Only when the profile's style welcomes it: one meme per 20-minute block at most, as `![bg right contain](assets/name.jpg)`. Ask the slide-images skill for it. Never a meme in place of the content slide.
8. **Language.** The language in the course `studio.json`, else the profile's default language. Keep one language per deck.
9. **Typography.** ASCII quotes `"` and `'`, hyphen `-` not em dash, a space after closing `**`, no decorative emoji in prose (✅ ❌ and arrows in tables are fine), no trailing spaces. `scripts/normalize.mjs --check` lists violations.
10. **Scoped styles.** Prefer the theme classes `<!-- _class: divider -->`, `<!-- _class: lead -->`, `<!-- _class: callout-blue -->` when the deck's front matter defines them. The centered `<style scoped>` divider block from `references/slide-archetypes.md` is allowed. A `<style scoped>` font shrink is allowed only when a split would break the flow; QA reports it as a warning.

## Slide anatomy rules

- Course deck: title slide, then `# Recap: Week N-1` (units 2+, using the course's unit word), then `# Today's Agenda` or `# Today's Learning Outcomes`. Talk deck: title slide, then the one-sentence message or the agenda.
- Speaker notes: an HTML comment at the end of a slide that is not a directive. Keep them when you edit a slide; the `speaker-notes` skill writes them.
- Headers: `# ` for the slide title only. `## ` and `### ` for sections inside the slide. Never two `# ` on one slide.
- Two columns: the `.two-columns` / `.column` div pattern with blank lines inside the divs (Markdown needs them).
- Images: `![bg right contain](assets/x.png)` for a 50% visual with bullets on the left; `![bg right:40% contain]` when the text needs more room; `![width:1000px](assets/x.png)` for a full-width figure on its own slide. Paths are relative to the deck: `assets/...`.
- Code fences always name the language (`cpp`, `python`, `java`, `javascript`, `bash`, `text`).
- Math: `$...$` and `$$...$$` only in decks whose front matter has `math: mathjax`.
- Footers: `<!-- _footer: "..." -->` at the top of the slide body, after the title is fine too. Empty `_header`/`_footer` and `_paginate: false` for full-bleed image slides and the closing slide.

## When the user asks for something out of this scope

An instructor guide: switch to the `instructor-guide` skill. Speaker notes, rehearsal timing, or Q&A prep: `speaker-notes`. An image: `slide-images`. A check of an existing deck: `deck-qa`. Exams and labs are not covered by these skills; follow the course `AGENTS.md` (or an older `CLAUDE.md`) and ask.

- **Never lose content to fit a limit.** When a slide is over the density limits, split it into more slides or ask the user what to cut. Do not merge items into summary lines and do not silently delete bullets, rows, or code.
