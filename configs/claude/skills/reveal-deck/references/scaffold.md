# Scaffold

## Layout

```
deck/
  index.html        reveal bootstrap and the SECTIONS running order
  build.mjs         compiles everything into the single file deck.html
  deck.html         generated. Never edit it by hand
  serve.mjs         local static server
  css/custom.css    the theme: colour tokens, type scale, slide archetypes
  sections/         one file per act, numbered
  assets/           figures extracted from the source
  lib/              reveal.js and the fonts, vendored
  README.md         act plan, archetype table, house rules
```

## Set it up

```bash
mkdir -p deck/{css,sections,assets,lib}
cd deck/lib && npm install reveal.js @fontsource/inter @fontsource/jetbrains-mono
```

Then copy `index.html`, `build.mjs`, `serve.mjs` and `css/custom.css` from this
skill's `assets/` directory.

**Vendor, do not use a CDN.** Presentation rooms have no wifi, or have wifi that
fails during your talk. This is the only real requirement.

**Vendor the fonts too.** System fallbacks render heavier than Inter, and slides
that fitted during authoring stop fitting on the night.

## Two modes, one source

**Editing.** `index.html` fetches `sections/*.html` at runtime, so a change to
one act is a browser refresh with no build step.

```bash
node serve.mjs        # http://localhost:8000/
```

A server is needed because browsers block `fetch` over `file://`.

**Shipping.** `build.mjs` inlines the stylesheets, the fonts as base64 woff2,
every section, every image as a data URI, and reveal itself.

```bash
node build.mjs        # writes deck.html
```

The result opens by double-clicking, needs no server and no network, and can be
emailed or put on a stick. Rebuild after any edit.

Set this up at the start, not at the end. Retrofitting the single-file build
onto a finished deck means finding every path assumption at the worst moment.

## The two SECTIONS lists

The running order lives in `index.html` and again in `build.mjs`. Adding an act
means adding it to both. This is a wart. The alternative is parsing `index.html`
from the build script, which is worse. Keep unbuilt acts commented in both so
the plan is visible:

```js
const SECTIONS = [
  '00-open.html',
  '01-model-flow.html',
  // '02-costs.html',
];
```

## Reveal config

```js
Reveal.initialize({
  width: 1280,
  height: 720,
  // We own vertical placement: every section is a full height flex column.
  // Reveal's own centring fights that and leaves a dead band.
  center: false,
  margin: 0.06,
  minScale: 0.2,
  maxScale: 1.6,
  hash: true,
  slideNumber: 'c/t',
  transition: 'fade',
  transitionSpeed: 'fast',
});
```

`hash: true` in the built file is deliberate. Reveal writes the hash directly
rather than through the History API, so it is safe on a `file://` URL, and it is
what makes `deck.html#/12` verifiable by screenshot.

`slideNumber: 'c/t'` stays on while building. It is how you map a screenshot back
to a slide.

## The height chain

With `center: false` the deck owns vertical placement, and that needs an
unbroken height chain:

```css
.reveal .slides { height: 100%; }
.reveal .slides section { height: 100%; box-sizing: border-box; }

.reveal section.act-body {
  display: flex !important;
  flex-direction: column;
  justify-content: center;
}
```

**The `!important` is load bearing.** Reveal writes `display: block` as an inline
style on whichever slide is showing. An inline style beats a plain class rule, so
without it every flex layout silently collapses and the content jams to the top.
This applies to every section class that is a flex column.

## Act files

One file per act. Open each with a header comment recording the budget, the
source, the goal, and the boundary with adjacent acts:

```html
<!-- ============================================================
     ACT 2 of 10. Anatomy of the bill. Budget: 7 min.
     Source: Olmo 3 section 2.4, plus Table 34 for throughput.
     Goal: the audience can do the compute arithmetic themselves.
     Act 6 owns systems. Do not re-derive the cost there.
     Every number in section 2.4 is on a slide somewhere: do not
     drop them when editing.
     ============================================================ -->
```

The boundary lines are what stop a later pass from "fixing" deliberate overlap.

## README

Keep one in the deck. It carries the act plan with a status column, the
archetype table, the colour meanings, and the house rules. It is what makes the
deck editable in three months, by you or by anyone else.
