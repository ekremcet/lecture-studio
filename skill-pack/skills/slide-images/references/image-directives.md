# Marp image directives used in these decks

Counts are from the existing decks; use the common forms.

| Directive | Uses | When |
|---|---|---|
| `![bg right contain](assets/x.png)` | 431 | Default: image on the right half, text on the left. Image keeps its aspect ratio |
| `![bg right:40% contain](assets/x.png)` | 51 | Text needs more room; image takes 40% |
| `![bg right:30% contain](assets/x.png)` | 7 | Small visual next to a dense slide |
| `![bg right 80%](assets/x.png)` / `70%` / `90%` | 58 / 15 / 31 | Same as contain but scaled to that fraction of its area; use for memes with white borders |
| `![bg contain](assets/x.png)` | 5 | Full-bleed figure slide; pair with empty `_header`, `_footer`, `_paginate: false` |
| `![width:1000px](assets/x.png)` | 82 | Inline figure on its own slide under the title; 1000 px fits the 1280 px slide with padding |
| `![width:600px](assets/x.png)` | 9 | Inline figure inside a column |

Rules:
- Paths are relative to the deck file: `assets/name.ext`. Both `assets/` and `./assets/` render; use `assets/` for new slides.
- A `bg` image must be the first element after the title (or before it); Marp strips it from the flow.
- One `bg` per slide. Two `bg` images split the background; do not use that.
- Inline images larger than 1000 px wide overflow. Inline images taller than about 480 px overflow when there is a title.
- Alt text is not shown; keep the directive keywords exact.
