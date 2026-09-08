---
name: deck-qa
description: Check a Marp deck for overflow, missing images, density, typography, and structure, and fix what it finds. Use after writing or editing slides, before an export, or when the user says QA, check, review, lint, overflow, "does it fit", or "clean up the deck".
---

# Deck QA

You check and repair decks in the lecture repository. The deck is on the user's machine; read and change it ONLY with the client tools `read_file`, `replace_in_file`, `append_file`, `overwrite_file`, `save_asset`, `qa_deck`, `show_preview`. The Oberik sandbox (`write_file`, `send_file`, shell) is a scratch machine: use it to run the bundled scripts on a COPY of the deck text, never as the place where the deck lives.

## Procedure

1. **Render check.** Call `qa_deck(path)`. It renders the deck in the app's preview and returns one entry per slide: `page`, `title`, `words`, `offenders` (elements that cross the slide boundary, with `rightOverflow` and `bottomOverflow` in px), `missingImages` (broken `src`), and `warnings` (for example a `<style scoped>` font shrink).
2. **Density check.** Copy the deck text into the sandbox (`read_file` the whole deck in ranges, sandbox `write_file` it as `deck.md`) and run `node scripts/density.mjs deck.md --summary`. Or skip this when `qa_deck` already reports zero offenders and the user asked only about rendering.
3. **Typography check.** Run `node scripts/normalize.mjs --check deck.md` in the sandbox. It lists lines with em/en dashes, smart quotes, decorative emoji, missing space after closing `**`, trailing spaces.
4. **Structure check** by reading the first 120 and last 100 lines of the deck:
   - Title slide present with course code, week, topic, instructor, date.
   - Recap slide (weeks 2+), agenda or learning outcomes.
   - Header and footer strings match the course profile and the week number.
   - Summary or key takeaways, next-week preview, thank-you slide with the contact block.
   - Every `_footer` that names a source has a link.
   - A `# Question` slide is followed by an `# Answer` slide; a `# Practice` slide does not contain its own sample answer.
5. **Fix**, in this order: overflow and missing images (they break the lecture), then over-budget slides, then typography, then structure. Use `replace_in_file` with enough context to match once. For a split, replace the whole slide body with two slide bodies.
6. **Re-run `qa_deck`** on the touched range. Repeat until `offenders` and `missingImages` are empty.
7. **Report.** A table: page, problem, fix applied. Then the remaining warnings the user should decide on (for example a scoped shrink you kept).

## Content is never lost

A fix changes layout, not meaning. When a slide overflows, split it into as many slides as it takes ("Title" and "Title, Continued"), move a code block to its own slide, or shorten wording sentence by sentence. Never delete bullets, rows, or code lines, and never merge several items into a summary line to fit a count. If the only way to fit is to cut content, stop and ask the user which items to cut.

## Triage table

| Finding | Fix |
|---|---|
| `bottomOverflow` on a two-column slide | Split into two slides with the same title plus ", Continued", one column each becomes full width, or move the second `###` group to the new slide |
| `bottomOverflow` with one long code block | Keep the signature and the interesting lines; move the rest to a "..., Continued" slide; or cut comments |
| `bottomOverflow` with a table | Drop rows to 6, or split the table across two slides by rows |
| `rightOverflow` on `pre` | Wrap long code lines at 80 columns; shorten comments |
| `rightOverflow` on a table | Shorten cell text; remove a column; never shrink below 16px |
| Missing image | `list_dir` the week's `assets/`, fix the path (case, extension, `./assets` vs `assets`), or ask `slide-images` to produce it |
| Words over limit | Cut adjectives and the second sentence of each bullet; move an example to its own slide |
| Bullets over limit | Group into two `###` lists on two slides, or turn 3 bullets into one sentence |
| Three code blocks | One block per slide, or fold two tiny blocks into a table |
| `<style scoped>` font shrink (warning) | Try the split first. Keep the shrink only when the slide is a single logical unit (a full class listing, a UML notation table). Never below 16px, never on a slide with a bg image |
| Em dash, smart quotes | Run `normalize.mjs` on the copy, then apply the changed lines with `replace_in_file`, or apply the rules by hand for a few lines |

`references/fix-patterns.md` has before/after examples for the common splits.

## Rules you do not relax

- No slide keeps an offender after QA. "It is only 3 px" still cuts the last bullet in the PDF.
- Do not shrink to fit when the content is two ideas. Split.
- Do not delete content to pass the check without telling the user which sentence went away.
- Do not touch a course folder whose `studio.json` has `"archived": true`, or whose `AGENTS.md` (or an older `CLAUDE.md`) marks it as archived or read-only.
