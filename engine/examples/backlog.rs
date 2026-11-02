//! Simulates a review backlog through the engine to choose the study queue's order, its
//! bucket size and when new cards pause (issue #53). Run from `engine/`:
//!
//! `cargo run --locked --release --example backlog`
//!
//! It prints the Markdown tables ADR 0025 records. Every draw comes from one generator per
//! run, seeded from `SEEDS`, so the output is the same on every host.
//!
//! The model:
//! - a user studies every day for `WARM_UP_DAYS`, taking `NEW_PER_DAY` new cards and every
//!   due card, then skips `gap` days, then studies for a horizon of days with a daily budget
//!   of reviews, a re-show included;
//! - a reviewed card is recalled with the probability the engine's retrievability gives at
//!   that moment, a new card with `FIRST_RECALL`; recall answers "Know" (Good), else
//!   "Don't know" (Again), which re-shows the card later in the session, where it is recalled
//!   (the engine gives a retrievability of 1 within the day) if the budget allows;
//! - every review draws a fuzz factor, as the app does.

use knowno_engine::{FuzzFactor, MemoryState, Rating, Timestamp, review};

const DAY: i64 = 86_400;
/// When each day's session starts: 09:00.
const SESSION_START: i64 = 9 * 3_600;
/// How long after a "Don't know" its re-show is answered.
const RESHOW_AFTER: i64 = 600;
const WARM_UP_DAYS: i64 = 120;
const NEW_PER_DAY: usize = 20;
const FIRST_RECALL: f64 = 0.5;
const SEEDS: std::ops::RangeInclusive<u64> = 1..=20;

/// SplitMix64: small, seedable, and the same on every host.
struct Rng(u64);

impl Rng {
    fn next_u64(&mut self) -> u64 {
        self.0 = self.0.wrapping_add(0x9E37_79B9_7F4A_7C15);
        let mut z = self.0;
        z = (z ^ (z >> 30)).wrapping_mul(0xBF58_476D_1CE4_E5B9);
        z = (z ^ (z >> 27)).wrapping_mul(0x94D0_49BB_1331_11EB);
        z ^ (z >> 31)
    }

    /// From 0, inclusive, to 1, exclusive.
    fn next_f64(&mut self) -> f64 {
        (self.next_u64() >> 11) as f64 / (1_u64 << 53) as f64
    }

    /// From 0 to `n`, `n` excluded.
    fn below(&mut self, n: usize) -> usize {
        (self.next_f64() * n as f64) as usize
    }

    fn shuffle<T>(&mut self, items: &mut [T]) {
        for place in 0..items.len().saturating_sub(1) {
            let pick = place + self.below(items.len() - place);
            items.swap(place, pick);
        }
    }
}

#[derive(Clone, Copy, PartialEq)]
enum Order {
    /// Today's queue: due cards in a uniformly random order.
    Shuffle,
    /// Lowest retrievability first: the most forgotten.
    RetrievabilityAscending,
    /// Highest retrievability first: the most likely still remembered.
    RetrievabilityDescending,
    /// Earliest due first.
    DueAscending,
}

impl Order {
    fn name(self) -> &'static str {
        match self {
            Order::Shuffle => "shuffle (today)",
            Order::RetrievabilityAscending => "retrievability ascending",
            Order::RetrievabilityDescending => "retrievability descending",
            Order::DueAscending => "due date ascending",
        }
    }
}

#[derive(Clone, Copy)]
struct Policy {
    /// The order of the due cards while in backlog; out of backlog they are shuffled.
    order: Order,
    /// Consecutive cards of the order shuffled together; 1 is the strict order.
    bucket: usize,
    backlog: Backlog,
    /// Whether a session in backlog takes no new card; otherwise it takes `NEW_PER_DAY`, each
    /// at a random place among the ordered due cards.
    pause_new: bool,
}

/// When a session is in backlog: its due cards ordered, and no new card.
#[derive(Clone, Copy)]
enum Backlog {
    Never,
    Always,
    /// When more than this many days of reviews are due: the due count over the daily load.
    Over(f64),
}

