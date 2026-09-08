---
name: speaker-notes
description: Write or revise speaker notes for a Marp deck, estimate rehearsal timing, and prepare audience Q&A. Use when the user asks for speaker notes, presenter notes, what to say, a script, talking points, timing, "does this fit in 20 minutes", cuts for a shorter version, or likely audience questions.
---

# Speaker notes

Marp keeps presenter notes as HTML comments inside a slide: any `<!-- ... -->` that is not a directive (`<!-- _class: lead -->`, `<!-- _footer: ... -->`) is shown in presenter view and under the preview in the studio. You write them into the deck with the client tools (`read_file`, `replace_in_file`); the sandbox is not the repo.

## Notes for a deck

1. **Read the deck in ranges** and note every `# ` title with its slide number. Read `studio.json` at the repo root for the presenter's voice: the style paragraph decides whether the notes are a script or bullet-form prompts.
2. **Ask once** when the deck does not say it: how long the slot is, and whether the notes should be a full script or prompts. Default: prompts, 2-4 sentences per slide.
3. **Search the sources** (`list_sources`, `rag_search`) for the slides that make a claim, so a note can carry the number, the quote, or the page to point at.
4. **Write one slide at a time** with `replace_in_file`: match the last lines of the slide and append the comment before the `---`. The shape:

```markdown
<!--
Say: The point of this slide in one sentence, in the presenter's voice.
Then: the example or the number to give, with the source (Author, p. 12).
Ask: one question to the room, or the thing to let them try.
Next: the transition to the next slide.
~1.5 min
-->
```

   Keep the four labels; drop `Ask` on slides where nothing is asked. Title, divider, and closing slides get one line each.
5. **Do not change the slide content.** If a slide needs a change to be sayable, list it in the report instead.
6. **Report** the slide numbers you covered and the total estimated time.

## Rehearsal timing

Estimate per slide: about 120 words spoken a minute for prose in the notes (or 100 words of slide text when there are no notes), plus one minute for a diagram or a table the presenter walks through, plus the timebox of a practice slide as written on it. Sum per block or section. List the slides that run over their share and, when the user asks for a shorter version, name the slides to cut or merge; prefer dropping a whole section to shaving every slide. Do not edit the deck for a timing request.

## Audience Q&A prep

From the deck and the sources, write the 8-10 questions the audience is most likely to ask: the objection to the main claim, the "how does this compare to X" question, the "what about my case" question, the definition someone missed, the number someone doubts. Two-sentence answers each, with the slide to go back to and the source to cite. Save it as `qa-prep.md` next to the deck with `create_file` (ask before overwriting an existing one).

## Style

- Second person, present tense, the presenter's own voice from the profile. Short sentences.
- No stage directions about slides that are self-explanatory. Notes are for what is not on the slide.
- Plain ASCII quotes and hyphens.
- Match the language of the deck.
