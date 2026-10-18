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
with the locked dependencies writes the same files. The cards a vocabulary page shows, with the
parts of speech and examples it prints, are written beside its image as the ground truth; a notes
page's truth is the rules and exceptions it teaches, each with its step, the terms that cover it
and the worked examples the page prints for it, and every line it prints, from tools/eval/notes.json.
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
# many small rules, worked examples and marked exceptions, and a page with a classification
# table and the writer's own additions in pen.
DENSE_DOCUMENTS = ["ko-grammar", "ko-auxiliary"]
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
    addition in pen, and an `aside` is one written beside the heading above it."""
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
    """An entry's fields as its page prints them: only the dictionary layout prints a part of speech and examples."""
    card = {"front": entry["front"], "meaning": entry["back"]}
    if layout == "dictionary":
        card["partOfSpeech"] = entry["pos"]
        if "example" in entry:
            card["examples"] = [entry["example"]]
    return card


def check_coverage(covered: dict[str, set[str]]) -> None:
    """Fails when a font lacks a character drawn in it, which it would draw as an empty box."""
    for face, chars in covered.items():
        cmap = TTFont(FONTS / face).getBestCmap()
        missing = sorted(c for c in chars if not c.isspace() and ord(c) not in cmap)
        if missing:
            raise SystemExit(f"{face} has no glyph for: {''.join(missing)}")


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
        doc = documents[name]
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
                (SAMPLES / f"{sample}.json").write_text(json.dumps(truth, ensure_ascii=False, indent=2) + "\n",
                                                        encoding="utf-8")
    print(f"wrote {index} samples to {SAMPLES.relative_to(HERE.parent.parent)}/ from seed {SEED}")


if __name__ == "__main__":
    main()
