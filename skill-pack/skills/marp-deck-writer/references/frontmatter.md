# Front matter per course family

Copy the block for the family exactly. Change only `header`, `footer`, and add `math: mathjax` where the table says so. The style block is the house theme; do not edit it inside a deck.

## Header and footer strings by course

| Course | `header` | `footer` pattern | `math` |
|---|---|---|---|
| CS102 Advanced Programming | `"CS102 - Advanced Programming"` | `"Week N: Topic Title"` | yes (`math: mathjax`) |
| CS211 Intro to Machine Learning | `"CS211 - Introduction to Machine Learning"` | `"Week N: Topic Title"` | yes |
| CS221 Software Engineering (fall26 and older) | `"CS221 - Software Engineering Principles"` | `"**Week N**: Topic Title"` (bold week) | only when a slide uses math |
| CS231 Data Structures and Algorithms | `"CS231 - Data Structures and Algorithms"` | `"Week N: Topic Title"` | no |
| CS415 Human-Centered AI workshop (Turkish) | `"CS415 - İnsan Merkezli Yapay Zeka Çalıştayı"` | `"**N. Çalıştay**: Başlık"` | when needed |
| Talks (seminar, startup) | short talk title, e.g. `"AI in Science"` | `"AI in Science - December 2025"` | yes |

Put `math: mathjax` on its own line right after `marp: true` when used.

## Lecture family (all lecture courses)

```yaml
---
marp: true
paginate: true
size: 16:9
header: "CS231 - Data Structures and Algorithms"
footer: "Week 3: Stack and Queue"
style: |
  section {
    font-size: 20px;
    padding: 32px;
    justify-content: flex-start;
    text-align: left;
  }
  section h1 {
    font-size: 36px;
    margin-bottom: 20px;
    margin-top: 0;
    text-align: left;
  }
  section h2 {
    font-size: 30px;
    margin-bottom: 15px;
    margin-top: 20px;
    text-align: left;
  }
  section h3 {
    font-size: 24px;
    margin-bottom: 10px;
    text-align: left;
  }
  section ul, section ol {
    margin: 10px 0;
    text-align: left;
  }
  section li {
    margin: 8px 0;
    line-height: 1.3;
    text-align: left;
  }
  section blockquote {
    margin: 15px 0;
    text-align: left;
  }
  section pre {
    text-align: left;
  }
  section small {
    font-size: 12px;
    font-style: italic;
  }
  section p {
    text-align: left;
  }
  .two-columns {
    display: flex;
    gap: 24px;
  }
  .column {
    flex: 1;
  }
  .columns-3 {
    display: grid;
    grid-template-columns: repeat(3, minmax(0, 1fr));
    gap: 1rem;
  }
  .highlight {
    background-color: #acd8fa;
    padding: 2px 8px;
    border-radius: 4px;
    display: inline-block;
    font-weight: bold;
    color: #eb3434;
  }
  section.divider h1 {
    text-align: center;
    font-size: 72px;
  }
  section.divider p {
    text-align: center;
  }
  section.callout-blue { background: #eef5fb; }
  section.callout-green { background: #edf7ee; }
  section.callout-yellow { background: #fff8e5; }
  section.callout-red { background: #fbeeee; }
---
```

Notes:
- CS221 fall26 decks omit `justify-content: flex-start`; keep it for new decks, it prevents vertical centering surprises.
- `.columns-3`, `.highlight`, `section.divider`, and `section.callout-*` are additions to the historical block. Existing decks may lack them; do not rely on them when editing an older deck unless you also add the CSS.

## Talk family (seminar, startup pitch, keynote)

```yaml
---
marp: true
math: mathjax
theme: default
paginate: true
size: 16:9
header: "AI in Science"
footer: "AI in Science - December 2025"
style: |
  section {
    font-size: 22px;
    padding: 32px;
    text-align: left;
  }
  section h1 {
    font-size: 42px;
    margin-bottom: 20px;
    color: #0066cc;
  }
  section h2 {
    font-size: 32px;
    margin-bottom: 15px;
    color: #333;
  }
  section h3 {
    font-size: 26px;
    margin-bottom: 10px;
    color: #555;
  }
  .columns {
    display: flex;
    gap: 12px;
  }
  .column {
    flex: 1;
  }
  .highlight-box {
    background: #fff3cd;
    border-left: 5px solid #ffc107;
    padding: 15px;
    margin: 10px 0;
    border-radius: 4px;
  }
  .red-box {
    background: #f8d7da;
    border-left: 5px solid #dc3545;
    padding: 12px;
    margin-bottom: 12px;
  }
  .green-box {
    background: #d4edda;
    border-left: 5px solid #28a745;
    padding: 12px;
    margin-bottom: 12px;
  }
  .timer {
    position: absolute;
    top: 20px;
    right: 40px;
    background: #ff6b6b;
    color: white;
    padding: 8px 16px;
    border-radius: 20px;
    font-weight: bold;
  }
  .source {
    position: absolute;
    bottom: 50px;
    left: 30px;
    font-size: 12px;
    color: #666;
    font-style: italic;
  }
  .source a {
    color: #0066cc;
    text-decoration: none;
  }
---
```

In talks the column class is `.columns` (not `.two-columns`) and sources go in `<div class="source">` or the footer.