#[derive(Clone, Copy)]
struct Scenario {
    gap: i64,
    budget: usize,
    horizon: i64,
}

#[derive(Clone, Copy)]
struct Card {
    state: MemoryState,
    due: Timestamp,
    /// Whether the card was reviewed before the gap.
    old: bool,
}

#[derive(Default, Clone, Copy)]
struct Outcome {
    /// The sum of retrievability over every reviewed card at the horizon's end.
    retained: f64,
    /// The same over the cards reviewed before the gap.
    retained_old: f64,
    /// Reviews in the horizon, re-shows included.
    reviews: f64,
    /// New cards introduced in the horizon.
    introduced: f64,
    /// Days of the horizon whose queue the session did not finish.
    unfinished_days: f64,
    /// Days of the horizon in backlog.
    backlog_days: f64,
    /// The mean, over the horizon's days, of the sum of retrievability at the session's start.
    mean_retained: f64,
    /// The same over the cards reviewed before the gap.
    mean_retained_old: f64,
}

impl Outcome {
    fn add(&mut self, other: &Outcome) {
        self.retained += other.retained;
        self.retained_old += other.retained_old;
        self.reviews += other.reviews;
        self.introduced += other.introduced;
        self.unfinished_days += other.unfinished_days;
        self.backlog_days += other.backlog_days;
        self.mean_retained += other.mean_retained;
        self.mean_retained_old += other.mean_retained_old;
    }

    fn scaled(mut self, by: f64) -> Outcome {
        self.retained *= by;
        self.retained_old *= by;
        self.reviews *= by;
        self.introduced *= by;
        self.unfinished_days *= by;
        self.backlog_days *= by;
        self.mean_retained *= by;
        self.mean_retained_old *= by;
        self
    }
}

fn retrievability(card: &Card, now: Timestamp) -> f64 {
    card.state
        .retrievability(now)
        .expect("a session never runs before a card's last review")
}

fn draw_fuzz(rng: &mut Rng) -> Option<FuzzFactor> {
    Some(FuzzFactor::new(rng.next_f64()).expect("next_f64 is in [0, 1)"))
}

/// The number of reviews a day the collection asks for at its current intervals.
fn daily_load(cards: &[Card]) -> f64 {
    cards
        .iter()
        .map(|card| {
            let interval = (card.due.0 - card.state.last_review().0) as f64 / DAY as f64;
            1.0 / interval.max(1.0)
        })
        .sum()
}

struct Simulation {
    rng: Rng,
    cards: Vec<Card>,
}

impl Simulation {
    /// Answers one card at `now`: `None` for a new one. Returns the reviews spent.
    fn answer(&mut self, card: Option<usize>, now: Timestamp, budget: usize, old: bool) -> usize {
        let recall = match card {
            Some(index) => retrievability(&self.cards[index], now),
            None => FIRST_RECALL,
        };
        let rating = if self.rng.next_f64() < recall {
            Rating::Good
        } else {
            Rating::Again
        };
        let state = card.map(|index| self.cards[index].state);
        let factor = draw_fuzz(&mut self.rng);
        let (state, due) = review(state.as_ref(), rating, now, factor).expect("a valid review");
        let index = match card {
            Some(index) => {
                self.cards[index].state = state;
                self.cards[index].due = due;
                index
            }
            None => {
                self.cards.push(Card { state, due, old });
                self.cards.len() - 1
            }
        };
        if rating == Rating::Good || budget < 2 {
            return 1;
        }
        let later = Timestamp(now.0 + RESHOW_AFTER);
        let factor = draw_fuzz(&mut self.rng);
        let (state, due) = review(Some(&self.cards[index].state), Rating::Good, later, factor)
            .expect("a valid re-show");
        self.cards[index].state = state;
        self.cards[index].due = due;
        2
    }

