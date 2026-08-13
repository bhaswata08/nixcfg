# Slide archetypes

A fixed catalogue of layouts, reused. Roughly fifteen of these covered a
ninety-slide deck. Inventing a layout per slide is how a deck stops looking like
one deck, and it is also how you spend an afternoon on CSS instead of content.

The CSS for all of these is in `assets/custom.css`. Copy that file into the deck
and use these classes. If you need something genuinely new, add it to that file
with a comment saying what it is for, so the next slide can reuse it.

## The catalogue

| Class | Use |
| --- | --- |
| `.title-slide` | Deck title. Used once |
| `.act-open` | Act title: number, title, one line of promise, time budget |
| `.act-body` + `.act-tag` | Every content slide. The tag is the "you are here" ribbon |
| `.roadmap` with `.row` / `.row.key` | Two-column act list. `.key` marks the load-bearing acts |
| `.qlist` | Numbered circle list, for the "by the end you will be able to" slide |
| `.beats` with `.beat.purpose` / `.breaks` / `.anchor` | Three cards: what it is for, what breaks without it, what the running example did |
| `.beats.two` / `.beats.four` | Two or four cards. Four needs one short line each |
| `.beat .no` / `.beat .note` | Second line in a card. `.no` is the broken colour and means a failure mode, `.note` is faint detail |
| `.anchor` | Inline callout for a fact from the running example |
| `.flow` with `.stage` | Pipeline. Add `.on` to highlight the box this act is about |
| `.chips` with `.c` / `.c.cost` / `.c.hit` / `.a` | Light inline sequence, when the boxes need no description |
| `.stats` with `.stat` | Big measured numbers, up to four |
| `.bars` with `.bar` / `.bar.other` | Magnitude comparison. Widths inline, usually log. Always label the scale |
| `.bar` with `.track.split` + `.cut` | Funnel variant: what survived against what was thrown away. Linear widths |
| `.layers` with `.ly` / `.ly.full` / `.ly.last` | A row of boxes for a pattern that repeats down the depth of a model |
| `.plate` | White card for a figure quoted from a source |
| `.eq` with `.f` | Framed display equation, set in the mono face |
| `.cols`, `.cols.wide-left`, `.cols.wide-right` | Two-column bodies |
| `table` | Real tabular data. 5 rows, 4 columns, then stop |
| `.say` | The one sentence under a graphic. Replaces every paragraph |
| `.src` | Small monospace citation line |
| `.takeaway` | Closing strip, one line the audience should keep |

## The shapes

**Act opener.** Every act starts with one. It is the audience's chance to
resynchronise.

```html
<section class="act-open">
  <div class="act-num">Act 2 of 10</div>
  <h1>Anatomy<br>of the bill</h1>
  <p class="act-sub">One equation for the compute. Then everything it leaves out.</p>
  <div class="act-time">7 minutes</div>
</section>
```

**Content slide.** The workhorse. Ribbon, heading, graphic, sentence, source.

```html
<section class="act-body">
  <div class="act-tag"><b>Act 2</b> / The bill</div>
  <h2>Where the 56 days went</h2>

  <div class="bars"> ... </div>

  <p class="say">Pretraining is <em>84%</em> of the calendar.</p>
  <p class="src">Olmo 3, section 2.4.</p>
</section>
```

**Three beats.** For "why does this stage exist". Purpose, what breaks without
it, what one real team did. The three colours are already wired to those roles.

```html
<div class="beats">
  <div class="beat purpose"><h4>One clean pass</h4><p>...</p></div>
  <div class="beat breaks"><h4>The search</h4><p>Roughly <b>80</b> small runs.</p></div>
  <div class="beat anchor"><h4>The measuring</h4><p>...</p></div>
</div>
```

**Flow.** A pipeline where one box is the subject of this act.

```html
<div class="flow">
  <div class="stage on"><span class="k">Stage 1</span><span class="t">Pretraining</span><span class="tok">6T tokens</span></div>
  <div class="arrow">&#8594;</div>
  <div class="stage"><span class="k">Stage 2</span><span class="t">Midtraining</span><span class="tok">100B tokens</span></div>
</div>
```

**Chips.** Cheaper than a flow, for when the sequence is the whole point.
`.c.cost` is a measured value, `.c.hit` is the result, `.a` is the operator
between them.

```html
<div class="chips">
  <span class="c">1,024 H100s</span>
  <span class="a">&#215;</span>
  <span class="c cost">1,960 tok/s each</span>
  <span class="a">=</span>
  <span class="c hit">34 days</span>
</div>
```

Chips wrap at the frame edge rather than clipping, so five is survivable, but
screenshot it. One chip alone on a second row reads as a mistake.

**Bars.** Two numbers that differ enough to be worth seeing. Widths are set
inline. If the scale is logarithmic, say so on the slide.

```html
<div class="bars">
  <div class="bar">
    <span class="nm">Pretraining<span class="sub">512 then 1024 GPUs</span></span>
    <span class="track"><span class="fill" style="width:100%"></span></span>
    <span class="v">44.5 d</span>
  </div>
  <div class="bar other">
    <span class="nm">SFT<span class="sub">4 sweeps</span></span>
    <span class="track"><span class="fill" style="width:4.5%"></span></span>
    <span class="v">2 d</span>
  </div>
</div>
```

The unfilled part of the track is often the point. A bar at 43% says "and here
is the 57% you do not get" without a word.

**Stats.** Up to four. Every number needs a label under it saying what it counts.

```html
<div class="stats">
  <div class="stat"><div class="n">56 days</div><div class="l">Start of training to an evaluated checkpoint.</div></div>
  <div class="stat"><div class="n">$2.75M</div><div class="l">At a rented $2 per GPU hour.</div></div>
</div>
```

**Recap.** Ends an act. Three lines, then one line handing off to the next act.
The handoff is what stops a deck feeling like a list of topics.

```html
<p class="say"><em>Next:</em> the largest hidden line item, getting the data.</p>
```

## Colour discipline

Three roles, fixed:

- **Structure** (amber in the shipped theme): headings, act numbers, the ribbon,
  `<em>`, "you are here"
- **Measured** (teal): numbers, results, quoted facts, `.stat .n`, `.bar .v`
- **Broken** (rose): failure modes, regressions, `.beat.breaks`, `.beat .no`

The rule that gets broken: a table of before and after where two values went
backwards. If those render in the measured colour like the rises, the slide
contradicts the sentence above it. Set them to the broken colour explicitly.

```html
<tr><td>AlpacaEval</td><td class="num">74.2</td>
    <td class="num" style="color:var(--warn)">69.1</td></tr>
```

## Emphasis

`<em>` is restyled to the structure colour and is not italic. Use it for the two
or three words in the sentence that carry it. `<strong>` is white and heavier,
for a value inside running text.

One `<em>` per sentence. Emphasis on everything is emphasis on nothing.
