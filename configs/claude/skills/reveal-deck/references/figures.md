# Figures

**If the diagram already exists in the source, take it from the source.**

Do not rebuild a paper's figure in HTML, SVG or CSS boxes. It is slower and the
result is worse every time. The original has a layout somebody iterated on, and
your version has whatever you remembered while reading it. Worse, a rebuilt
figure quietly becomes your claim rather than theirs, and you lose the ability
to cite it.

The exception is a figure that is genuinely just three boxes and two arrows, or
one you need to highlight one stage of. Build those with the `.flow` archetype.

## Extract, do not screenshot

A screenshot has the wrong resolution, a cursor in it, and JPEG artefacts on a
projector. Render the page from the PDF instead.

```bash
# 1. Render the page that has the figure, at print resolution.
pdftoppm -f 13 -l 13 -r 220 -png source.pdf /tmp/page

# 2. Crop to the figure, trim the whitespace, add a small even margin back.
magick /tmp/page-13.png -crop 1200x760+180+320 +repage \
  -trim +repage -bordercolor white -border 14 \
  assets/snr.png
```

- `-r 220` is the useful floor. It survives a 4K projector. `-r 150` looks soft.
- `+repage` after `-crop` and after `-trim` is not optional. Without it
  ImageMagick keeps the original canvas geometry and later operations land in
  the wrong place.
- `-trim` then `-border` gives an even margin regardless of how sloppy the crop
  was. Do not try to crop exactly.

## Finding the crop box

Render the page and look at it first. Do not guess coordinates from the PDF's
own units.

```bash
pdftoppm -f 13 -l 13 -r 220 -png source.pdf /tmp/page
```

Read `/tmp/page-13.png`, find the figure, estimate the box, crop, then **read
the cropped file too**. Expect two or three iterations. The failures are always
the same two:

- the caption or a panel label, "(c) Continuous batching", is clipped off the
  bottom
- a sliver of body text from the column above is included at the top

Both are obvious in the crop and invisible in the command.

## Getting the text out too

For the numbers around the figure:

```bash
pdftotext -f 12 -l 15 source.pdf /tmp/pages.txt
```

Plain mode usually beats `-layout` on figure-heavy pages. `-layout` preserves
column positions, which turns a two-column paper into interleaved nonsense.

## Mounting a figure

Paper figures arrive on a white background. Do not recolour them to match a
dark theme. It never survives the detail, and the seams show. Mount them on a
white card instead. The card reads as "this is quoted", which is honest.

```html
<div class="plate"><img src="assets/snr.png" alt="Signal to noise by benchmark"></div>
```

`.plate` is full width by default. Two cases need a width:

- **Wide figures**, past about two to one, are fine full width but push the
  sentence under them off the bottom. Screenshot and check.
- **Near-square figures** eat a whole column and push the heading into the
  ribbon. Hold them back and centre:
  `style="width:66%; margin-left:auto; margin-right:auto"`.

When you narrow a plate, leave a comment saying why, or the next pass will
helpfully widen it again.

```html
<!-- Nearly square, so it eats the column height at full width. Hold it back. -->
<div class="plate" style="width:66%; margin:0.3em auto">
```

## Cite it

Every quoted figure gets a source line. Table number, figure number, section.

```html
<p class="src">Olmo 3, Figure 7. Signal to noise on the mid-training suite.</p>
```

## Mark derived numbers as derived

If you computed a number rather than reading it, say so in the source line.

```html
<p class="src">Derived: 32B params x 2 bytes for weights, x2 for gradients,
  x6 for optimiser state. The paper gives the hardware, not this breakdown.</p>
```

This is the difference between a question you answer in four words and a
question that ends the talk.

## From PPTX

`python-pptx` gets the text and the embedded media out:

```python
from pptx import Presentation
p = Presentation("in.pptx")
for i, slide in enumerate(p.slides):
    for shape in slide.shapes:
        if shape.has_text_frame:
            print(i, shape.text_frame.text)
        if shape.shape_type == 13:  # picture
            with open(f"assets/s{i}-{shape.shape_id}.png", "wb") as f:
                f.write(shape.image.blob)
```

Take the content and the images. Leave the layout. A PPTX layout converted
faithfully to HTML is a bad PPTX layout in a new format.
