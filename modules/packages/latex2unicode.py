"""Render a LaTeX formula to multi-line unicode text.

Reads LaTeX on stdin, writes unicode on stdout. Matrix environments become
2D grids with tall brackets and \\frac becomes a stacked fraction; everything
else is handed to unicodeit (sub/superscripts, greek) then pylatexenc's
latex2text (\\mathscr, \\cdots, ...). render-markdown.nvim renders the
multi-line result as virtual lines above the formula.
"""

import re
import sys
import unicodedata

from pylatexenc.latex2text import LatexNodes2Text
from unicodeit.replace import replace as unicodeit_replace

_L2T = LatexNodes2Text()

# env name -> (left, right) delimiter; '' means no delimiter
DELIMS = {
    "matrix": ("", ""),
    "smallmatrix": ("", ""),
    "bmatrix": ("[", "]"),
    "Bmatrix": ("{", "}"),
    "pmatrix": ("(", ")"),
    "vmatrix": ("|", "|"),
    "Vmatrix": ("\u2016", "\u2016"),
    "array": ("", ""),
    "cases": ("{", ""),
}

# left delimiter -> (top, middle, bottom) glyphs used when it spans >1 line
TALL = {
    "[": ("\u23a1", "\u23a2", "\u23a3"),
    "]": ("\u23a4", "\u23a5", "\u23a6"),
    "(": ("\u239b", "\u239c", "\u239d"),
    ")": ("\u239e", "\u239f", "\u23a0"),
    "{": ("\u23a7", "\u23aa", "\u23a9"),
    "}": ("\u23ab", "\u23aa", "\u23ad"),
    "|": ("\u2502", "\u2502", "\u2502"),
    "\u2016": ("\u2016", "\u2016", "\u2016"),
}

BEGIN = re.compile(r"\\begin\{(" + "|".join(DELIMS) + r")\}")
FRAC = re.compile(r"\\[dt]?frac(?![a-zA-Z])")
SCRIPT = re.compile(r"[_^]")
ROW_SEP = re.compile(r"\\\\\s*(?:\[[^\]]*\])?")
CELL_SEP = re.compile(r"&")
LEFT = re.compile(r"\\left\s*(\(|\[|\\\{|\\\||\||\.)")
RIGHT = re.compile(r"\\right\s*(\)|\]|\\\}|\\\||\||\.)")

# \left/\right argument -> the glyph to draw ('.' is an invisible delimiter)
DELIM_GLYPH = {
    "(": "(",
    ")": ")",
    "[": "[",
    "]": "]",
    "\\{": "{",
    "\\}": "}",
    "|": "|",
    "\\|": "\u2016",
    ".": "",
    "": "",
}


# characters with a sub/superscript form: latex2text's minus and \times land
# here too, since scripts are converted after the libraries have run
SUPER_FROM = "0123456789+-=()abcdefghijklmnoprstuvwxyz−×"
SUPER_TO = "⁰¹²³⁴⁵⁶⁷⁸⁹⁺⁻⁼⁽⁾ᵃᵇᶜᵈᵉᶠᵍʰⁱʲᵏˡᵐⁿᵒᵖʳˢᵗᵘᵛʷˣʸᶻ⁻ˣ"
SUB_FROM = "0123456789+-=()aehijklmnoprstuvx−"
SUB_TO = "₀₁₂₃₄₅₆₇₈₉₊₋₌₍₎ₐₑₕᵢⱼₖₗₘₙₒₚᵣₛₜᵤᵥₓ₋"
SUPERSCRIPT = str.maketrans(SUPER_FROM, SUPER_TO)
SUBSCRIPT = str.maketrans(SUB_FROM, SUB_TO)


def width(text):
    """Display width, matching how neovim measures a line (ambiwidth=single)."""
    total = 0
    for char in text:
        if unicodedata.combining(char):
            continue
        total += 2 if unicodedata.east_asian_width(char) in "WF" else 1
    return total


def pad(text, target):
    return text + " " * max(0, target - width(text))


class Box:
    """Lines of text plus the index of the line that sits on the baseline."""

    def __init__(self, lines, baseline=0):
        self.lines = lines or [""]
        self.baseline = baseline
        self.width = max(width(line) for line in self.lines)
        self.lines = [pad(line, self.width) for line in self.lines]

    @property
    def height(self):
        return len(self.lines)


