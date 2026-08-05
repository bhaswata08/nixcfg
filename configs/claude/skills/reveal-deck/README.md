# reveal-deck

A skill for building reveal.js presentations that hold real numbers and can be
checked before anybody sees them.

```
SKILL.md                the map: seven non-negotiables, five phases, known traps
references/
  scaffold.md           directory layout, vendoring, the two build modes
  archetypes.md         the layout catalogue and when each one applies
  figures.md            extracting diagrams from source PDFs and PPTX
  verify.md             the headless screenshot loop
  density.md            what goes on a slide and what gets said out loud
  anti-slop.md          the pre-delivery gate
  prose.md              word-level bans, adapted from stop-slop
assets/
  index.html            reveal bootstrap, editing mode
  build.mjs             compiles to one self-contained deck.html
  serve.mjs             local static server
  custom.css            the theme and every archetype
  sections/00-open.html a starter act: title, promise, roadmap
scripts/
  shoot.sh              screenshot a slide range, headless
```

## Where it came from

Written from a ninety-slide technical seminar deck, plus three existing slide
skills.

- [stop-slop](https://github.com/hardikpandya/stop-slop) (MIT) supplies the
  word-level bans in `references/prose.md`.
- [frontend-slides](https://github.com/zarazhangrui/frontend-slides) (MIT)
  supplies the fixed-stage principle, the two density modes, and the phase
  structure.
- [skills-slides](https://github.com/nghiahsgs/skills-slides) supplies most of
  the quality gate in `references/anti-slop.md`.

What none of them had, and what this skill is mostly about: extract figures
from the source instead of rebuilding them, verify by screenshot because layout
fails silently, cut explanation rather than numbers, and build one act at a
time.

Four checks from those projects are deliberately reversed. `anti-slop.md` says
which and why.
