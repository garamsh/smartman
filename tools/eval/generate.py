# /// script
# requires-python = ">=3.12"
# dependencies = ["pillow==12.3.0", "numpy==2.5.3", "fonttools==4.66.1"]
# ///
"""Writes the eval's synthetic sample set: photos of vocabulary and notes pages, and their truth.

Regenerate from the repository root with:

    uv run --locked --script tools/eval/generate.py

Each sample is a page in one layout and language pair, set in the bundled OFL fonts under
tools/eval/fonts/, then photographed synthetically: perspective, rotation, uneven lighting,
blur, and JPEG noise. Every random choice comes from SEED and the sample's index, so a rerun
with the locked dependencies writes the same files. The cards a vocabulary page shows, each sense
with the labels and examples it prints, are written beside its image as the ground truth; a notes
page's truth is the rules and exceptions it teaches, each with its step, the terms that cover it
and the worked examples the page prints for it, and every line it prints, from tools/eval/notes.json.
A page for the two-stage eval adds its sections, each line with its marks and the spans to blank,
from tools/eval/structure.json.
"""

import json
from dataclasses import dataclass
from pathlib import Path

import numpy as np
from fontTools.ttLib import TTFont
from PIL import Image, ImageDraw, ImageFilter, ImageFont

SEED = 20261015
HERE = Path(__file__).parent
FONTS = HERE / "fonts"
SAMPLES = HERE / "samples"

LAYOUTS = ["two-column", "bilingual-table", "dictionary", "glossary"]
PAIRS = ["en-ko", "ja-ko"]
STYLES = ["print", "handwriting", "harsh"]

PAGE = (1240, 1754)
LONG_SIDE = 1600

# The font each side is set in, per language pair and hand.
FACES = {
    ("en-ko", "print"): ("NanumGothic-Regular.ttf", "NanumGothic-Regular.ttf"),
    ("en-ko", "handwriting"): ("NanumPenScript-Regular.ttf", "NanumPenScript-Regular.ttf"),
    ("ja-ko", "print"): ("SawarabiGothic-Regular.ttf", "NanumGothic-Regular.ttf"),
    ("ja-ko", "handwriting"): ("Yomogi-Regular.ttf", "NanumPenScript-Regular.ttf"),
}
LABEL_FACE = "NanumGothic-Regular.ttf"
HEADINGS = {"en-ko": ("English", "한국어"), "ja-ko": ("日本語", "한국어")}


@dataclass(frozen=True)
class Distortion:
    perspective: float  # largest corner shift, as a fraction of the side
    rotation: float  # largest rotation, in degrees
    shadow: float  # darkest light level of the gradient, 1.0 for even light
    blur: float  # Gaussian blur radius, in pixels of the page
    noise: float  # standard deviation of the added noise, in 0-255 levels
    quality: int  # JPEG quality


MILD = Distortion(perspective=0.03, rotation=4, shadow=0.8, blur=0.6, noise=4, quality=82)
HARSH = Distortion(perspective=0.05, rotation=9, shadow=0.55, blur=1.6, noise=10, quality=55)


class Page:
    """A blank sheet and the fonts it is set in; `ink` jitters baselines for handwriting."""

    def __init__(self, rng: np.random.Generator, pair: str, hand: str, faces: tuple[str, str] | None = None):
        self.rng = rng
        self.image = Image.new("RGB", PAGE, (250, 248, 240))
        self.draw = ImageDraw.Draw(self.image)
        self.front_face, self.back_face = faces or FACES[(pair, hand)]
        self.handwritten = hand == "handwriting"
        self.ink = (25, 40, 110) if self.handwritten else (20, 20, 20)
        self.covered: dict[str, set[str]] = {}

    def font(self, face: str, size: int) -> ImageFont.FreeTypeFont:
        # Handwriting faces draw small, so they are set larger to read alike.
        scale = {"NanumPenScript-Regular.ttf": 1.5, "Yomogi-Regular.ttf": 1.15}.get(face, 1.0)
        return ImageFont.truetype(str(FONTS / face), round(size * scale), layout_engine=ImageFont.Layout.BASIC)

    def text(self, xy: tuple[float, float], text: str, face: str, size: int, fill=None) -> float:
        """Draws text from xy, its baseline `size` below y so mixed faces line up, and returns its width."""
        self.covered.setdefault(face, set()).update(text)
        x, y = xy
        if self.handwritten:
            x += self.rng.uniform(-3, 3)
            y += self.rng.uniform(-4, 4)
        font = self.font(face, size)
        self.draw.text((x, y + size), text, font=font, fill=fill or self.ink, anchor="ls")
        return font.getlength(text)

    def width(self, text: str, face: str, size: int) -> float:
        return self.font(face, size).getlength(text)


def two_column(page: Page, entries: list[dict], pair: str) -> None:
    page.text((110, 90), "Vocabulary  단어 목록", LABEL_FACE, 44, (60, 60, 60))
    y = 210
    for number, entry in enumerate(entries, 1):
        page.text((110, y), f"{number}.", LABEL_FACE, 34, (90, 90, 90))
        page.text((190, y), entry["front"], page.front_face, 38)
        page.text((680, y), entry["back"], page.back_face, 38)
        y += (PAGE[1] - 320) / len(entries)


