# What goes on the slide

## Pick a mode first

Ask before slide one. It changes everything downstream.

**Speaker-led.** The slide is the visual aid, the speaker is the content. One
idea per slide, one sentence of text, large type. The deck is close to useless
without the talk, and that is correct. This is the default, and it is what the
rest of this file assumes.

**Reading-first.** The deck is circulated and read alone. Slides are more
self-contained: structured tables, four to eight lines, a heading that states
the conclusion rather than the topic. Still not paragraphs.

Never blend them. A deck that is half each is a deck that is bad at both.

## The shape of a slide

```
ribbon        you are here
heading       the claim, not the topic
graphic       figure, bars, chips, flow, table, cards
one sentence  what the graphic means
source line   where it came from
```

That is the whole vocabulary. If a slide does not fit it, it is two slides.

**Headings state the claim.** "Where the 56 days went" beats "Timeline". The
heading is read first and remembered longest, so spend it on the point rather
than on the category.

**One sentence, not two.** A second sentence means the slide is doing two
things. The archetype for that sentence is deliberately capped in width so it
cannot quietly become a paragraph.

## Cut explanation, never numbers

This is the rule that does the most work.

When a slide is too full, everyone's instinct is to drop the specific thing,
because "43% MFU" looks like detail and "systems work matters" looks like the
point. It is backwards. The number is the reason anyone is in the room. The
sentence explaining what MFU stands for is what the speaker is for.

**Cut:** definitions of terms the audience knows, restatements of the heading,
justification for why a stage exists when the diagram already shows it, "as we
can see", any sentence that survives being deleted.

**Keep:** every measured value, every specific mechanism, the units, the scale,
the source.

Assume the presenter is competent, and that the audience can read a bar chart
without being told it is a bar chart.

## Density ceilings

Per slide, speaker-led. These are ceilings, not targets.

| Slide type | Ceiling |
| --- | --- |
| Act opener | Number, title, one line of promise, the time budget |
| Figure | One figure, one sentence, one source line |
| Cards | 3 cards of a title plus one line. 4 only if each is a title plus a short line |
| Bars | 6 bars. Past that it is a table |
| Table | 5 rows, 4 columns. Past that, screenshot it before you trust it |
| Chips | One row. Two only if the split is deliberate |
| Stats | 4 big numbers. Each needs a label under it |
| Recap | 3 lines, then the one-line handoff to the next act |

## Empty space is fine

Do not scale a heading up to fill a slide that has three items on it. The
instinct that empty slides look unfinished is right about a poster and wrong
about a talk. Consistent type across the deck is worth more than any single
slide being full, and a slide with one number and one line is often the best
slide in the deck.

What is not fine is content jammed against the top with a dead band underneath.
That is a broken layout, not white space, and `references/verify.md` covers it.

## Repetition is sometimes deliberate

An early act may name a structure that a later act explains. That is a
signpost, and it works.

Record it in both files:

```html
<!-- Act 3 slide 3.0b already names the three stages as a scope signpost.
     This act is where they are explained, so 7.1 repeating the flow is
     deliberate, not a duplicate. -->
```

Without that comment, a later pass deletes one of them and the argument breaks
in a way that is very hard to see afterwards.

## Signpost when the scope narrows

If two acts silently cover only one stage of a pipeline, the audience will
generalise the numbers to the whole thing. One slide fixes it: show the whole
pipeline, highlight the box these acts are about, say so in one sentence, and
name the stages you are not covering yet.

This is cheap and it is the single most common gap in a technical deck.
