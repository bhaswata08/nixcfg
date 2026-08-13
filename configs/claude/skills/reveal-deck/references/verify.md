# Verify by looking

Slide layout fails silently. There is no exception, no console warning, no
failing test. A chip row that overruns the frame just puts its last chip past
the right edge and carries on. A figure that is taller than its column pushes
the heading up under the ribbon and carries on. A caption clipped out of a crop
looks fine until somebody asks what the third panel was.

Every one of those is invisible in the markup and obvious in a screenshot.

**Rule: if you wrote or changed a slide and did not look at it rendered, it is
not done.**

## The shot

```bash
nix-shell -p chromium --run "chromium --headless --disable-gpu --no-sandbox \
  --hide-scrollbars --window-size=1400,800 --virtual-time-budget=9000 \
  --screenshot=/tmp/shot.png 'http://localhost:8000/#/12'"
```

Then read the PNG.

On a system with chromium already installed, drop the `nix-shell` wrapper and
call `chromium` or `google-chrome` directly.

Flags that matter:

- `--virtual-time-budget=9000` gives fonts, images and reveal's own layout pass
  time to settle. Below about 5000 you screenshot a half-styled slide and chase
  a bug that is not there.
- `--window-size=1400,800` is a 16:9-ish frame with room around the stage, so
  you can see content escaping rather than having it cropped by the window.
- `--hide-scrollbars` stops a scrollbar from changing the scale.

## Off by one

`#/N` renders slide **N+1**. `#/0` is the title slide. Write it down, because
you will otherwise verify the slide next to the one you changed and conclude it
is fine.

## Both modes

The editing build (`index.html`, fetches sections over HTTP) and the shipped
build (`deck.html`, everything inlined) can differ. Inlining changes how images
resolve and when fonts arrive.

- Editing build: `http://localhost:8000/#/N` with `node serve.mjs` running.
- Shipped build: `file:///abs/path/deck.html#/N`, no server.

Verify the shipped one before delivery. It is the one that gets presented.

For `#/N` to work over `file://`, the build must keep `hash: true`. Reveal writes
the hash directly rather than through the History API, so this is safe on a local
file and is what makes the shipped deck verifiable at all.

## A whole act at once

```bash
for i in 12 13 14 15 16 17; do
  chromium --headless --disable-gpu --no-sandbox --hide-scrollbars \
    --window-size=1400,800 --virtual-time-budget=9000 \
    --screenshot=/tmp/deck/s$i.png "http://localhost:8000/#/$i"
done
```

Write them to the scratchpad, then read them in one batch. Reading six PNGs is
cheaper than six round trips.

## What to look for

Go through this list on every shot. It is short because these are the only
things that actually go wrong.

- [ ] **Nothing past the frame edge.** Especially the right edge, and especially
      rows of chips or inline boxes. Content does not clip, it escapes.
- [ ] **Nothing past the bottom.** A source line pushed off the floor is the
      most common one, and the hardest to notice, because the slide above it
      looks perfect.
- [ ] **The heading is clear of the ribbon.** If a figure grew, the heading is
      the thing that gets squeezed.
- [ ] **The block is optically centred**, not jammed to the top with a dead band
      underneath. That band means a flex rule lost to reveal's inline
      `display:block`.
- [ ] **Text in figures is readable.** A paper figure scaled to 40% width has
      6pt axis labels on the projector. Either give it width or crop tighter.
- [ ] **No lone wrapped item.** One chip alone on a second row reads as a
      mistake. Shorten a label or split the row deliberately.
- [ ] **Colour still means what it means.** Two regressions rendered in the
      measured colour will contradict the sentence above them.
- [ ] **Figure captions survived the crop.** Check the panel labels, "(c)" and
      friends, are inside the image.

## Fixes, in order of preference

1. Cut a word. Almost always available, almost always an improvement.
2. Narrow a figure: `style="width:66%; margin:0.4em auto"` and centre it.
   Anything close to square eats a column at full width.
3. Split the slide. If it needs two sentences it was two slides.
4. Change the layout to a two-column archetype.
5. Adjust a font size. Last resort. It desynchronises the slide from every
   other slide, and the gain is small.

Never fix overflow by deleting a number. See the non-negotiables.

## After a global CSS change

A rule added to fix one slide applies to every slide using that class.
Re-screenshot at least one slide per act that uses it before moving on. Adding
`flex-wrap` to a chip row is exactly the kind of edit that quietly relayouts
five other slides.