def bilingual_table(page: Page, entries: list[dict], pair: str) -> None:
    left, right, middle = 100, PAGE[0] - 100, PAGE[0] // 2
    row = min(110, (PAGE[1] - 260) // (len(entries) + 1))
    top = 140
    bottom = top + row * (len(entries) + 1)
    for i in range(len(entries) + 2):
        page.draw.line([(left, top + i * row), (right, top + i * row)], fill=(70, 70, 70), width=2)
    for x in (left, middle, right):
        page.draw.line([(x, top), (x, bottom)], fill=(70, 70, 70), width=2)
    page.draw.rectangle([left + 2, top + 2, right - 2, top + row - 2], fill=(225, 230, 240))
    front_heading, back_heading = HEADINGS[pair]
    page.text((left + 30, top + row * 0.28), front_heading, page.front_face, 36, (40, 40, 40))
    page.text((middle + 30, top + row * 0.28), back_heading, LABEL_FACE, 36, (40, 40, 40))
    for i, entry in enumerate(entries, 1):
        y = top + i * row + row * 0.25
        page.text((left + 30, y), entry["front"], page.front_face, 38)
        page.text((middle + 30, y), entry["back"], page.back_face, 38)


def dictionary(page: Page, entries: list[dict], pair: str) -> None:
    y = 110
    step = (PAGE[1] - 220) / len(entries)
    for entry in entries:
        x = 100
        x += page.text((x, y), entry["front"], page.front_face, 46) + 24
        x += page.text((x, y + 10), entry["pos"], LABEL_FACE, 30, (150, 40, 40)) + 20
        page.text((x, y + 6), entry["back"], page.back_face, 38)
        if "example" in entry:
            page.text((140, y + 66), entry["example"], page.front_face, 30, (90, 90, 90))
        page.draw.line([(100, y + step - 22), (PAGE[0] - 100, y + step - 22)], fill=(200, 200, 200), width=1)
        y += step


def glossary(page: Page, entries: list[dict], pair: str) -> None:
    unit = int(page.rng.integers(1, 13))
    page.text((100, 90), f"Unit {unit}  Glossary", LABEL_FACE, 48, (30, 60, 120))
    page.text((100, 160), f"{unit}과 새 단어", LABEL_FACE, 32, (90, 90, 90))
    page.draw.line([(100, 220), (PAGE[0] - 100, 220)], fill=(30, 60, 120), width=4)
    half = (len(entries) + 1) // 2
    rows = max(half, 1)
    step = min(120, (PAGE[1] - 400) / rows)
    for i, entry in enumerate(entries):
        x = 100 if i < half else PAGE[0] // 2 + 20
        y = 270 + (i % half) * step
        width = page.text((x, y), "•", LABEL_FACE, 34, (30, 60, 120))
        x += width + 14
        x += page.text((x, y), entry["front"], page.front_face, 36) + 18
        page.text((x, y + 2), entry["back"], page.back_face, 34, (70, 70, 70) if not page.handwritten else None)
    page.text((PAGE[0] // 2 - 30, PAGE[1] - 110), f"— {10 + unit * 4} —", LABEL_FACE, 30, (120, 120, 120))


# The face a notes page is written in, per hand; both cover Korean and Latin.
NOTE_FACES = {"print": "NanumGothic-Regular.ttf", "handwriting": "NanumPenScript-Regular.ttf"}
NOTE_LANGUAGES = ["ko", "en"]
NOTE_HANDS = ["print", "handwriting"]
NOTE_DISTORTIONS = ["mild", "harsh"]
# The further pages, each in every hand and distortion after the pages above: a dense page of
# many small rules, worked examples and marked exceptions, a page with a classification table and
# the writer's own additions in pen, and a page with a classification table, judgment rules,
# starred handwritten tips and a side box.
DENSE_DOCUMENTS = ["ko-grammar", "ko-auxiliary", "ko-numerals"]
# The pages for prompt v7, each in every hand and distortion after the word book pages: a page
# whose classification table is to be memorised, its truth naming the cells a table card should
# blank, and a page of list lines recalled in context, naming the words a cloze card should.
BLANK_DOCUMENTS = ["ko-honorifics", "ko-components"]
MARK_COLOUR = (190, 40, 40)
# A line the writer added by hand, in pen, in the handwriting face on every page.
ADDITION_COLOUR = (30, 90, 170)
ADDITION_FACE = NOTE_FACES["handwriting"]


def wrap(page: Page, text: str, face: str, size: int, width: float) -> list[str]:
    """Breaks text at spaces into lines no wider than width, as a writer would."""
    lines: list[str] = []
    line = ""
    for word in text.split(" "):
        candidate = word if not line else f"{line} {word}"
        if line and page.width(candidate, face, size) > width:
            lines.append(line)
            line = word
        else:
            line = candidate
    return lines + [line]


def star(page: Page, centre: tuple[float, float], radius: float) -> None:
    """A five-pointed star, as a writer marks a line to remember."""
    cx, cy = centre
    points = [(cx + (radius if i % 2 == 0 else radius * 0.4) * np.sin(i * np.pi / 5),
               cy - (radius if i % 2 == 0 else radius * 0.4) * np.cos(i * np.pi / 5)) for i in range(10)]
    page.draw.polygon(points, outline=MARK_COLOUR, width=3)


def notes(page: Page, doc: dict) -> None:
    """A page of notes: a title, headings, points and sub-points under them, examples, and table
    rows whose cells `text` separates with " | "; a page sets them at its `scale`. A line's `mark`
    draws a star before it or a circle around its first line; a line with `hand` is the writer's
    addition in pen, an `aside` is one written beside the heading above it, and a `box` is a
    framed side box."""
    scale = doc.get("scale", 1.0)
    page.text((100, 80), doc["title"], page.front_face, 50, (30, 60, 120) if not page.handwritten else None)
    page.draw.line([(100, 160), (PAGE[0] - 100, 160)], fill=(30, 60, 120), width=3)
    y = 200
    heading_end = (0.0, 0.0)
    for line in doc["lines"]:
        kind = line["kind"]
        added = line.get("hand", False) or kind == "aside"
        face = ADDITION_FACE if added else page.front_face
        if kind == "aside":
            x, at = heading_end
            page.text((x + 40, at), line["text"], face, round(30 * scale), ADDITION_COLOUR)
            continue
        if kind == "row":
            y = table_row(page, line, round(30 * scale), y)
            continue
        if kind == "box":
            y = side_box(page, line["text"], round(28 * scale), y)
            continue
        base, indent, mark, colour = {
            "heading": (40, 100, "", (30, 60, 120)),
            "point": (32, 130, "- ", None),
            "sub": (30, 190, "- ", None),
            "example": (30, 160, "", (120, 60, 30)),
        }[kind]
        size = round(base * scale)
        colour = ADDITION_COLOUR if added else colour
        if kind == "heading":
            y += 14
        if line.get("mark") == "star":
            star(page, (indent - 28, y + size * 0.6), size * 0.55)
        for i, part in enumerate(wrap(page, mark + line["text"], face, size, PAGE[0] - 100 - indent)):
            x = indent + (0 if i == 0 else page.width(mark, face, size))
            width = page.text((x, y), part, face, size, colour if added or not page.handwritten else None)
            if i == 0 and kind == "heading":
                heading_end = (x + width, y)
            if i == 0 and line.get("mark") == "circle":
                page.draw.ellipse([(x - 16, y - size * 0.15), (x + width + 16, y + size * 1.35)],
                                  outline=MARK_COLOUR, width=3)
            y += size * 1.55
    if y > PAGE[1] - 60:
        raise SystemExit(f"the notes page {doc['title']} runs off the page")


def side_box(page: Page, text: str, size: int, y: float) -> float:
    """A framed box of printed text set off from the notes, as a textbook prints a note to the side;
    returns the y below it."""
    left, right, pad = 130, PAGE[0] - 100, 16
    top = y + size * 0.4
    lines = wrap(page, text, page.front_face, size, right - left - 2 * pad)
    bottom = top + pad * 2 + len(lines) * size * 1.5
    page.draw.rectangle([(left, top), (right, bottom)], outline=(90, 90, 90), width=2)
    for i, part in enumerate(lines):
        page.text((left + pad, top + pad + i * size * 1.5), part, page.front_face, size)
    return bottom + size * 0.6


# A table row's cell widths, as shares of the page between its margins.
TABLE_COLUMNS = (0.24, 0.46, 0.30)


def table_row(page: Page, line: dict, size: int, y: float) -> float:
    """One row of a ruled table, its cells from `text` split at " | ", a header row when
    `header` is set; returns the y below it."""
    left, right = 130, PAGE[0] - 100
    height = size * 1.9
    x = float(left)
    for share, cell in zip(TABLE_COLUMNS, line["text"].split(" | ")):
        width = (right - left) * share
        page.draw.rectangle([(x, y), (x + width, y + height)], outline=(90, 90, 90), width=2)
        page.text((x + 12, y + size * 0.45), cell, page.front_face, size,
                  (30, 60, 120) if line.get("header") and not page.handwritten else None)
        x += width
    return y + height


def word_book(page: Page, entries: list[dict], title: str) -> None:
    """A word book's entries: each headword with its pronunciation when it has one, one line per
    sense with its labels in red and its examples under it, and its extras under their labels."""
    page.text((100, 90), title, LABEL_FACE, 44, (60, 60, 60))
    y = 200
    for entry in entries:
        x = 100 + page.text((100, y), entry["front"], page.front_face, 48) + 24
        if "pronunciation" in entry:
            page.text((x, y + 12), entry["pronunciation"], LABEL_FACE, 30, (90, 90, 90))
        y += 72
        for sense in entry["senses"]:
            x = 140
            for label in sense["labels"]:
                x += page.text((x, y), label, LABEL_FACE, 32, (150, 40, 40)) + 18
            page.text((x, y), sense["meaning"], page.back_face, 36)
            y += 52
            for example in sense.get("examples", []):
                page.text((180, y), example, page.front_face, 28, (90, 90, 90))
                y += 44
        for extra in entry.get("extras", []):
            x = 140 + page.text((140, y), extra["label"], LABEL_FACE, 28, (30, 60, 120)) + 16
            page.text((x, y), extra["text"], page.front_face, 30)
            y += 46
        page.draw.line([(100, y + 4), (PAGE[0] - 100, y + 4)], fill=(200, 200, 200), width=1)
        y += 28
    if y > PAGE[1] - 60:
        raise SystemExit("the word book page runs off the page")


# The category of each part-of-speech label the pages print, by its text without brackets; any
# other label, such as a semantic class, has none (ADR 0075).
CATEGORIES = {
    "n.": "noun", "v.": "verb", "adj.": "adjective", "adv.": "adverb",
    "명": "noun", "동": "verb", "형": "adjective", "부": "adverb",
    "명사": "noun", "동사": "verb", "형용사": "adjective",
}
BRACKETS = ["[]", "「」"]


def truth_label(printed: str) -> dict:
    """A printed label's truth: its text without the brackets around it, and its category."""
    text = printed[1:-1] if any(printed[0] + printed[-1] == pair for pair in BRACKETS) else printed
    category = CATEGORIES.get(text)
    return {"kind": "part_of_speech" if category else "other", "category": category, "text": text}


def truth_sense(labels: list[str], meaning: str, examples: list[str]) -> dict:
    return {"labels": [truth_label(label) for label in labels], "meaning": meaning, "examples": examples}


def word_book_card(entry: dict) -> dict:
    """A word book entry's truth: its senses in order, and its pronunciation and extras when it prints them."""
    card = {"front": entry["front"],
            "senses": [truth_sense(s["labels"], s["meaning"], s.get("examples", [])) for s in entry["senses"]]}
    if "pronunciation" in entry:
        card["pronunciation"] = entry["pronunciation"]
    if "extras" in entry:
        card["extras"] = entry["extras"]
    return card


def unlabelled(entries: list[dict]) -> list[dict]:
    """[entries] as a page printing no label for any sense."""
    return [{**entry, "senses": [{**sense, "labels": []} for sense in entry["senses"]]} for entry in entries]


# The word-book pages after the pages for prompt v7, each in every style, for prompt v8 (#228):
# the word book with no label printed, against samples 45 to 47 as its labelled control; entries
# with an example under each sense; a Korean dictionary page of semantic classes and
# definitions; and German nouns and verbs with their gender, plural and past forms as extras.
LABEL_PAGES = [
    ("word-book-unlabelled-en-ko", "word-book", True, ("en", "ko"), "Word Book  어휘"),
    ("word-book-examples-en-ko", "word-book-examples", False, ("en", "ko"), "Word Book  어휘"),
    ("dictionary-ko", "dictionary-ko", False, ("ko", "ko"), "국어사전"),
    ("word-book-de-ko", "word-book-de", False, ("de", "ko"), "Wortschatz  어휘"),
]


# The pages for the two-stage eval (#414), each in every hand and distortion after the pages for
# prompt v8: sections of a comparison table or a table whose cells hold bullet lines, and a list,
# with the writer's pen underlines, circles, highlights and stars on their lines.
STRUCTURE_DOCUMENTS = ["ko-states", "ko-respiration", "en-markets", "ko-sentences", "en-organelles"]
TABLE_CONTENT = {"comparison_table", "table"}
# The marks that cover a span of a line, and so a word to blank; a star marks the whole line.
SPAN_MARKS = {"underline", "circle", "highlight"}
HIGHLIGHT_COLOUR = (250, 222, 90)
BULLET = "- "


def line_step(page: Page, size: int) -> float:
    """The height of one row of a marked line: the handwriting face, set larger, needs more."""
    return size * (1.75 if page.handwritten else 1.45)


def wrap_offsets(page: Page, text: str, face: str, size: int, width: float) -> list[tuple[int, str]]:
    """Breaks text at spaces into rows no wider than width, each with the offset of its first
    character in text; fails when one word alone is wider."""
    rows: list[tuple[int, str]] = []
    start, row, at = 0, "", 0
    for word in text.split(" "):
        candidate = word if not row else f"{row} {word}"
        if row and page.width(candidate, face, size) > width:
            rows.append((start, row))
            start, row = at, word
        else:
            row = candidate
        at += len(word) + 1
    rows.append((start, row))
    if any(page.width(part, face, size) > width for _, part in rows):
        raise SystemExit(f"a word of '{text}' is wider than its box")
    return rows


def marked_line(page: Page, xy: tuple[float, float], line: dict, size: int, width: float) -> float:
    """Draws a line wrapped to width, with its pen marks on the spans they cover, and returns the
    height it took."""
    x, y = xy
    face = page.front_face
    step = line_step(page, size)
    rows = wrap_offsets(page, line["text"], face, size, width)

    def overlaps(mark: dict):
        for i, (start, part) in enumerate(rows):
            lo, hi = max(mark["start"], start), min(mark["end"], start + len(part))
            if lo < hi:
                yield (x + page.width(part[:lo - start], face, size), x + page.width(part[:hi - start], face, size),
                       y + i * step)

    for mark in line["marks"]:
        if mark["kind"] == "highlight":
            for x0, x1, top in overlaps(mark):
                page.draw.rectangle([(x0, top + size * 0.2), (x1, top + size * 1.2)], fill=HIGHLIGHT_COLOUR)
    for i, (_, part) in enumerate(rows):
        page.text((x, y + i * step), part, face, size)
    for mark in line["marks"]:
        if mark["kind"] == "underline":
            for x0, x1, top in overlaps(mark):
                page.draw.line([(x0, top + size * 1.25), (x1, top + size * 1.25)], fill=MARK_COLOUR, width=3)
        elif mark["kind"] == "circle":
            for x0, x1, top in overlaps(mark):
                page.draw.ellipse([(x0 - 9, top - size * 0.05), (x1 + 9, top + size * 1.4)], outline=MARK_COLOUR,
                                  width=3)
        elif mark["kind"] == "star":
            star(page, (x - 22, y + size * 0.6), size * 0.5)
    return len(rows) * step


def truth_line(line_id: str, spec: dict) -> dict:
    """A line's truth: its text, each mark's span counted in characters, and the spans a card should
    blank: every span a mark covers and every further one the page names."""
    text = spec["text"]

    def span(part: str) -> dict:
        start = text.find(part)
        if start < 0:
            raise SystemExit(f"'{part}' is not in '{text}'")
        return {"start": start, "end": start + len(part)}

    marks = [{**({"start": 0, "end": len(text)} if mark.get("line") else span(mark["span"])),
              "kind": mark["kind"], "ink": "pen"} for mark in spec.get("marks", [])]
    blanks = [{"start": mark["start"], "end": mark["end"]} for mark in marks if mark["kind"] in SPAN_MARKS]
    blanks += [span(part) for part in spec.get("blanks", [])]
    if not blanks:
        raise SystemExit(f"'{text}' names no blank")
    return {"id": line_id, "text": text, "marks": marks, "blanks": sorted(blanks, key=lambda b: b["start"])}


def truth_sections(doc: dict) -> list[dict]:
    """A structure document's sections as their truth: each table cell's lines, or each list line."""
    sections = []
    for s, section in enumerate(doc["sections"], 1):
        truth = {"title": section["title"], "language": doc["language"], "content_type": section["content_type"]}
        if section["content_type"] in TABLE_CONTENT:
            table = section["table"]
            truth["lines"] = []
            truth["table"] = {"columns": table["columns"], "rows": [
                {"header": row["header"], "cells": [
                    {"lines": [truth_line(f"s{s}-r{r}-c{c}-l{n}", line) for n, line in enumerate(cell, 1)]}
                    for c, cell in enumerate(row["cells"], 1)]}
                for r, row in enumerate(table["rows"], 1)]}
        else:
            truth["lines"] = [truth_line(f"s{s}-l{n}", line) for n, line in enumerate(section["lines"], 1)]
            truth["table"] = None
        sections.append(truth)
    return sections


def section_lines(section: dict) -> list[dict]:
    """Every line of a truth section, a table's row by row and cell by cell."""
    if section["table"] is None:
        return section["lines"]
    return [line for row in section["table"]["rows"] for cell in row["cells"] for line in cell["lines"]]


def structure(page: Page, doc: dict, sections: list[dict]) -> None:
    """A page of sections: each a heading, then a ruled table whose first column names its rows and
    whose cells hold bullet lines, or a list of lines; every line drawn with its marks."""
    scale = doc.get("scale", 1.0)
    size = round(30 * scale)
    page.text((100, 80), doc["title"], page.front_face, 50, (30, 60, 120) if not page.handwritten else None)
    page.draw.line([(100, 160), (PAGE[0] - 100, 160)], fill=(30, 60, 120), width=3)
    y = 190.0
    left, right, pad = 110, PAGE[0] - 100, 12
    for section in sections:
        y += 20
        page.text((left, y), section["title"], page.front_face, round(38 * scale),
                  (30, 60, 120) if not page.handwritten else None)
        y += round(38 * scale) * 1.7
        if section["table"] is None:
            for line in section["lines"]:
                bullet = page.text((left + 20, y), BULLET, page.front_face, size)
                y += marked_line(page, (left + 20 + bullet, y), line, size, right - left - 40 - bullet)
            continue
        table = section["table"]
        header_width = (right - left) * 0.25
        width = (right - left - header_width) / len(table["columns"])
        xs = [left, left + header_width] + [left + header_width + width * (i + 1) for i in range(len(table["columns"]))]
        bullet = page.width(BULLET, page.front_face, size)
        rows = [[None, *table["columns"]]] + [[row["header"], *row["cells"]] for row in table["rows"]]
        for r, row in enumerate(rows):
            heights = []
            for c, cell in enumerate(row):
                inner = xs[c + 1] - xs[c] - 2 * pad
                if cell is None:
                    heights.append(0.0)
                elif isinstance(cell, str):
                    heights.append(len(wrap_offsets(page, cell, page.front_face, size, inner)) * line_step(page, size))
                else:
                    heights.append(sum(len(wrap_offsets(page, line["text"], page.front_face, size, inner - bullet))
                                       for line in cell["lines"]) * line_step(page, size))
            height = max(heights) + 2 * pad
            for c, cell in enumerate(row):
                page.draw.rectangle([(xs[c], y), (xs[c + 1], y + height)], outline=(90, 90, 90), width=2)
                inner = xs[c + 1] - xs[c] - 2 * pad
                if cell is None:
                    continue
                if isinstance(cell, str):
                    if r == 0:
                        page.draw.rectangle([(xs[c] + 2, y + 2), (xs[c + 1] - 2, y + height - 2)], fill=(225, 230, 240))
                    marked_line(page, (xs[c] + pad, y + pad), {"text": cell, "marks": []}, size, inner)
                    continue
                at = y + pad
                for line in cell["lines"]:
                    page.text((xs[c] + pad, at), BULLET, page.front_face, size)
                    at += marked_line(page, (xs[c] + pad + bullet, at), line, size, inner - bullet)
            y += height
    if y > PAGE[1] - 60:
        raise SystemExit(f"the structure page {doc['title']} runs off the page")


# The page for photo import's clear material (ADR 0128), after the pages for the two-stage eval:
# a printed word list, each line its number, the word and its meaning, in print under the mild
# distortion and in print under the harsh one.
NUMBERED_LIST_STYLES = ["print", "harsh"]


def numbered_list(page: Page, entries: list[dict]) -> None:
    """A word list printed one entry a line, as "1. abandon 버리다"."""
    page.text((110, 90), "Word List  단어장", LABEL_FACE, 44, (60, 60, 60))
    y = 210.0
    step = (PAGE[1] - 320) / len(entries)
    for number, entry in enumerate(entries, 1):
        x = 110 + page.text((110, y), f"{number}. {entry['front']}", page.front_face, 38) + 28
        page.text((x, y), entry["back"], page.back_face, 38)
        y += step


def write_numbered_list_samples(index: int, entries: list[dict]) -> int:
    """Writes the numbered word list in each of its styles, numbered after `index`, with its
    truth; returns the last index."""
    for style in NUMBERED_LIST_STYLES:
        index += 1
        rng = np.random.default_rng([SEED, index])
        page = Page(rng, "en-ko", "print")
        numbered_list(page, entries)
        check_coverage(page.covered)
        d = HARSH if style == "harsh" else MILD
        photo = photograph(page.image, rng, d)
        sample = f"{index:02d}-numbered-list-en-ko-{style}"
        photo.save(SAMPLES / f"{sample}.jpg", quality=d.quality, optimize=False)
        truth = {
            "image": f"{sample}.jpg",
            "layout": "numbered-list",
            "languages": {"front": "en", "back": "ko"},
            "hand": "print",
            "distortion": style if style == "harsh" else "mild",
            "fonts": sorted({page.front_face, page.back_face}),
            "cards": [truth_card(entry, "numbered-list") for entry in entries],
        }
        (SAMPLES / f"{sample}.json").write_text(json.dumps(truth, ensure_ascii=False, indent=2) + "\n",
                                                encoding="utf-8")
    return index


# The dense pages, after the numbered word list: French words in two ruled tables of three columns,
# 번호, 앞면 (프랑스어) and 뒷면 (한국어 뜻), as the owner's word list prints them, a word of two
# senses numbering each; a hundred numbered from 101 (#519), and two hundred numbered from 1 in a
# smaller size (#535). Their words have no accent, which the Nanum faces lack.
DENSE_COLUMNS = ("번호", "앞면 (프랑스어)", "뒷면 (한국어 뜻)")
DENSE_WIDTHS = (70, 170, 260)


def dense_back(senses: list[str]) -> str:
    """An entry's back as printed: its one sense, or each numbered, as "1. 땅  2. 지구"."""
    return senses[0] if len(senses) == 1 else "  ".join(f"{n}. {s}" for n, s in enumerate(senses, 1))


def dense_list(page: Page, entries: list[dict], first: int, size: int) -> None:
    """A title, then the entries numbered from `first` in two tables side by side, each a header row
    and half the entries, in text of `size`."""
    page.text((100, 70), f"프랑스어 단어 {first}-{first + len(entries) - 1}",
              LABEL_FACE, 40, (30, 60, 120))
    half = (len(entries) + 1) // 2
    top = 160
    row = (PAGE[1] - top - 70) / (half + 1)
    for t, left in enumerate((100, 100 + sum(DENSE_WIDTHS) + 40)):
        rows = [DENSE_COLUMNS] + [(str(first + t * half + i), e["front"], dense_back(e["senses"]))
                                  for i, e in enumerate(entries[t * half:(t + 1) * half])]
        for r, cells in enumerate(rows):
            y = top + r * row
            x = left
            for c, (cell, width) in enumerate(zip(cells, DENSE_WIDTHS)):
                if r == 0:
                    page.draw.rectangle([(x, y), (x + width, y + row)], fill=(225, 230, 240))
                page.draw.rectangle([(x, y), (x + width, y + row)], outline=(90, 90, 90), width=1)
                face = page.front_face if c == 1 and r > 0 else page.back_face
                if page.width(cell, face, size) > width - 16:
                    raise SystemExit(f"'{cell}' is wider than its cell")
                page.text((x + 8, y + (row - size) / 2 - 2), cell, face, size)
                x += width


def write_dense_list_sample(index: int, entries: list[dict], first: int, size: int,
                            name: str) -> int:
    """Writes a dense French word list numbered from `first`, in text of `size`, in print under the
    mild distortion, as sample `name` numbered after `index`, with its truth; returns its index."""
    index += 1
    rng = np.random.default_rng([SEED, index])
    page = Page(rng, "en-ko", "print")
    dense_list(page, entries, first, size)
    check_coverage(page.covered)
    photo = photograph(page.image, rng, MILD)
    sample = f"{index:02d}-{name}-fr-ko-print"
    photo.save(SAMPLES / f"{sample}.jpg", quality=MILD.quality, optimize=False)
    truth = {
        "image": f"{sample}.jpg",
        "layout": "dense-list",
        "languages": {"front": "fr", "back": "ko"},
        "hand": "print",
        "distortion": "mild",
        "fonts": sorted({page.front_face, page.back_face, LABEL_FACE}),
        "cards": [{"front": e["front"], "senses": [truth_sense([], s, []) for s in e["senses"]]}
                  for e in entries],
    }
    (SAMPLES / f"{sample}.json").write_text(json.dumps(truth, ensure_ascii=False, indent=2) + "\n",
                                            encoding="utf-8")
    return index


def write_structure_samples(index: int, name: str, doc: dict) -> int:
    """Writes the structure page `name` in every hand and distortion, numbered after `index`, with
    its truth: its sections, its lines as notes facts, each fact the spans its line should blank,
    and every line it prints; returns the last index."""
    sections = truth_sections(doc)
    lines = [line for section in sections for line in section_lines(section)]
    facts = [{"id": line["id"], "step": 1 if line["marks"] else 2,
              "terms": [line["text"][b["start"]:b["end"]] for b in line["blanks"]]} for line in lines]
    printed = [doc["title"]]
    for section in sections:
        printed.append(section["title"])
        if section["table"] is not None:
            printed += section["table"]["columns"]
            for row in section["table"]["rows"]:
                printed.append(row["header"])
                printed += [line["text"] for cell in row["cells"] for line in cell["lines"]]
        else:
            printed += [line["text"] for line in section["lines"]]
    for hand in NOTE_HANDS:
        for distortion in NOTE_DISTORTIONS:
            index += 1
            rng = np.random.default_rng([SEED, index])
            face = NOTE_FACES[hand]
            page = Page(rng, "", hand, (face, face))
            structure(page, doc, sections)
            check_coverage(page.covered)
            d = HARSH if distortion == "harsh" else MILD
            photo = photograph(page.image, rng, d)
            sample = f"{index:02d}-structure-{name}-{hand}-{distortion}"
            photo.save(SAMPLES / f"{sample}.jpg", quality=d.quality, optimize=False)
            truth = {
                "image": f"{sample}.jpg",
                "kind": "notes",
                "layout": "structure",
                "languages": {"front": doc["language"], "back": doc["language"]},
                "hand": hand,
                "distortion": distortion,
                "fonts": [face],
                "facts": facts,
                "lines": printed,
                "sections": sections,
            }
            (SAMPLES / f"{sample}.json").write_text(json.dumps(truth, ensure_ascii=False, indent=2) + "\n",
                                                    encoding="utf-8")
    return index


RENDER = {"two-column": two_column, "bilingual-table": bilingual_table, "dictionary": dictionary, "glossary": glossary}
COUNTS = {"two-column": (12, 16), "bilingual-table": (10, 14), "dictionary": (6, 9), "glossary": (14, 20)}


def perspective_coefficients(source: list[tuple[float, float]], target: list[tuple[float, float]]) -> list[float]:
    """The coefficients PIL's PERSPECTIVE transform takes to map each target corner to its source."""
    rows, values = [], []
    for (x, y), (u, v) in zip(target, source):
        rows.append([x, y, 1, 0, 0, 0, -u * x, -u * y])
        rows.append([0, 0, 0, x, y, 1, -v * x, -v * y])
        values += [u, v]
    return list(np.linalg.solve(np.array(rows, dtype=float), np.array(values, dtype=float)))


def photograph(page: Image.Image, rng: np.random.Generator, d: Distortion) -> Image.Image:
    """The page lying on a desk, shot at an angle in uneven light, then saved as a phone would."""
    w, h = page.size
    margin = round(0.18 * max(w, h))
    desk = np.clip(rng.normal((120, 100, 80), 12, (h + 2 * margin, w + 2 * margin, 3)), 0, 255)
    canvas = Image.fromarray(desk.astype(np.uint8))
    canvas.paste(page, (margin, margin))

    cw, ch = canvas.size
    corners = [(0, 0), (cw, 0), (cw, ch), (0, ch)]
    shifted = [(x + rng.uniform(-1, 1) * d.perspective * cw, y + rng.uniform(-1, 1) * d.perspective * ch)
               for x, y in corners]
    canvas = canvas.transform(canvas.size, Image.Transform.PERSPECTIVE,
                              perspective_coefficients(corners, shifted), Image.Resampling.BICUBIC,
                              fillcolor=(110, 92, 74))
    canvas = canvas.rotate(rng.uniform(-d.rotation, d.rotation), Image.Resampling.BICUBIC,
                           fillcolor=(110, 92, 74))

    pixels = np.asarray(canvas, dtype=float)
    angle = rng.uniform(0, 2 * np.pi)
    ys, xs = np.mgrid[0:ch, 0:cw]
    along = (np.cos(angle) * xs / cw + np.sin(angle) * ys / ch)
    along = (along - along.min()) / (along.max() - along.min())
    light = 1.0 - (1.0 - d.shadow) * along
    pixels = pixels * light[..., None]
    canvas = Image.fromarray(np.clip(pixels, 0, 255).astype(np.uint8))
    canvas = canvas.filter(ImageFilter.GaussianBlur(d.blur))

    scale = LONG_SIDE / max(canvas.size)
    canvas = canvas.resize((round(cw * scale), round(ch * scale)), Image.Resampling.LANCZOS)
    noisy = np.asarray(canvas, dtype=float) + rng.normal(0, d.noise, (canvas.size[1], canvas.size[0], 3))
    return Image.fromarray(np.clip(noisy, 0, 255).astype(np.uint8))


def truth_card(entry: dict, layout: str) -> dict:
    """An entry's one sense as its page prints it: only the dictionary layout prints a part of speech and examples."""
    printed = layout == "dictionary"
    card = {"front": entry["front"], "senses": [truth_sense([entry["pos"]] if printed else [], entry["back"], [])]}
    if printed and "example" in entry:
        card["examples"] = [entry["example"]]
    return card


def check_coverage(covered: dict[str, set[str]]) -> None:
    """Fails when a font lacks a character drawn in it, which it would draw as an empty box."""
    for face, chars in covered.items():
        cmap = TTFont(FONTS / face).getBestCmap()
        missing = sorted(c for c in chars if not c.isspace() and ord(c) not in cmap)
        if missing:
            raise SystemExit(f"{face} has no glyph for: {''.join(missing)}")


def write_notes_samples(index: int, name: str, doc: dict) -> int:
    """Writes the notes page `name` in every hand and distortion, numbered after `index`, with its
    truth: its facts and lines, and the table and cloze blanks it names; returns the last index."""
    language = name.split("-")[0]
    for hand in NOTE_HANDS:
        for distortion in NOTE_DISTORTIONS:
            index += 1
            rng = np.random.default_rng([SEED, index])
            face = NOTE_FACES[hand]
            page = Page(rng, "", hand, (face, face))
            notes(page, doc)
            check_coverage(page.covered)
            d = HARSH if distortion == "harsh" else MILD
            photo = photograph(page.image, rng, d)
            sample = f"{index:02d}-notes-{name}-{hand}-{distortion}"
            photo.save(SAMPLES / f"{sample}.jpg", quality=d.quality, optimize=False)
            truth = {
                "image": f"{sample}.jpg",
                "kind": "notes",
                "layout": "notes",
                "languages": {"front": language, "back": language},
                "hand": hand,
                "distortion": distortion,
                "fonts": [face],
                "facts": doc["facts"],
                "lines": [doc["title"]] + [line["text"] for line in doc["lines"]],
            }
            for key in ("tableBlanks", "clozeBlanks"):
                if key in doc:
                    truth[key] = doc[key]
            (SAMPLES / f"{sample}.json").write_text(json.dumps(truth, ensure_ascii=False, indent=2) + "\n",
                                                    encoding="utf-8")
    return index


def write_word_book_samples(index: int, name: str, entries: list[dict], languages: tuple[str, str],
                            title: str) -> int:
    """Writes the word-book page `name` of `entries` in every style, numbered after `index`, with
    its truth; returns the last index."""
    for style in STYLES:
        index += 1
        rng = np.random.default_rng([SEED, index])
        hand = style if style != "harsh" else ("print", "handwriting")[index % 2]
        page = Page(rng, "en-ko", hand)
        word_book(page, entries, title)
        check_coverage(page.covered)
        d = HARSH if style == "harsh" else MILD
        photo = photograph(page.image, rng, d)
        sample = f"{index:02d}-{name}-{style}"
        photo.save(SAMPLES / f"{sample}.jpg", quality=d.quality, optimize=False)
        truth = {
            "image": f"{sample}.jpg",
            "layout": "word-book",
            "languages": dict(zip(("front", "back"), languages)),
            "hand": hand,
            "distortion": style if style == "harsh" else "mild",
            "fonts": sorted({page.front_face, page.back_face, LABEL_FACE}),
            "cards": [word_book_card(entry) for entry in entries],
        }
        (SAMPLES / f"{sample}.json").write_text(json.dumps(truth, ensure_ascii=False, indent=2) + "\n",
                                                encoding="utf-8")
    return index


def main() -> None:
    vocabulary = json.loads((HERE / "vocabulary.json").read_text(encoding="utf-8"))
    SAMPLES.mkdir(exist_ok=True)
    index = 0
    for layout in LAYOUTS:
        for pair in PAIRS:
            for style in STYLES:
                index += 1
                rng = np.random.default_rng([SEED, index])
                hand = style if style != "harsh" else ("print", "handwriting")[index % 2]
                low, high = COUNTS[layout]
                words = vocabulary[pair]
                picked = [words[i] for i in rng.choice(len(words), int(rng.integers(low, high + 1)), replace=False)]
                page = Page(rng, pair, hand)
                RENDER[layout](page, picked, pair)
                check_coverage(page.covered)
                photo = photograph(page.image, rng, HARSH if style == "harsh" else MILD)

                name = f"{index:02d}-{layout}-{pair}-{style}"
                photo.save(SAMPLES / f"{name}.jpg", quality=(HARSH if style == "harsh" else MILD).quality,
                           optimize=False)
                truth = {
                    "image": f"{name}.jpg",
                    "layout": layout,
                    "languages": dict(zip(("front", "back"), pair.split("-"))),
                    "hand": hand,
                    "distortion": style if style == "harsh" else "mild",
                    "fonts": sorted({page.front_face, page.back_face}),
                    "cards": [truth_card(e, layout) for e in picked],
                }
                (SAMPLES / f"{name}.json").write_text(json.dumps(truth, ensure_ascii=False, indent=2) + "\n",
                                                      encoding="utf-8")
    documents = json.loads((HERE / "notes.json").read_text(encoding="utf-8"))
    for language in NOTE_LANGUAGES:
        for hand in NOTE_HANDS:
            for distortion in NOTE_DISTORTIONS:
                index += 1
                rng = np.random.default_rng([SEED, index])
                face = NOTE_FACES[hand]
                page = Page(rng, "", hand, (face, face))
                doc = documents[language]
                notes(page, doc)
                check_coverage(page.covered)
                d = HARSH if distortion == "harsh" else MILD
                photo = photograph(page.image, rng, d)
                name = f"{index:02d}-notes-{language}-{hand}-{distortion}"
                photo.save(SAMPLES / f"{name}.jpg", quality=d.quality, optimize=False)
                truth = {
                    "image": f"{name}.jpg",
                    "kind": "notes",
                    "layout": "notes",
                    "languages": {"front": language, "back": language},
                    "hand": hand,
                    "distortion": distortion,
                    "fonts": [face],
                    "facts": doc["facts"],
                    "lines": [doc["title"]] + [line["text"] for line in doc["lines"]],
                }
                (SAMPLES / f"{name}.json").write_text(json.dumps(truth, ensure_ascii=False, indent=2) + "\n",
                                                      encoding="utf-8")
    for name in DENSE_DOCUMENTS:
        index = write_notes_samples(index, name, documents[name])
    # The word book pages, after every page above: several labelled senses an entry, and a
    # pronunciation per part of speech.
    index = write_word_book_samples(index, "word-book-en-ko", vocabulary["word-book"], ("en", "ko"),
                                    "Word Book  어휘")
    for name in BLANK_DOCUMENTS:
        index = write_notes_samples(index, name, documents[name])
    for name, key, strip, languages, title in LABEL_PAGES:
        entries = unlabelled(vocabulary[key]) if strip else vocabulary[key]
        index = write_word_book_samples(index, name, entries, languages, title)
    structures = json.loads((HERE / "structure.json").read_text(encoding="utf-8"))
    for name in STRUCTURE_DOCUMENTS:
        index = write_structure_samples(index, name, structures[name])
    index = write_numbered_list_samples(index, vocabulary["numbered-list"])
    index = write_dense_list_sample(index, vocabulary["dense-list-fr"], 101, 19, "dense-list")
    index = write_dense_list_sample(index, vocabulary["dense-list-fr-first"] + vocabulary["dense-list-fr"],
                                    1, 12, "dense-list-200")
    print(f"wrote {index} samples to {SAMPLES.relative_to(HERE.parent.parent)}/ from seed {SEED}")


if __name__ == "__main__":
    main()
