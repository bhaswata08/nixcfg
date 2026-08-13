# The gate

Run this before delivery. It is short on purpose. A checklist nobody finishes is
worse than no checklist.

Parts of this are adapted from the anti-slop checklists in the `skills-slides`
and `frontend-slides` projects. Where this file disagrees with them, it is
because a technical deck on a fixed stage has different failure modes than a
marketing page.

## Content, which is what actually fails

- [ ] **Every measured number that was in the draft is still in the deck.**
      The single most common real regression. Restyling eats numbers. Diff
      against the source if you are unsure.
- [ ] **No slide is prose.** One sentence under the graphic. If any slide has a
      paragraph, it is two slides.
- [ ] **Every quoted number has a source line**, with a table, figure or section
      number.
- [ ] **Every derived number says it is derived.**
- [ ] **No claim the source does not support.** Quantifiers are where this goes
      wrong: "a few hundred restarts" when the source says only that there were
      restarts. Say what is known.
- [ ] **Every heading states a claim, not a topic.**
- [ ] **Every act ends by handing off to the next one.**
- [ ] **Deliberate repetition is documented** in a header comment in both files.

## Visual

- [ ] **Every slide has been screenshotted.** See `references/verify.md`. Not
      negotiable and not inferable from the markup.
- [ ] **Colour means one thing.** Three roles. No measured colour on an
      unmeasured value, no broken colour on something that worked.
- [ ] **All colours are CSS variables.** No raw hex in a rule. Drift between
      `#4f46e5` and `#5046e6` in two places is how a deck starts looking cheap.
- [ ] **Three distinct text sizes with a clear order**, on every content slide.
      Heading, body, label.
- [ ] **Text passes WCAG AA, 4.5:1.** Saturated accents usually fail against a
      dark background. Use a lighter tint for text and keep the saturated value
      for borders and fills. Projectors are worse than your monitor, so treat AA
      as the floor.
- [ ] **Shadows have a hierarchy** if the theme uses them at all. One shadow
      value on every element flattens the design.
- [ ] **Layouts come from the archetype catalogue.** A one-off layout needs a
      reason.
- [ ] **`prefers-reduced-motion` is respected.** The shipped theme uses fade
      transitions only, which is already close to the floor, but if you added
      motion, gate it.

## Build

- [ ] **`node build.mjs` ran after the last edit to any section.**
- [ ] **The built file has zero external references.**
      `grep -oE '(src|href)="[^"]*"' deck.html | grep -v '="data:' | sort -u`
- [ ] **Fonts are inlined**, latin subset only. Other subsets triple the file for
      glyphs no slide contains.
- [ ] **No dependency that earns its size.** A syntax highlighter with no code
      blocks, or a maths typesetter for one equation, comes out.
- [ ] **The built file was screenshotted over `file://`**, not just the served
      version.
- [ ] **No `<aside class="notes">`** unless the notes plugin is loaded.

## Deliberately not on this list

The three source checklists demand these. On a fixed-stage technical deck they
are wrong.

- **"Never use Inter or system fonts for display."** Sound advice for a landing
  page. Here the display face has to hold dense headings at small sizes on a
  projector, and a distinctive display face makes slides stop fitting. Vendor a
  clean sans and spend the design budget on the figures.
- **"All font sizes must use `clamp()`."** Directly wrong here. Reveal scales the
  whole 1280x720 canvas to the viewport, so viewport-relative sizes scale twice
  and break unpredictably. Use `em` against the stage.
- **"Every deck needs a signature visual effect."** A particle field on a slide
  about memory bandwidth is a lie about where the effort went. The signature
  effect of a technical deck is that the numbers are right and the figures came
  from the paper.
- **"Never leave more than 30% of the viewport empty, scale text up to fill."**
  Filling a sparse slide by growing the type desynchronises it from every other
  slide. Empty space is fine. See `references/density.md`.
