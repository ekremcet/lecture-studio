---
name: instructor-guide
description: Write or update the weekN-instructor-guide.md that pairs with a lecture deck - six 20-minute blocks, student outputs, facilitation notes, minimum viable path, extension. Use when the user asks for a session plan, teaching guide, lesson plan, pacing, timing, activities, "how do I run this week", or an instructor guide.
---

# Instructor guide writer

The guide is a one-page Markdown file next to the deck: `courseFolder/weekN/weekN-instructor-guide.md`. It turns a three-hour meeting into six 20-minute teaching blocks. Read and write it ONLY with the client tools (`read_file`, `create_file`, `replace_in_file`); the sandbox is not the repo.

## Procedure

1. **Read the deck.** `read_file` the deck in ranges (it is 800-2600 lines). Note every `# ` title with its slide number, and every `# Practice`, `# Question`, `# ... Studio`, and divider slide.
2. **Read the course context.** The course `studio.json`, `AGENTS.md` (or an older `CLAUDE.md`), and syllabus (deliverable schedule, lab weeks), and `studio.json` at the repo root for the presenter's style. The course-level `INSTRUCTOR_SESSION_GUIDE.md` when it exists. `list_sources` and `rag_search` when the guide should point at readings.
3. **Map slides to blocks.** Six blocks, each 20 minutes, each with a core path (which concepts) and one student output (a thing they produce before you show the sample answer). Blocks 1-5 are concept or practice blocks; block 6 is a studio block tied to the current deliverable or lab when the course has one.
4. **Write the file** with `create_file`, using `references/template.md` exactly (same headings, same table columns). Keep it under 40 lines.
5. **Link it.** When the course has `INSTRUCTOR_SESSION_GUIDE.md`, add or fix the week's line in its "Weekly Guides" list with `replace_in_file`.
6. **Report** the six blocks in one line each.

## Rules

- Every block names a student output. "Listen to the lecture" is not an output.
- Block 6 output must be usable in the next deliverable (D1-D5) or lab. Say which.
- The minimum viable path is an arrow chain of 4-5 items for a class that runs late: what to keep when practice time runs out. Always keep at least one practice and its debrief.
- The extension is one task for a class that runs early: make students defend, review, test, or revise an artifact. Never new theory that will not be assessed.
- Facilitation notes: 3 bullets. One about framing (constraints, no universal best), one about a required artifact rule (for example "require one rejected alternative and its failure mode"), one linking to the project or lab.
- Sample answers are revealed only in the debrief. If the deck shows the answer on the slide after the practice, say "reveal slide N only after the debrief".
- Block timing inside a block follows `references/block-types.md`.
- Match the deck's language.
- Use the course's unit word (week, session, module) in the file name and the headings: `weekN-instructor-guide.md` next to `weekN-slides.md`, `sessionN-instructor-guide.md` next to `sessionN-slides.md`.

`references/example-week3.md` is a real guide to copy the tone from.
