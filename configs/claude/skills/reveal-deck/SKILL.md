---
name: reveal-deck
description: Build a graphic-first reveal.js presentation that survives a projector and a hostile question. Use when asked to make a talk, deck, slides, seminar, lecture or conference presentation, to turn a paper or report or PPTX into slides, or to fix a deck that is too text heavy. Covers scaffold, slide archetypes, extracting figures from source PDFs, headless screenshot verification, and compiling to one self-contained HTML file.
---

# reveal-deck

Build presentations in reveal.js that look deliberate, hold real numbers, and can
be checked before anybody sees them.

The failure this skill exists to prevent is the deck of bullet lists that says
nothing, and its cousin, the deck that looks styled but drops every measured
number to make room for the styling.

## The seven non-negotiables

Everything else in this skill is detail. These are not.

1. **Graphic first.** A picture, then one sentence under it. Never a paragraph.
   Two sentences means it should be two slides.
2. **Cut explanation, never numbers.** When a slide is too full, the thing that
   goes is the sentence explaining what a token is, not "43% MFU". Assume the
   presenter is competent.
3. **Extract figures, never rebuild them.** If the diagram exists in the source
   PDF, lift it out at 220 dpi. Hand-built SVG of somebody else's figure is
   always worse and always slower. See `references/figures.md`.
4. **Verify by screenshot.** Overflow is silent. Nothing throws. If you did not
   look at the rendered slide you do not know it works. See
   `references/verify.md`.
5. **Colour carries meaning, and the same meaning every time.** Three roles, no
   more. Structure, measured, broken.
6. **Cite the source, and mark derived numbers as derived.** A small source line
   under a slide is the difference between surviving a question and not.
7. **Build one act at a time, and stop.** Show the act, take the note, then
   build the next one. A deck emitted in one shot hides its own gaps.

## Load these when you need them

| File | When |
| --- | --- |
| `references/scaffold.md` | Starting a new deck. Directory layout, vendoring, the two build modes |
| `references/archetypes.md` | Writing any slide. The layout catalogue and when each one applies |
| `references/figures.md` | The source has diagrams, charts or tables worth quoting |
| `references/verify.md` | Any slide has been written or changed. Which is always |
| `references/density.md` | Deciding what goes on a slide and what gets said out loud |
| `references/anti-slop.md` | Before delivery. The quality gate |
| `references/prose.md` | Writing any user-visible words at all |
| `assets/` | Copy `custom.css`, `index.html`, `build.mjs`, `serve.mjs` into the new deck |

## Phase 0: work out what this is

Three inputs, three routes.

- **New deck from a topic or a source document.** Go to Phase 1.
- **A PPTX, PDF or existing deck to convert.** Read the content first. It is
  already the answer to most of Phase 1, so pre-fill and confirm rather than
  interrogate. Extract the figures rather than re-typesetting them.
- **An existing reveal deck to fix.** Screenshot it first (`references/verify.md`),
  then say what is wrong before changing anything. Usually the answer is that
  the slides are prose.

## Phase 1: the brief

Ask only what you cannot infer. Six questions, and skip any the user already
answered:

1. How long is the talk, and how hard is that limit?
2. Who is in the room, and what do they already know?
3. What should they be able to do afterwards? Name the outcome. "Map literacy,
   can name every stage and say why it exists" is an outcome. "Understand
   transformers" is not.
4. Is there a source document? A paper, a report, an internal doc. Get the path.
5. Speaker-led or reading-first? See `references/density.md`. This changes every
   slide, so settle it now.
6. Anything that must appear, and anything that must not?

Then write the act plan before writing a slide: a table of act number, title,
minutes, status. Minutes must sum to the budget. Get agreement on the table.
It is much cheaper to move an act in a table than in HTML.

Roughly 6 to 10 slides per 10 minutes for a speaker-led deck. Slides are cheap,
words on them are not.

## Phase 2: the look

One committed theme, not a style roulette. Do not generate fifty variants.

Pick a background family (dark for a seminar room and a projector, light for a
printed handout or a bright room), then fix exactly three semantic colours:

- **Structure**: headings, act numbers, the "you are here" ribbon, emphasis
- **Measured**: every number, result and quoted fact
- **Broken**: failure modes, regressions, what goes wrong without this stage

`assets/custom.css` ships a dark theme with amber, teal and rose already wired
to those three roles. Recolour the tokens if you like. Do not add a fourth role,
and never use the measured colour on something that was not measured.

If the user wants to see options before committing, build the title slide and
one content slide in two directions and screenshot both. Two, not five.

## Phase 3: build, one act at a time

For each act:

1. Write `sections/NN-name.html`.
2. Open it with a header comment that records **what this act owns and what it
   does not**. Adjacent acts overlap on purpose sometimes. Without the note, a
   later editing pass deletes the repetition and breaks the argument.
3. Add the file to `SECTIONS` in both `index.html` and `build.mjs`.
4. Screenshot every slide in the act. Fix what you see.
5. Show the user. Stop. Wait.

Reuse the archetypes. A new layout per slide is how a deck stops looking like
one deck.

## Phase 4: deliver

1. Run the gate in `references/anti-slop.md`.
2. `node build.mjs` to produce the single self-contained file.
3. Confirm zero external references:
   `grep -oE '(src|href)="[^"]*"' deck.html | grep -v '^.*="data:' | sort -u`
4. Screenshot the built file over `file://`, not just the served one. They can
   differ.
5. Report the absolute path, the slide count, and any content decision you made
   on the user's behalf.

For PDF, print the built file with headless chromium. For PPTX, say plainly that
the conversion loses the layout and offer the PDF instead.

## Traps that cost real time

- **Reveal writes `display:block` as an inline style on the active slide.** That
  beats a plain class rule and silently kills every flex layout. Any section
  that is a flex column needs `display: flex !important`.
- **`center: false`, then own the vertical placement yourself.** Reveal's own
  centring fights a full-height flex column and leaves a dead band.
- **`#/N` in the URL renders slide N+1.** Off by one when verifying.
- **A fixed stage means no `clamp()`.** Reveal scales the whole 1280x720 canvas
  to the viewport. Viewport-relative font sizes on top of that scale twice and
  break in a way that only shows on the presenter's laptop.
- **Vendor the fonts.** System fallbacks render heavier than Inter and slides
  that fitted stop fitting.
- **No speaker notes** unless the notes plugin is actually loaded. An
  `<aside class="notes">` in a deck without the plugin is invisible text that
  someone will assume was delivered.
- **Do not ship a dependency you use once.** A maths typesetter for one equation,
  or a syntax highlighter for zero code blocks, is most of the file size for
  none of the value.
