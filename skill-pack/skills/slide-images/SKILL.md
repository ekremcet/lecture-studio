---
name: slide-images
description: Find or make an image for a slide - a meme, a screenshot, a chart, or a diagram (Graphviz, matplotlib) - and place it in the week's assets folder with the right Marp image directive. Use when a slide needs a visual, when the user asks for a meme, figure, diagram, chart, or picture, or when deck QA reports a missing image.
---

# Slide images

Images live in the lecture repo at `courseFolder/weekN/assets/`. They get there ONLY through the client tool `save_asset(week_dir, filename, source)`, or through a sandbox `send_file` attachment that the user saves in the app. The sandbox (`write_file`, shell, `web_search`, `browse_url`, `screenshot_url`) is where you search and generate; it is not the repo.

## Decide the kind

| Need | Route |
|---|---|
| Meme or a known picture (a real photo, a book cover, a logo) | `web_search` → pick a direct image URL (`.jpg`, `.png`, `.webp`) → `save_asset(week_dir, "kebab-name.jpg", url)` |
| Screenshot of a web page or a tool | sandbox `screenshot_url` → `send_file`, or `save_asset` with the data URI if under 2 MB |
| Structural diagram (boxes and arrows, trees, state machines, layered architecture) | sandbox: `scripts/graphviz.py` → PNG → `send_file` |
| Chart from numbers (complexity curves, comparison bars, timelines) | sandbox: `scripts/plot.py` → PNG → `send_file` |
| Memory layout, table-like diagram | Prefer a markdown table on the slide; no image |
| UML | Graphviz `record` shapes via `graphviz.py --uml`; or draw.io by the user |

There is no image-generation model on this project. Do not promise generated art. Mermaid is not available in the sandbox (no Chromium); write Graphviz instead.

## Sandbox setup (once per conversation)

```bash
sudo apt-get install -y graphviz >/dev/null 2>&1 || true
python3 -c "import matplotlib" 2>/dev/null || pip install matplotlib
which convert || sudo apt-get install -y imagemagick
```

Copy the scripts from this skill into `/workspace/scripts/` first (they are bundled with the skill; `list_files` shows them).

## Making a diagram

1. Write the DOT or the data as a small file in the sandbox.
2. `python3 scripts/graphviz.py spec.dot out.png` (or `python3 scripts/plot.py spec.json out.png`). Both produce a PNG at most 1600 px wide, white background, fonts and colors from `references/diagram-styles.md`.
3. Look at the result: `screenshot_url` is not needed; the app shows attachments. Check that labels are readable at 50% width on a slide (a 1600 px image shown at 640 px means 12 pt text needs to be 24 pt in the image).
4. `send_file out.png` with a one-line caption. Tell the user the target: `weekN/assets/kebab-name.png`. The app offers "save to assets".
5. Put the directive in the deck (see `references/image-directives.md`), then `qa_deck` to confirm the image resolves.

`scripts/resize.sh in.png out.png 1600` shrinks an oversized image with ImageMagick.

## Finding a meme

1. `web_search` with the concept plus "meme" (for example "waterfall model meme", "AVL rotation meme"). Prefer classic templates the students recognize.
2. `browse_url` the page and take the direct image URL. Avoid images with visible watermarks or under 400 px.
3. `save_asset(week_dir, "topic-meme.jpg", url)`. The tool refuses to overwrite; pick a new name if it exists.
4. Reference it as `![bg right contain](assets/topic-meme.jpg)` on a slide that has at most 5 bullets. One meme per 20-minute block.
5. Add the source to the slide footer when the image is a figure from a paper, a book, or a company blog: `<!-- _footer: "Source: [Title](url)" -->`. Memes need no footer.

## Naming

`kebab-case`, descriptive, no week number: `stack-push-pop.png`, `waterfall-meme.jpg`, `rup-phases.png`. Extensions lower-case. Never overwrite an existing asset; add `-v2`.

## When QA reports a missing image

1. `list_dir` the week's `assets/` and look for a near match (case, extension, `./assets` prefix).
2. Fix the path with `replace_in_file` when a match exists.
3. Otherwise make or find the image with the routes above.