    /// One day's session. Returns (reviews, new cards, finished, in backlog).
    fn session(
        &mut self,
        day: i64,
        budget: Option<usize>,
        policy: &Policy,
        old: bool,
    ) -> (usize, usize, bool, bool) {
        let now = Timestamp(day * DAY + SESSION_START);
        let mut due: Vec<usize> = (0..self.cards.len())
            .filter(|&index| self.cards[index].due <= now)
            .collect();
        let backlog = match policy.backlog {
            Backlog::Never => false,
            Backlog::Always => true,
            Backlog::Over(days) => due.len() as f64 > days * daily_load(&self.cards),
        };
        let fresh = if backlog && policy.pause_new {
            0
        } else {
            NEW_PER_DAY
        };
        // `None` stands for a new card.
        let mut queue: Vec<Option<usize>> = if backlog {
            match policy.order {
                Order::Shuffle => self.rng.shuffle(&mut due),
                order => {
                    self.sort(&mut due, order, now);
                    for bucket in due.chunks_mut(policy.bucket.max(1)) {
                        self.rng.shuffle(bucket);
                    }
                }
            }
            let mut queue: Vec<Option<usize>> = due.into_iter().map(Some).collect();
            for _ in 0..fresh {
                let at = self.rng.below(queue.len() + 1);
                queue.insert(at, None);
            }
            queue
        } else {
            let mut queue: Vec<Option<usize>> = due.into_iter().map(Some).collect();
            queue.extend(std::iter::repeat_n(None, fresh));
            self.rng.shuffle(&mut queue);
            queue
        };
        let mut left = budget.unwrap_or(usize::MAX);
        let mut spent = 0;
        let mut introduced = 0;
        let mut finished = true;
        for card in queue.drain(..) {
            if left == 0 {
                finished = false;
                break;
            }
            let used = self.answer(card, now, left, old);
            left -= used;
            spent += used;
            if card.is_none() {
                introduced += 1;
            }
        }
        (spent, introduced, finished, backlog)
    }

    fn sort(&self, due: &mut [usize], order: Order, now: Timestamp) {
        let cards = &self.cards;
        let r = |index: &usize| retrievability(&cards[*index], now);
        match order {
            Order::Shuffle => {}
            Order::RetrievabilityAscending => due.sort_by(|a, b| r(a).total_cmp(&r(b))),
            Order::RetrievabilityDescending => due.sort_by(|a, b| r(b).total_cmp(&r(a))),
            Order::DueAscending => due.sort_by_key(|index| cards[*index].due),
        }
    }

    fn retained(&self, at: Timestamp, only_old: bool) -> f64 {
        self.cards
            .iter()
            .filter(|card| card.old || !only_old)
            .map(|card| retrievability(card, at))
            .sum()
    }
}

/// The user who studied every day: the collection the gap starts from.
fn warm_up(seed: u64) -> Simulation {
    let mut sim = Simulation {
        rng: Rng(seed),
        cards: Vec::new(),
    };
    let today = Policy {
        order: Order::Shuffle,
        bucket: 1,
        backlog: Backlog::Never,
        pause_new: true,
    };
    for day in 0..WARM_UP_DAYS {
        sim.session(day, None, &today, true);
    }
    sim
}

fn run(seed: u64, scenario: Scenario, policy: &Policy) -> Outcome {
    let mut sim = warm_up(seed);
    let first = WARM_UP_DAYS + scenario.gap;
    let mut outcome = Outcome::default();
    for day in first..first + scenario.horizon {
        let start = Timestamp(day * DAY + SESSION_START);
        outcome.mean_retained += sim.retained(start, false) / scenario.horizon as f64;
        outcome.mean_retained_old += sim.retained(start, true) / scenario.horizon as f64;
        let (reviews, introduced, finished, backlog) =
            sim.session(day, Some(scenario.budget), policy, false);
        outcome.reviews += reviews as f64;
        outcome.introduced += introduced as f64;
        outcome.unfinished_days += f64::from(u8::from(!finished));
        outcome.backlog_days += f64::from(u8::from(backlog));
    }
    let end = Timestamp((first + scenario.horizon) * DAY + SESSION_START);
    outcome.retained = sim.retained(end, false);
    outcome.retained_old = sim.retained(end, true);
    outcome
}

