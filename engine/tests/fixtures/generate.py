# /// script
# requires-python = ">=3.10"
# dependencies = ["fsrs==6.3.2"]
# ///
"""Writes reference.json: py-fsrs 6.3.2 run over fixed rating sequences.

Regenerate from the repository root with:

    uv run --locked --script engine/tests/fixtures/generate.py

The scheduler matches the engine's configuration: default parameters, desired
retention 0.9, no learning or relearning steps. "sequences" are run without
fuzzing; "fuzzed_sequences" run the same steps with fuzzing, its draws taken from
a seeded source, and record the factor each review drew.
"""

import json
import random
from datetime import datetime, timedelta, timezone
from importlib.metadata import version
from pathlib import Path

import fsrs.scheduler
from fsrs import Card, Rating, Scheduler

START = datetime(2026, 1, 1, tzinfo=timezone.utc)
DUE = "due"
MINUTE = 60
HOUR = 60 * MINUTE
DAY = 24 * HOUR

A, H, G, E = Rating.Again, Rating.Hard, Rating.Good, Rating.Easy

# Each step is (rating, delay): delay is DUE for a review at the scheduled due
# time, or seconds after the previous review. The first delay is ignored.
SEQUENCES = {
    "first-again": [(A, 0)],
    "first-hard": [(H, 0)],
    "first-good": [(G, 0)],
    "first-easy": [(E, 0)],
    "good-on-due": [(G, DUE)] * 10,
    "again-on-due": [(A, DUE)] * 8,
    "hard-on-due": [(H, DUE)] * 8,
    "easy-on-due-to-maximum-interval": [(E, DUE)] * 16,
    "know-dont-know-alternating": [(G, DUE), (A, DUE)] * 5,
    "lapse-and-recover": [(G, DUE)] * 4 + [(A, DUE)] + [(G, DUE)] * 4,
    "hard-easy-mix": [(H, 0), (E, DUE), (H, DUE), (E, DUE), (G, DUE), (H, DUE)],
    "same-day-relearning-from-new": [
        (A, 0),
        (A, 10 * MINUTE),
        (G, 10 * MINUTE),
        (G, DAY),
        (G, DUE),
    ],
    "same-day-again-to-minimum-stability": [(A, 0)] + [(A, MINUTE)] * 8 + [(G, DAY)],
    "same-day-after-review": [
        (G, 0),
        (G, DUE),
        (G, HOUR),
        (A, HOUR),
        (G, 23 * HOUR),
        (G, DUE),
    ],
    "overdue": [(G, 0), (G, 30 * DAY), (G, 200 * DAY), (A, 730 * DAY), (G, DUE)],
    "lapse-long-overdue-with-low-stability": [(A, 0), (A, 3650 * DAY), (G, DUE)],
    "lapse-long-overdue-after-good": [(G, 0), (A, 400 * DAY), (G, DUE)],
    "early": [(G, 0), (G, DUE), (G, DAY), (G, DAY + 12 * HOUR), (G, DUE)],
    "two-button-session": [
        (A, 0),
        (A, 5 * MINUTE),
        (G, 5 * MINUTE),
        (G, DAY),
        (G, DUE),
        (A, DUE),
        (G, 10 * MINUTE),
        (G, DUE),
    ],
}


# Each sequence is fuzzed once with each of these seeds.
FUZZ_SEEDS = (1, 2)


class Draws:
    """Stands in for the `random()` py-fsrs fuzzes with: seeded, and keeping each draw."""

    def __init__(self, seed):
        self._source = random.Random(seed)
        self.drawn = []

    def __call__(self):
        value = self._source.random()
        self.drawn.append(value)
        return value


def run(steps, seed=None):
    draws = None
    if seed is not None:
        draws = Draws(seed)
        # `Scheduler._get_fuzzed_interval` calls the `random` its module imported.
        fsrs.scheduler.random = draws
    scheduler = Scheduler(
        learning_steps=(), relearning_steps=(), enable_fuzzing=seed is not None
    )
    card = Card(card_id=1, due=START)
    at = START
    reviews = []
    for index, (rating, delay) in enumerate(steps):
        if index > 0:
            at = card.due if delay == DUE else at + timedelta(seconds=delay)
        retrievability = (
            scheduler.get_card_retrievability(card, current_datetime=at)
            if card.last_review is not None
            else None
        )
        drawn_before = len(draws.drawn) if draws else 0
        card, _ = scheduler.review_card(card, rating, review_datetime=at)
        step = {}
        if draws:
            # py-fsrs draws once for an interval it fuzzes and not at all otherwise.
            step["fuzz_factor"] = (
                draws.drawn[-1] if len(draws.drawn) > drawn_before else None
            )
        reviews.append(
            step
            | {
                "rating": int(rating),
                "at": int(at.timestamp()),
                "retrievability": retrievability,
                "stability": card.stability,
                "difficulty": card.difficulty,
                "interval_days": (card.due - at) // timedelta(days=1),
                "due": int(card.due.timestamp()),
            }
        )
    return reviews


def main():
    fixtures = {
        "generator": f"py-fsrs {version('fsrs')}",
        "sequences": [
            {"name": name, "reviews": run(steps)} for name, steps in SEQUENCES.items()
        ],
        "fuzzed_sequences": [
            {"name": name, "seed": seed, "reviews": run(steps, seed)}
            for name, steps in SEQUENCES.items()
            for seed in FUZZ_SEEDS
        ],
    }
    out = Path(__file__).with_name("reference.json")
    out.write_text(json.dumps(fixtures, indent=2) + "\n")


if __name__ == "__main__":
    main()