def hstack(boxes, sep=""):
    """Join boxes side by side, aligned on their baselines."""
    boxes = [b for b in boxes if b.width or b.height > 1]
    if not boxes:
        return Box([""])
    above = max(b.baseline for b in boxes)
    below = max(b.height - b.baseline - 1 for b in boxes)
    lines = [""] * (above + below + 1)
    for i, box in enumerate(boxes):
        pad_top = above - box.baseline
        cells = (
            [" " * box.width] * pad_top
            + box.lines
            + [" " * box.width] * (len(lines) - pad_top - box.height)
        )
        for j, cell in enumerate(cells):
            lines[j] += (sep if i else "") + cell
    return Box(lines, above)


def center(box, width, height, baseline):
    """Grow a box to the given geometry, keeping it centered horizontally."""
    pad = width - box.width
    lines = [" " * (pad // 2) + line + " " * (pad - pad // 2) for line in box.lines]
    top = baseline - box.baseline
    lines = [" " * width] * top + lines + [" " * width] * (height - top - box.height)
    return Box(lines, baseline)


def flat(text):
    """Hand a chunk with no scripts and no 2D structure to the two libraries."""
    text = text.strip()
    if not text:
        return ""
    try:
        text = unicodeit_replace(text)
    except Exception:
        pass
    try:
        text = _L2T.latex_to_text(text)
    except Exception:
        pass
    return " ".join(text.split("\n")).strip()


def small(text, up):
    """Sub/superscript a converted string, or None if some char has no form."""
    text = "".join(text.split())
    if not text:
        return None
    result = text.translate(SUPERSCRIPT if up else SUBSCRIPT)
    known = SUPER_TO if up else SUB_TO
    missing = any(a == b and b not in known for a, b in zip(text, result))
    return None if missing else result


def scripts(text):
    """Convert _{..}/^{..} groups the libraries cannot: they drop the braces,
    losing the scope, so anything they leave behind is unrecoverable."""
    out, i = "", 0
    while i < len(text):
        if text[i] in "_^" and i + 1 < len(text):
            body, j = group(text, i + 1)
            shrunk = small(flat(scripts(body)), text[i] == "^")
            if shrunk:
                out, i = out + shrunk, j
                continue
        out += text[i]
        i += 1
    return out


def leaf(text):
    """Convert a chunk with no 2D structure into a single line."""
    return Box([flat(scripts(text))])


def group(s, i):
    """Read the brace group starting at s[i]; return (contents, next index)."""
    while i < len(s) and s[i].isspace():
        i += 1
    if i >= len(s):
        return "", i
    if s[i] != "{":
        return s[i], i + 1
    depth, start = 0, i
    while i < len(s):
        if s[i] == "{" and (i == start or s[i - 1] != "\\"):
            depth += 1
        elif s[i] == "}" and s[i - 1] != "\\":
            depth -= 1
            if depth == 0:
                return s[start + 1 : i], i + 1
        i += 1
    return s[start + 1 :], len(s)


def environment(s, i, env):
    """Read up to the \\end{env} matching the \\begin{env} just consumed."""
    depth = 1
    begin = re.compile(r"\\(begin|end)\{" + env + r"\}")
    pos = i
    while depth:
        m = begin.search(s, pos)
        if not m:
            return s[i:], len(s)
        depth += 1 if m.group(1) == "begin" else -1
        pos = m.end()
    return s[i : pos - len("\\end{}") - len(env)], pos


def split(s, pattern):
    """Split on pattern, ignoring matches nested in braces or environments."""
    parts, depth, start, i = [], 0, 0, 0
    while i < len(s):
        if s.startswith("\\begin", i):
            depth += 1
        elif s.startswith("\\end", i):
            depth -= 1
        elif s[i] == "{" and s[i - 1 : i] != "\\":
            depth += 1
        elif s[i] == "}" and s[i - 1 : i] != "\\":
            depth -= 1
        m = pattern.match(s, i) if depth <= 0 else None
        if m and m.end() > i:
            parts.append(s[start:i])
            start = i = m.end()
            continue
        i += 1
    parts.append(s[start:])
    return parts


def fraction(num, den):
    top, bottom = render(num), render(den)
    inner = max(top.width, bottom.width) + 2
    lines = (
        center(top, inner, top.height, top.baseline).lines
        + ["\u2500" * inner]
        + center(bottom, inner, bottom.height, bottom.baseline).lines
    )
    return Box(lines, top.height)


def matrix(body, env):
    grid = [
        [render(cell) for cell in split(row, CELL_SEP)]
        for row in split(body, ROW_SEP)
        if row.strip()
    ]
    if not grid:
        return Box([""])
    columns = max(len(row) for row in grid)
    widths = [
        max((row[c].width for row in grid if c < len(row)), default=0)
        for c in range(columns)
    ]
    rows = []
    for row in grid:
        above = max(cell.baseline for cell in row)
        below = max(cell.height - cell.baseline - 1 for cell in row)
        height = above + below + 1
        cells = [
            center(row[c] if c < len(row) else Box([""]), widths[c], height, above)
            for c in range(columns)
        ]
        rows.append(hstack(cells, sep="  "))
    # tall rows (fractions, nested matrices) need a blank line to read as rows
    gap = any(row.height > 1 for row in rows)
    lines = []
    for i, row in enumerate(rows):
        if i and gap:
            lines.append("")
        lines.extend(row.lines)
    body_box = Box(lines, len(lines) // 2)
    left, right = DELIMS[env]
    return hstack([bracket(left, body_box), body_box, bracket(right, body_box)])


def bracket(glyph, box):
    if not glyph:
        return Box([""])
    if box.height == 1:
        return Box([glyph], 0)
    top, middle, bottom = TALL[glyph]
    lines = [top] + [middle] * (box.height - 2) + [bottom]
    return Box(lines, box.baseline)


def script(s, i, box):
    """Attach any trailing _{..}/^{..} to a rendered box."""
    while True:
        j = i
        while j < len(s) and s[j].isspace():
            j += 1
        if j >= len(s) or not SCRIPT.match(s[j]):
            return box, i
        body, i = group(s, j + 1)
        up = s[j] == "^"
        inner = render(body)
        text = small(inner.lines[0], up) if inner.height == 1 else None
        if text is None and box.height == 1 and inner.height == 1:
            text = s[j] + inner.lines[0]  # marker: nothing else marks it
        if text is not None:
            lines = list(box.lines)
            row = 0 if up else len(lines) - 1
            lines[row] = lines[row] + text
            box = Box(lines, box.baseline)
        else:
            # hang it off a corner: bottom line beside the box's top line for a
            # superscript, top line beside the box's bottom line for a subscript
            if up:
                corner = Box(inner.lines, inner.height - 1 + box.baseline)
            else:
                corner = Box(inner.lines, box.baseline - box.height + 1)
            box = hstack([box, corner])


def delimited(s, i, glyph):
    """Read up to the \\right matching a \\left, and wrap what is between."""
    depth, pos = 1, i
    while depth:
        m = re.compile(r"\\(left|right)").search(s, pos)
        if not m:
            end = stop = len(s)
            close = ""
            break
        depth += 1 if m.group(1) == "left" else -1
        pos = m.end()
        if not depth:
            right = RIGHT.match(s, m.start())
            stop = right.end() if right else pos
            end, close = m.start(), (right.group(1) if right else "")
    inner = render(s[i:end])
    glyph, close = DELIM_GLYPH.get(glyph, ""), DELIM_GLYPH.get(close, "")
    return hstack([bracket(glyph, inner), inner, bracket(close, inner)]), stop


def render(s):
    """Render a LaTeX fragment into a Box, recursing through 2D constructs."""
    boxes, buf, i = [], "", 0
    while i < len(s):
        begin = BEGIN.match(s, i)
        frac = FRAC.match(s, i)
        left = LEFT.match(s, i)
        if begin:
            env = begin.group(1)
            body, i = environment(s, begin.end(), env)
            if env == "array":  # drop the column spec, we always center
                body = body[group(body, 0)[1] :]
            box, i = script(s, i, matrix(body, env))
            boxes += [leaf(buf), box]
            buf = ""
        elif frac:
            num, i = group(s, frac.end())
            den, i = group(s, i)
            box, i = script(s, i, fraction(num, den))
            boxes += [leaf(buf), box]
            buf = ""
        elif left:
            box, i = delimited(s, left.end(), left.group(1))
            box, i = script(s, i, box)
            boxes += [leaf(buf), box]
            buf = ""
        else:
            buf += s[i]
            i += 1
    boxes.append(leaf(buf))
    return hstack(boxes, sep=" ")


def main():
    source = sys.stdin.read().strip()
    if not source:
        return
    try:
        box = render(source)
    except Exception:  # never drop a formula: fall back to the flat pipeline
        box = leaf(source)
    sys.stdout.write("\n".join(line.rstrip() for line in box.lines) + "\n")


if __name__ == "__main__":
    main()