/// The mean, over every seed, of how far `ahead` leads `behind` on the cards from before the
/// gap, run by run with the same seed, with its standard error: over the horizon, and at its end.
fn paired_lead(scenario: Scenario, ahead: &Policy, behind: &Policy) -> [(f64, f64); 2] {
    let leads: Vec<(f64, f64)> = SEEDS
        .map(|seed| {
            let (a, b) = (run(seed, scenario, ahead), run(seed, scenario, behind));
            (
                a.mean_retained_old - b.mean_retained_old,
                a.retained_old - b.retained_old,
            )
        })
        .collect();
    let count = leads.len() as f64;
    let stats = |value: fn(&(f64, f64)) -> f64| {
        let mean = leads.iter().map(value).sum::<f64>() / count;
        let variance = leads
            .iter()
            .map(|lead| (value(lead) - mean).powi(2))
            .sum::<f64>()
            / (count - 1.0);
        (mean, (variance / count).sqrt())
    };
    [stats(|lead| lead.0), stats(|lead| lead.1)]
}

/// The mean outcome over every seed, with the standard errors of its retained at the end and
/// its mean retained over the horizon, over every card and over the cards from before the gap.
fn mean(scenario: Scenario, policy: &Policy) -> (Outcome, [f64; 4]) {
    let runs: Vec<Outcome> = SEEDS.map(|seed| run(seed, scenario, policy)).collect();
    let mut total = Outcome::default();
    for outcome in &runs {
        total.add(outcome);
    }
    let count = runs.len() as f64;
    let mean = total.scaled(1.0 / count);
    let error = |value: fn(&Outcome) -> f64| {
        let variance = runs
            .iter()
            .map(|outcome| (value(outcome) - value(&mean)).powi(2))
            .sum::<f64>()
            / (count - 1.0);
        (variance / count).sqrt()
    };
    (
        mean,
        [
            error(|outcome| outcome.retained),
            error(|outcome| outcome.mean_retained),
            error(|outcome| outcome.retained_old),
            error(|outcome| outcome.mean_retained_old),
        ],
    )
}

/// Study days of the warm-up that `Backlog::Over(days)` calls a backlog, for a user who
/// studies every day without a budget except `skipped` days at the end of each week.
fn false_backlog_days(days: f64, skipped: i64) -> f64 {
    let policy = Policy {
        order: CHOSEN_ORDER,
        bucket: CHOSEN_BUCKET,
        backlog: Backlog::Over(days),
        pause_new: true,
    };
    let mut total = 0.0;
    for seed in SEEDS {
        let mut sim = Simulation {
            rng: Rng(seed),
            cards: Vec::new(),
        };
        for day in (0..WARM_UP_DAYS).filter(|day| day % 7 < 7 - skipped) {
            let (_, _, _, backlog) = sim.session(day, None, &policy, true);
            total += f64::from(u8::from(backlog));
        }
    }
    total / SEEDS.count() as f64
}

const fn scenario(gap: i64, budget: usize, horizon: i64) -> Scenario {
    Scenario {
        gap,
        budget,
        horizon,
    }
}

/// The scenarios every table runs.
const SCENARIOS: [Scenario; 4] = [
    scenario(7, 50, 60),
    scenario(7, 200, 60),
    scenario(30, 50, 60),
    scenario(30, 200, 60),
];

/// Further budgets and horizons the order table is checked against.
const SENSITIVITY: [Scenario; 8] = [
    scenario(7, 25, 60),
    scenario(30, 25, 60),
    scenario(7, 100, 60),
    scenario(30, 100, 60),
    scenario(7, 50, 30),
    scenario(30, 50, 30),
    scenario(7, 100, 120),
    scenario(30, 100, 120),
];

const HEADER: &str = "| Skip | Budget | Horizon | Policy | Retained at end | Retained at end, cards from before the skip | Mean retained over the horizon | Reviews | New cards | Unfinished days | Backlog days |\n|---|---|---|---|---|---|---|---|---|---|---|";

