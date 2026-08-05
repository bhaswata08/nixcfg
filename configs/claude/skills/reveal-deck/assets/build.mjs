// Compiles the whole deck into one self contained HTML file.
//
//   node build.mjs        # writes deck.html
//
// The result opens straight off the disk with no server and no network. Every
// stylesheet, font, script, section and image is inlined, so it can be emailed,
// put on a USB stick, or opened on a machine that has never seen this repo.
//
// The served version (index.html) fetches sections/*.html at runtime, which is
// what makes it pleasant to edit. This script is the other end of that trade.
// Edit the sections, then re-run this. Never edit deck.html by hand.

import { readFile, writeFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const HERE = dirname(fileURLToPath(import.meta.url));
const p = (...parts) => join(HERE, ...parts);

const OUT = p('deck.html');
const TITLE = 'DECK TITLE';

// Must match the SECTIONS array in index.html. Two lists is a wart, but the
// alternative is parsing index.html, and that is worse.
const SECTIONS = [
  '00-open.html',
];

// Only the latin subsets. If the deck is in English, the other subsets would
// triple the file for glyphs no slide contains. Add subsets if it is not.
const FONTS = [
  ['Inter', 400, 'inter/files/inter-latin-400-normal.woff2'],
  ['Inter', 500, 'inter/files/inter-latin-500-normal.woff2'],
  ['Inter', 600, 'inter/files/inter-latin-600-normal.woff2'],
  ['JetBrains Mono', 400, 'jetbrains-mono/files/jetbrains-mono-latin-400-normal.woff2'],
  ['JetBrains Mono', 500, 'jetbrains-mono/files/jetbrains-mono-latin-500-normal.woff2'],
];

const text = (f) => readFile(f, 'utf8');
const b64 = async (f) => (await readFile(f)).toString('base64');

async function fontFaces() {
  const out = [];
  for (const [family, weight, file] of FONTS) {
    const data = await b64(p('lib/node_modules/@fontsource', file));
    out.push(
      `@font-face{font-family:'${family}';font-style:normal;font-weight:${weight};` +
        `font-display:swap;src:url(data:font/woff2;base64,${data}) format('woff2')}`
    );
  }
  return out.join('\n');
}

// Rewrites <img src="assets/x.png"> to a data URI. Add mime types here if the
// deck ever carries anything other than PNGs.
const MIME = { png: 'image/png', jpg: 'image/jpeg', jpeg: 'image/jpeg', svg: 'image/svg+xml', gif: 'image/gif' };

async function inlineImages(html) {
  const seen = new Map();
  for (const [, src] of html.matchAll(/src="(assets\/[^"]+)"/g)) {
    if (seen.has(src)) continue;
    const ext = src.split('.').pop().toLowerCase();
    const mime = MIME[ext];
    if (!mime) throw new Error(`No mime type for ${src}. Add it to MIME in build.mjs.`);
    seen.set(src, `data:${mime};base64,${await b64(p(src))}`);
  }
  for (const [src, uri] of seen) html = html.split(`src="${src}"`).join(`src="${uri}"`);
  return html;
}

// The UMD build, not the .mjs one. An inline <script type="module"> is subject
// to CORS on a file:// URL, so the module build would not run off the disk.
const reveal = await text(p('lib/node_modules/reveal.js/dist/reveal.js'));
const css = [
  await text(p('lib/node_modules/reveal.js/dist/reset.css')),
  await text(p('lib/node_modules/reveal.js/dist/reveal.css')),
  await fontFaces(),
  await text(p('css/custom.css')),
].join('\n');

let slides = '';
for (const file of SECTIONS) {
  slides += `\n<!-- ===== ${file} ===== -->\n` + (await text(p('sections', file)));
}
slides = await inlineImages(slides);

const html = `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>${TITLE}</title>
<!-- Built by build.mjs. Do not edit: edit sections/*.html and rebuild. -->
<style>
${css}
</style>
</head>
<body>

<div class="reveal">
  <div class="slides">
${slides}
  </div>
</div>

<script>
${reveal}
</script>
<script>
  Reveal.initialize({
    width: 1280,
    height: 720,
    // We own vertical placement ourselves: every section is a full height flex
    // column. Reveal's own centring fights that and leaves a dead band.
    center: false,
    margin: 0.06,
    minScale: 0.2,
    maxScale: 1.6,
    // Reveal writes the hash directly rather than through the History API, so
    // this is safe on a file:// URL and #/12 still jumps to a slide. That is
    // what makes the shipped file verifiable by screenshot.
    hash: true,
    slideNumber: 'c/t',
    transition: 'fade',
    transitionSpeed: 'fast',
  });
</script>

</body>
</html>
`;

await writeFile(OUT, html);
const mb = (Buffer.byteLength(html) / 1024 / 1024).toFixed(2);
console.log(`deck.html written: ${SECTIONS.length} acts, ${(html.match(/<section/g) || []).length} slides, ${mb} MB`);
