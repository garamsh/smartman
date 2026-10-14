# Sample provenance

Where each file of the extract-cards eval's sample set comes from, and under what licence.

## Generated samples

- `NN-<layout>-<pair>-<style>.jpg` and the `.json` beside it, 24 pairs, are written by `tools/eval/generate.py` with seed `20261015`: `uv run --locked --script tools/eval/generate.py` from the repository root.
- Each `.json` is the ground truth of its image: the cards the page shows, its layout, languages, hand, distortion and fonts.
- They are synthetic. Each is a page rendered in one of four layouts (two-column list, bilingual table, dictionary entries, textbook glossary), for English to Korean or Japanese to Korean, then distorted by perspective, rotation, uneven light, blur and JPEG noise. None is a photo taken with a phone.
- Two runs of the generator on macOS 26 (arm64) with the locked dependencies wrote byte-identical files.
- The generator's dependencies are pinned in its header and locked in `tools/eval/generate.py.lock`. No bot proposes their bump; whoever regenerates the samples moves them, with `uv lock --script tools/eval/generate.py --upgrade`, and commits the new samples in the same change.

## Vocabulary

- `tools/eval/vocabulary.json` was written for this project: 90 English and 90 Japanese entries with their Korean meanings, parts of speech, and English example sentences. It is licensed with the repository.

## Fonts

From `google/fonts` at commit `67bc647ce1910e92f461bcc82aae30f21d21a9cc`, each under the SIL Open Font License 1.1, whose text sits beside it in `tools/eval/fonts/`:

| File | Source path | Licence file | SHA-256 |
|---|---|---|---|
| `NanumGothic-Regular.ttf` | `ofl/nanumgothic/` | `NanumGothic-Regular-OFL.txt` | `76f45ef4a6bcff344c837c95a7dcc26e017e38b5846d5ae0cdcb5b86be2e2d31` |
| `NanumPenScript-Regular.ttf` | `ofl/nanumpenscript/` | `NanumPenScript-Regular-OFL.txt` | `6f0d1ab29c7894010dc88831fb7a0a51edb79136e450344183de5b1a8b52bd43` |
| `SawarabiGothic-Regular.ttf` | `ofl/sawarabigothic/` | `SawarabiGothic-Regular-OFL.txt` | `04f2f9111bb69cb8d3706c27b44879c2c0fac593a11edf5cfe8cec1efc92c789` |
| `Yomogi-Regular.ttf` | `ofl/yomogi/` | `Yomogi-Regular-OFL.txt` | `ec280f473a03187292905618f24fdb08a6dcbf8620b52637e3b589fe745259b9` |

- Nanum Pen Script and Yomogi are handwriting faces; the others are print faces.

## Adding real photos

- A real photo goes in this folder as `NN-<description>.jpg` with a `.json` ground truth of the same shape, at least `image` and `cards`, and a line in this file naming who took it and under what licence.
- `generate.py` overwrites only the 24 names it writes, so a real photo keeps any other name; numbering it from 25 keeps the folder in order.