fn row(
    scenario: Scenario,
    name: &str,
    (outcome, [end_error, mean_error, ..]): (Outcome, [f64; 4]),
) {
    println!(
        "| {} | {} | {} | {} | {:.1} ± {:.1} | {:.1} | {:.1} ± {:.1} | {:.0} | {:.0} | {:.1} | {:.1} |",
        scenario.gap,
        scenario.budget,
        scenario.horizon,
        name,
        outcome.retained,
        end_error,
        outcome.retained_old,
        outcome.mean_retained,
        mean_error,
        outcome.reviews,
        outcome.introduced,
        outcome.unfinished_days,
        outcome.backlog_days,
    );
}

/// The backlog threshold the new-card table runs with, in days of reviews due.
const CHOSEN_BACKLOG_DAYS: f64 = 3.0;
/// The bucket size the threshold tables run with.
const CHOSEN_BUCKET: usize = 10;
/// The order the bucket and threshold tables run with.
const CHOSEN_ORDER: Order = Order::DueAscending;

fn main() {
    let warm = warm_up(*SEEDS.start());
    let end = Timestamp(WARM_UP_DAYS * DAY + SESSION_START);
    println!(
        "Collection after the warm-up, seed {}: {} cards, a daily load of {:.1} reviews, {:.1} retained.\n",
        SEEDS.start(),
        warm.cards.len(),
        daily_load(&warm.cards),
        warm.retained(end, false),
    );

    println!(
        "## Days of reviews due on return\n\nThe due count over the daily load at the first session after a skip, the warm-up's collection, mean over the seeds.\n"
    );
    println!("| Skip | Due | Daily load | Days of reviews due |\n|---|---|---|---|");
    for gap in [1, 2, 3, 7, 14, 30] {
        let (mut due, mut load) = (0.0, 0.0);
        for seed in SEEDS {
            let sim = warm_up(seed);
            let now = Timestamp((WARM_UP_DAYS + gap) * DAY + SESSION_START);
            due += sim.cards.iter().filter(|card| card.due <= now).count() as f64;
            load += daily_load(&sim.cards);
        }
        let seeds = SEEDS.count() as f64;
        println!(
            "| {gap} | {:.0} | {:.1} | {:.2} |",
            due / seeds,
            load / seeds,
            due / load
        );
    }

    println!(
        "\n## Order\n\nEvery session of the horizon in backlog: its due cards in the strict order (bucket 1), no new card. The first row of each scenario is today's queue for comparison. The last eight scenarios check other budgets and horizons.\n"
    );
    println!("{HEADER}");
    let orders = [
        Order::Shuffle,
        Order::RetrievabilityAscending,
        Order::RetrievabilityDescending,
        Order::DueAscending,
    ];
    for scenario in SCENARIOS.into_iter().chain(SENSITIVITY) {
        let today = Policy {
            order: Order::Shuffle,
            bucket: 1,
            backlog: Backlog::Never,
            pause_new: true,
        };
        row(
            scenario,
            "today: shuffle with new cards",
            mean(scenario, &today),
        );
        for order in orders {
            let policy = Policy {
                order,
                bucket: 1,
                backlog: Backlog::Always,
                pause_new: true,
            };
            row(scenario, order.name(), mean(scenario, &policy));
        }
    }

    println!(
        "\n## Bucket size\n\nEvery session in backlog, {}, no new card.\n",
        CHOSEN_ORDER.name()
    );
    println!("{HEADER}");
    for scenario in SCENARIOS {
        for bucket in [1, 5, 10, 20, 50, 100] {
            let policy = Policy {
                order: CHOSEN_ORDER,
                bucket,
                backlog: Backlog::Always,
                pause_new: true,
            };
            row(
                scenario,
                &format!("bucket {bucket}"),
                mean(scenario, &policy),
            );
        }
    }

    println!(
        "\n## Backlog threshold\n\n{}, bucket {CHOSEN_BUCKET}, in backlog when more than the given days of reviews are due; out of it, today's queue.\n",
        CHOSEN_ORDER.name()
    );
    println!("{HEADER}");
    for scenario in SCENARIOS {
        let thresholds = [
            Backlog::Never,
            Backlog::Over(1.0),
            Backlog::Over(1.5),
            Backlog::Over(2.0),
            Backlog::Over(3.0),
            Backlog::Over(5.0),
            Backlog::Always,
        ];
        for backlog in thresholds {
            let policy = Policy {
                order: CHOSEN_ORDER,
                bucket: CHOSEN_BUCKET,
                backlog,
                pause_new: true,
            };
            let name = match backlog {
                Backlog::Never => "never in backlog (today)".to_owned(),
                Backlog::Always => "always in backlog".to_owned(),
                Backlog::Over(days) => format!("over {days} days due"),
            };
            row(scenario, &name, mean(scenario, &policy));
        }
    }

    println!(
        "\n## New cards in a backlog\n\nIn backlog over {CHOSEN_BACKLOG_DAYS} days of reviews due, {} in runs of {CHOSEN_BUCKET}, with new cards paused or with today's {NEW_PER_DAY} a day, each at a random place among the due cards; and today's queue. The pre-skip cards are the cards reviewed before the skip: the backlog's own.\n",
        CHOSEN_ORDER.name()
    );
    println!(
        "| Skip | Budget | Horizon | Policy | Mean retained over the horizon, pre-skip cards | Retained at end, pre-skip cards | Mean retained over the horizon, every card | Retained at end, every card | New cards | Backlog days | Paused leads this, pre-skip cards, over the horizon | Paused leads this, pre-skip cards, at end |\n|---|---|---|---|---|---|---|---|---|---|---|---|"
    );
    let budgets = SCENARIOS.into_iter().chain([
        scenario(7, 25, 60),
        scenario(30, 25, 60),
        scenario(7, 100, 60),
        scenario(30, 100, 60),
    ]);
    for scenario in budgets {
        let policies = [
            (
                "due date runs, new cards paused",
                Backlog::Over(CHOSEN_BACKLOG_DAYS),
                CHOSEN_ORDER,
                true,
            ),
            (
                "due date runs, new cards as today",
                Backlog::Over(CHOSEN_BACKLOG_DAYS),
                CHOSEN_ORDER,
                false,
            ),
            (
                "today: shuffle with new cards",
                Backlog::Never,
                Order::Shuffle,
                false,
            ),
        ];
        let paused = Policy {
            order: CHOSEN_ORDER,
            bucket: CHOSEN_BUCKET,
            backlog: Backlog::Over(CHOSEN_BACKLOG_DAYS),
            pause_new: true,
        };
        for (name, backlog, order, pause_new) in policies {
            let policy = Policy {
                order,
                bucket: CHOSEN_BUCKET,
                backlog,
                pause_new,
            };
            let (outcome, [end, mean_all, end_old, mean_old]) = mean(scenario, &policy);
            let lead = if pause_new {
                "— | —".to_owned()
            } else {
                let [(over, over_error), (at_end, end_error)] =
                    paired_lead(scenario, &paused, &policy);
                format!("{over:.1} ± {over_error:.1} | {at_end:.1} ± {end_error:.1}")
            };
            println!(
                "| {} | {} | {} | {name} | {:.1} ± {:.1} | {:.1} ± {:.1} | {:.1} ± {:.1} | {:.1} ± {:.1} | {:.0} | {:.1} | {lead} |",
                scenario.gap,
                scenario.budget,
                scenario.horizon,
                outcome.mean_retained_old,
                mean_old,
                outcome.retained_old,
                end_old,
                outcome.mean_retained,
                mean_all,
                outcome.retained,
                end,
                outcome.introduced,
                outcome.backlog_days,
            );
        }
    }

    println!(
        "\n## False backlogs\n\nStudy days of the {WARM_UP_DAYS}-day warm-up, without a budget, that each threshold calls a backlog, for a user who skips no day, one day a week, or two days a week.\n"
    );
    println!(
        "| Threshold | Skips no day | Skips 1 day a week | Skips 2 days a week |\n|---|---|---|---|"
    );
    for days in [1.0, 1.5, 2.0, 3.0, 5.0] {
        println!(
            "| over {days} days due | {:.1} | {:.1} | {:.1} |",
            false_backlog_days(days, 0),
            false_backlog_days(days, 1),
            false_backlog_days(days, 2),
        );
    }
}
