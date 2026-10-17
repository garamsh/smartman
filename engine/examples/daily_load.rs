//! Simulates users studying through the engine to choose the constants of the daily new-card
//! figure (issue #141): the study-time and pace half-lives, the daily change bound on the study
//! time, the cold start, the read window and the cap on an answer's duration. Run from
//! `engine/`:
//!
//! `cargo run --locked --release --example daily_load`
//!
//! It prints the Markdown tables ADR 0043 records. Every draw comes from one generator per run,
//! seeded from `SEEDS`, so the output is the same on every host.
//!
//! The model:
//! - each calendar day the user studies with a probability that is lower at the weekend; a
//!   study day has an amount of time `available` drawn around the habit's minutes, and the
//!   habit can change on `CHANGE_DAY`;
//! - the day's queue is every due card and the day's figure of new cards, shuffled, with no new
//!   card in a backlog (ADR 0025); the user answers until the queue is empty or the next card
//!   would pass the time available, so a short queue leaves time unused;
//! - a reviewed card is recalled with the probability the engine's retrievability gives, a new
//!   card with `FIRST_RECALL`; a "Don't know" comes back `RESHOW_GAP` cards later;
//! - a card's first answer takes a log-normal time around `FIRST_MEDIAN_MS`; a review takes one
//!   around a median that falls from `REVIEW_SLOW_MS` toward `REVIEW_FAST_MS` as the card is
//!   reviewed, the speed-up that comes with familiarity;
//! - an answer left on screen while the user is away (`IDLE_CHANCE`) stores the idle time on top
//!   of the time the answer took: what the stored `duration_ms` holds once background time no
//!   longer counts, while the screen stays in the foreground.

use smartman_engine::{FuzzFactor, MemoryState, Rating, Timestamp, review};

const DAY: i64 = 86_400;
/// When each day's session starts: 09:00, so the study day (from 04:00) holds it.
const SESSION_START: i64 = 9 * 3_600;
const HORIZON: i64 = 180;
/// The day a changed habit starts in the scenarios that change it.
const CHANGE_DAY: i64 = 90;
/// Days before this are the cold start and its settling; the main metrics read the days after.
const SETTLED_FROM: i64 = 30;
const FIRST_RECALL: f64 = 0.6;
const RESHOW_GAP: usize = 4;
const FIRST_MEDIAN_MS: f64 = 7_000.0;
const REVIEW_SLOW_MS: f64 = 6_500.0;
const REVIEW_FAST_MS: f64 = 2_500.0;
/// The reviews over which a card's review time halves its distance to `REVIEW_FAST_MS`.
const FAMILIARITY_HALF: f64 = 2.0;
const ANSWER_SPREAD: f64 = 0.7;
const IDLE_CHANCE: f64 = 0.03;
const IDLE_MEDIAN_MS: f64 = 90_000.0;
const IDLE_SPREAD: f64 = 1.0;
const SEEDS: std::ops::RangeInclusive<u64> = 1..=20;

/// The backlog rule of ADR 0025: more than this many days of reviews due pauses new cards.
const BACKLOG_DAYS: f64 = 3.0;

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

    /// A standard normal draw (Box–Muller).
    fn normal(&mut self) -> f64 {
        let u = 1.0 - self.next_f64();
        let v = self.next_f64();
        (-2.0 * u.ln()).sqrt() * (std::f64::consts::TAU * v).cos()
    }

    fn log_normal(&mut self, median: f64, spread: f64) -> f64 {
        median * (spread * self.normal()).exp()
    }

    fn shuffle<T>(&mut self, items: &mut [T]) {
        for place in 0..items.len().saturating_sub(1) {
            let pick = place + (self.next_f64() * (items.len() - place) as f64) as usize;
            items.swap(place, pick);
        }
    }
}

/// How the study-time estimate weighs the study days of the window.
#[derive(Clone, Copy)]
enum Estimate {
    /// Each day weighted 0.5^(age / half-life), age in study days, the newest 0.
    Weighted(f64),
    /// The plain mean of the window's days.
    Mean,
    /// The mean of the latest so many days.
    LastMean(usize),
    /// The median of the latest so many days.
    LastMedian(usize),
}

#[derive(Clone, Copy)]
struct Rule {
    estimate: Estimate,
    /// The pace's half-life, in study days.
    pace_half_life: f64,
    /// The most the study-time estimate moves from one study day's to the next, as a fraction;
    /// `None` leaves it unbounded.
    step: Option<f64>,
    /// The study days the window must hold before the figure leaves the cold start.
    cold_days: usize,
    /// The study days the estimate reads, newest first.
    window: usize,
    /// The most of an answer's stored duration the estimate counts; `None` counts all of it.
    cap_ms: Option<f64>,
    /// Not chosen, for comparison: the most the new-card figure moves from the previous study
    /// day's, in cards, as if each day's figure were stored.
    figure_step: Option<usize>,
    /// The reviews the figure sets time aside for.
    set_aside: SetAside,
}

/// Which reviews the figure sets time aside for.
#[derive(Clone, Copy)]
enum SetAside {
    /// The reviews due today.
    Due,
    /// The collection's daily load (`daily_load`).
    Load,
    /// The larger of the daily load and the reviews due today.
    LargerOfLoadAndDue,
    /// The daily load, plus the reviews due beyond it spread over so many days.
    Spread(f64),
}

impl SetAside {
    fn reviews(self, due: usize, load: f64) -> f64 {
        let due = due as f64;
        match self {
            SetAside::Due => due,
            SetAside::Load => load,
            SetAside::LargerOfLoadAndDue => load.max(due),
            SetAside::Spread(days) => load + (due - load).max(0.0) / days,
        }
    }
}

const COLD_NEW: usize = 20;
const PACE_MINIMUM: usize = 20;
const DEFAULT_ANSWER_MS: f64 = 10_000.0;

/// One answer as stored: its duration and whether it was its card's first.
#[derive(Clone, Copy)]
struct Stored {
    ms: f64,
    first: bool,
}

/// What the rule computes at a study day's start.
#[derive(Clone, Copy)]
struct Figure {
    /// The study time, in milliseconds; `None` in the cold start.
    time: Option<f64>,
    new_cards: usize,
}

impl Rule {
    fn capped(&self, ms: f64) -> f64 {
        self.cap_ms.map_or(ms, |cap| ms.min(cap))
    }

    /// The study time over `days`, oldest first, by the bounded recursion.
    fn time(&self, days: &[f64]) -> f64 {
        let raw = |upto: usize| -> f64 {
            let seen = &days[..=upto];
            match self.estimate {
                Estimate::Weighted(half_life) => {
                    let (mut sum, mut weights) = (0.0, 0.0);
                    for (index, value) in seen.iter().enumerate() {
                        let weight = 0.5_f64.powf((upto - index) as f64 / half_life);
                        sum += weight * value;
                        weights += weight;
                    }
                    sum / weights
                }
                Estimate::Mean => seen.iter().sum::<f64>() / seen.len() as f64,
                Estimate::LastMean(count) => {
                    let last = &seen[seen.len().saturating_sub(count)..];
                    last.iter().sum::<f64>() / last.len() as f64
                }
                Estimate::LastMedian(count) => {
                    let mut last = seen[seen.len().saturating_sub(count)..].to_vec();
                    last.sort_by(f64::total_cmp);
                    let middle = last.len() / 2;
                    if last.len() % 2 == 1 {
                        last[middle]
                    } else {
                        (last[middle - 1] + last[middle]) / 2.0
                    }
                }
            }
        };
        let mut time = raw(0);
        for upto in 1..days.len() {
            let next = raw(upto);
            time = match self.step {
                Some(step) => next.clamp(time * (1.0 - step), time * (1.0 + step)),
                None => next,
            };
        }
        time
    }

    /// The day's figure from the study days before it, oldest first, and the reviews due.
    fn figure(&self, history: &[Vec<Stored>], due: f64) -> Figure {
        let window = &history[history.len().saturating_sub(self.window)..];
        let pace = |first: bool| -> f64 {
            let (mut sum, mut weights, mut count) = (0.0, 0.0, 0);
            let newest = window.len().saturating_sub(1);
            for (index, day) in window.iter().enumerate() {
                let weight = 0.5_f64.powf((newest - index) as f64 / self.pace_half_life);
                for answer in day.iter().filter(|answer| answer.first == first) {
                    sum += weight * self.capped(answer.ms);
                    weights += weight;
                    count += 1;
                }
            }
            if count < PACE_MINIMUM {
                DEFAULT_ANSWER_MS
            } else {
                sum / weights
            }
        };
        let (review_ms, first_ms) = (pace(false), pace(true));
        if window.len() < self.cold_days.max(1) {
            return Figure {
                time: None,
                new_cards: COLD_NEW,
            };
        }
        let days: Vec<f64> = window
            .iter()
            .map(|day| day.iter().map(|answer| self.capped(answer.ms)).sum())
            .collect();
        let time = self.time(&days);
        let new_cards = ((time - due * review_ms) / first_ms).floor().max(0.0) as usize;
        Figure {
            time: Some(time),
            new_cards,
        }
    }
}

#[derive(Clone, Copy)]
struct Card {
    state: MemoryState,
    due: Timestamp,
    reviews: u32,
}

/// A user's habit: minutes a study day, how much a day varies, and how often a day is skipped.
#[derive(Clone, Copy)]
struct Habit {
    minutes: f64,
    spread: f64,
    weekday_rest: f64,
    weekend_rest: f64,
}

#[derive(Clone, Copy)]
struct Scenario {
    name: &'static str,
    before: Habit,
    /// The habit from `CHANGE_DAY` on.
    after: Habit,
    /// From `SETTLED_FROM`, the first `REST_LENGTH` days of every so many are skipped.
    rest_every: Option<i64>,
}

/// The days of each rest in a scenario with `rest_every`.
const REST_LENGTH: i64 = 2;

const fn habit(minutes: f64, spread: f64, weekday_rest: f64, weekend_rest: f64) -> Habit {
    Habit {
        minutes,
        spread,
        weekday_rest,
        weekend_rest,
    }
}

const STEADY: Habit = habit(15.0, 0.35, 0.1, 0.6);
const EVERY_DAY: Habit = habit(15.0, 0.35, 0.0, 0.0);
const SCENARIOS: [Scenario; 5] = [
    Scenario {
        name: "steady 15 min",
        before: STEADY,
        after: STEADY,
        rest_every: None,
    },
    Scenario {
        name: "15 min daily, 2 days' rest every 14",
        before: EVERY_DAY,
        after: EVERY_DAY,
        rest_every: Some(14),
    },
    Scenario {
        name: "irregular 15 min",
        before: habit(15.0, 0.7, 0.4, 0.4),
        after: habit(15.0, 0.7, 0.4, 0.4),
        rest_every: None,
    },
    Scenario {
        name: "25 → 8 min on day 90",
        before: habit(25.0, 0.35, 0.1, 0.6),
        after: habit(8.0, 0.35, 0.1, 0.6),
        rest_every: None,
    },
    Scenario {
        name: "8 → 25 min on day 90",
        before: habit(8.0, 0.35, 0.1, 0.6),
        after: habit(25.0, 0.35, 0.1, 0.6),
        rest_every: None,
    },
];

/// What one run measured. Times are milliseconds.
#[derive(Default, Clone)]
struct Run {
    /// Each settled study day: the estimate, the time actually studied, the time available.
    settled: Vec<(f64, f64, f64)>,
    /// The new cards each study day took after the cold start, in order.
    figures: Vec<usize>,
    /// The same with each study day's day number.
    dated: Vec<(i64, usize)>,
    /// The new cards each of the first `SETTLED_FROM` days' study days took.
    early: Vec<usize>,
    /// From `CHANGE_DAY`, each study day's estimate and time studied.
    after_change: Vec<(f64, f64)>,
    /// Each study day's estimate from stored durations against the same rule over the true ones.
    capped_error: Vec<f64>,
    new_cards: usize,
    unfinished_days: usize,
    study_days: usize,
}

fn draw_fuzz(rng: &mut Rng) -> Option<FuzzFactor> {
    Some(FuzzFactor::new(rng.next_f64()).expect("next_f64 is in [0, 1)"))
}

fn daily_load(cards: &[Card]) -> f64 {
    cards
        .iter()
        .map(|card| {
            let interval = (card.due.0 - card.state.last_review().0) as f64 / DAY as f64;
            1.0 / interval.max(1.0)
        })
        .sum()
}

fn run(seed: u64, scenario: &Scenario, rule: &Rule) -> Run {
    let mut rng = Rng(seed);
    let mut cards: Vec<Card> = Vec::new();
    // Each study day's answers, as stored and as they truly took.
    let mut stored: Vec<Vec<Stored>> = Vec::new();
    let mut true_days: Vec<Vec<Stored>> = Vec::new();
    let mut out = Run::default();
    let mut previous: Option<usize> = None;
    for day in 0..HORIZON {
        let habit = if day < CHANGE_DAY {
            scenario.before
        } else {
            scenario.after
        };
        let rest = if day % 7 >= 5 {
            habit.weekend_rest
        } else {
            habit.weekday_rest
        };
        if rng.next_f64() < rest {
            continue;
        }
        if let Some(period) = scenario.rest_every
            && day >= SETTLED_FROM
            && (day - SETTLED_FROM) % period < REST_LENGTH
        {
            continue;
        }
        let available = rng.log_normal(habit.minutes * 60_000.0, habit.spread);
        let start = day * DAY + SESSION_START;
        let day_end = (day + 1) * DAY + 4 * 3_600;
        let due: Vec<usize> = (0..cards.len())
            .filter(|&index| cards[index].due.0 < day_end)
            .collect();
        let set_aside = rule.set_aside.reviews(due.len(), daily_load(&cards));
        let mut figure = rule.figure(&stored, set_aside);
        if let (Some(step), Some(previous), Some(_)) = (rule.figure_step, previous, figure.time) {
            figure.new_cards = figure
                .new_cards
                .clamp(previous.saturating_sub(step), previous + step);
        }
        previous = Some(figure.new_cards);
        if figure.time.is_some() {
            let exact = Rule {
                cap_ms: None,
                ..*rule
            }
            .figure(&true_days, set_aside);
            if let (Some(capped), Some(truth)) = (figure.time, exact.time) {
                out.capped_error.push((capped - truth).abs() / truth);
            }
        }
        let backlog = due.len() as f64 > BACKLOG_DAYS * daily_load(&cards);
        let fresh = if backlog { 0 } else { figure.new_cards };
        let mut queue: Vec<Option<usize>> = due.into_iter().map(Some).collect();
        queue.extend(std::iter::repeat_n(None, fresh));
        rng.shuffle(&mut queue);

        let mut now = start;
        let (mut studied, mut taken) = (0.0, 0);
        let mut today_stored = Vec::new();
        let mut today_true = Vec::new();
        while !queue.is_empty() {
            let card = queue[0];
            let first = card.is_none();
            let median = match card {
                None => FIRST_MEDIAN_MS,
                Some(index) => {
                    let reviews = f64::from(cards[index].reviews);
                    REVIEW_FAST_MS
                        + (REVIEW_SLOW_MS - REVIEW_FAST_MS)
                            * 0.5_f64.powf(reviews / FAMILIARITY_HALF)
                }
            };
            let took = rng.log_normal(median, ANSWER_SPREAD);
            if studied + took > available && studied > 0.0 {
                break;
            }
            queue.remove(0);
            studied += took;
            let idle = if rng.next_f64() < IDLE_CHANCE {
                rng.log_normal(IDLE_MEDIAN_MS, IDLE_SPREAD)
            } else {
                0.0
            };
            today_stored.push(Stored {
                ms: took + idle,
                first,
            });
            today_true.push(Stored { ms: took, first });
            now += ((took + idle) / 1_000.0).ceil() as i64;
            let at = Timestamp(now);
            let recall = match card {
                Some(index) => cards[index]
                    .state
                    .retrievability(at)
                    .expect("a session never runs before a card's last review"),
                None => FIRST_RECALL,
            };
            let rating = if rng.next_f64() < recall {
                Rating::Good
            } else {
                Rating::Again
            };
            let state = card.map(|index| cards[index].state);
            let (state, due) =
                review(state.as_ref(), rating, at, draw_fuzz(&mut rng)).expect("a valid review");
            let index = match card {
                Some(index) => {
                    cards[index].state = state;
                    cards[index].due = due;
                    cards[index].reviews += 1;
                    index
                }
                None => {
                    taken += 1;
                    cards.push(Card {
                        state,
                        due,
                        reviews: 0,
                    });
                    cards.len() - 1
                }
            };
            if rating == Rating::Again {
                queue.insert(RESHOW_GAP.min(queue.len()), Some(index));
            }
        }
        if today_stored.is_empty() {
            continue;
        }
        out.study_days += 1;
        out.new_cards += taken;
        if !queue.is_empty() {
            out.unfinished_days += 1;
        }
        if let Some(time) = figure.time {
            out.figures.push(fresh);
            out.dated.push((day, fresh));
            if day >= SETTLED_FROM {
                out.settled.push((time, studied, available));
            }
            if day >= CHANGE_DAY {
                out.after_change.push((time, studied));
            }
        }
        if day < SETTLED_FROM {
            out.early.push(fresh);
        }
        stored.push(today_stored);
        true_days.push(today_true);
    }
    out
}

/// The means over every seed of what a table row shows.
#[derive(Default)]
struct Row {
    /// Mean |studied − estimate| / estimate over settled study days.
    fit: f64,
    /// Mean |new cards − the previous study day's| after the cold start.
    swing: f64,
    /// The same over the first `SETTLED_FROM` days.
    early_swing: f64,
    /// Study days after `CHANGE_DAY` until the estimate is within 20% of the time studied
    /// over the 30 study days that follow, or `None` in a scenario without a change.
    follow: Option<f64>,
    /// Mean |estimate from stored durations − estimate from true durations| / the latter.
    cap_error: f64,
    new_per_day: f64,
    /// After each rest of a scenario with `rest_every`: the new cards on the day of return over
    /// the mean of the three study days before the rest, and the study days from the return
    /// until a day takes at least 90% of that mean, at most 14.
    rest: Option<(f64, f64)>,
    /// The time studied over the time available, settled days.
    used: f64,
    minutes: f64,
    unfinished: f64,
}

fn mean_of(values: &[f64]) -> f64 {
    if values.is_empty() {
        0.0
    } else {
        values.iter().sum::<f64>() / values.len() as f64
    }
}

fn swing(figures: &[usize]) -> f64 {
    let steps: Vec<f64> = figures
        .windows(2)
        .map(|pair| (pair[1] as f64 - pair[0] as f64).abs())
        .collect();
    mean_of(&steps)
}

/// Each rest of `run`: the return day's new cards over the mean of the three study days before,
/// and the study days until a day takes at least 90% of that mean, at most 14.
fn rests(run: &Run) -> Vec<(f64, f64)> {
    let mut episodes = Vec::new();
    for at in 3..run.dated.len() {
        if run.dated[at].0 - run.dated[at - 1].0 <= REST_LENGTH {
            continue;
        }
        let before = mean_of(
            &run.dated[at - 3..at]
                .iter()
                .map(|(_, fresh)| *fresh as f64)
                .collect::<Vec<_>>(),
        );
        if before == 0.0 {
            continue;
        }
        let recovery = run.dated[at..]
            .iter()
            .take(15)
            .position(|(_, fresh)| *fresh as f64 >= 0.9 * before)
            .unwrap_or(14);
        episodes.push((run.dated[at].1 as f64 / before, recovery as f64));
    }
    episodes
}

fn measure(scenario: &Scenario, rule: &Rule) -> Row {
    let runs: Vec<Run> = SEEDS.map(|seed| run(seed, scenario, rule)).collect();
    let per_run =
        |value: &dyn Fn(&Run) -> f64| mean_of(&runs.iter().map(value).collect::<Vec<_>>());
    let changes = scenario.before.minutes != scenario.after.minutes;
    Row {
        fit: per_run(&|run| {
            mean_of(
                &run.settled
                    .iter()
                    .map(|(time, studied, _)| (studied - time).abs() / time)
                    .collect::<Vec<_>>(),
            )
        }),
        swing: per_run(&|run| swing(&run.figures)),
        early_swing: per_run(&|run| swing(&run.early)),
        follow: changes.then(|| {
            per_run(&|run| {
                let level = mean_of(
                    &run.after_change
                        .iter()
                        .skip(20)
                        .take(30)
                        .map(|(_, studied)| *studied)
                        .collect::<Vec<_>>(),
                );
                run.after_change
                    .iter()
                    .position(|(time, _)| (time - level).abs() <= 0.2 * level)
                    .unwrap_or(run.after_change.len()) as f64
            })
        }),
        cap_error: per_run(&|run| mean_of(&run.capped_error)),
        rest: scenario.rest_every.map(|_| {
            let episodes: Vec<(f64, f64)> = runs.iter().flat_map(rests).collect();
            (
                mean_of(&episodes.iter().map(|episode| episode.0).collect::<Vec<_>>()),
                mean_of(&episodes.iter().map(|episode| episode.1).collect::<Vec<_>>()),
            )
        }),
        new_per_day: per_run(&|run| run.new_cards as f64 / run.study_days as f64),
        used: per_run(&|run| {
            mean_of(
                &run.settled
                    .iter()
                    .map(|(_, studied, available)| studied / available)
                    .collect::<Vec<_>>(),
            )
        }),
        minutes: per_run(&|run| {
            mean_of(
                &run.settled
                    .iter()
                    .map(|(_, studied, _)| studied / 60_000.0)
                    .collect::<Vec<_>>(),
            )
        }),
        unfinished: per_run(&|run| run.unfinished_days as f64 / run.study_days as f64),
    }
}

const CHOSEN: Rule = Rule {
    estimate: Estimate::Weighted(7.0),
    pace_half_life: 7.0,
    step: Some(0.1),
    cold_days: 5,
    window: 30,
    cap_ms: Some(30_000.0),
    figure_step: None,
    set_aside: SetAside::Spread(7.0),
};

fn table(title: &str, intro: &str, candidates: &[(String, Rule)]) {
    println!("\n## {title}\n\n{intro}\n");
    println!(
        "| Scenario | Candidate | Fit | Swing | Early swing | Follow | Return | Recovery | Cap error | New a day | Minutes | Time used | Unfinished days |\n|---|---|---|---|---|---|---|---|---|---|---|---|---|"
    );
    for scenario in &SCENARIOS {
        for (name, rule) in candidates {
            let row = measure(scenario, rule);
            let follow = row
                .follow
                .map_or_else(|| "—".to_owned(), |days| format!("{days:.1}"));
            let rest = row.rest.map_or_else(
                || "— | —".to_owned(),
                |(back, days)| format!("{back:.2} | {days:.1}"),
            );
            println!(
                "| {} | {name} | {:.3} | {:.2} | {:.2} | {follow} | {rest} | {:.3} | {:.1} | {:.1} | {:.2} | {:.2} |",
                scenario.name,
                row.fit,
                row.swing,
                row.early_swing,
                row.cap_error,
                row.new_per_day,
                row.minutes,
                row.used,
                row.unfinished,
            );
        }
    }
}

fn main() {
    println!(
        "Every row is the mean over seeds {}–{}. Fit: mean |time studied − T| / T over the study days from day {SETTLED_FROM}. Swing: mean change in new cards between consecutive study days after the cold start; early swing the same over the first {SETTLED_FROM} days. Follow: study days after day {CHANGE_DAY} until T is within 20% of the time studied over study days 21–50 after it. Cap error: mean |T from stored durations − T from the true durations| / the latter. Time used: time studied over time available. Unfinished days: study days whose queue the user did not finish.",
        SEEDS.start(),
        SEEDS.end()
    );
    let with = |change: &dyn Fn(&mut Rule)| {
        let mut rule = CHOSEN;
        change(&mut rule);
        rule
    };
    table(
        "Study-time estimate",
        "The chosen rule with the study-time estimate replaced, and unbounded, so the estimators compare alone.",
        &[
            (
                "weighted, half-life 3".to_owned(),
                with(&|rule| {
                    rule.estimate = Estimate::Weighted(3.0);
                    rule.step = None;
                }),
            ),
            (
                "weighted, half-life 7".to_owned(),
                with(&|rule| rule.step = None),
            ),
            (
                "weighted, half-life 14".to_owned(),
                with(&|rule| {
                    rule.estimate = Estimate::Weighted(14.0);
                    rule.step = None;
                }),
            ),
            (
                "plain mean of the window".to_owned(),
                with(&|rule| {
                    rule.estimate = Estimate::Mean;
                    rule.step = None;
                }),
            ),
            (
                "mean of the last 7".to_owned(),
                with(&|rule| {
                    rule.estimate = Estimate::LastMean(7);
                    rule.step = None;
                }),
            ),
            (
                "median of the last 7".to_owned(),
                with(&|rule| {
                    rule.estimate = Estimate::LastMedian(7);
                    rule.step = None;
                }),
            ),
        ],
    );
    table(
        "Change bound",
        "The chosen rule with the bound on T's change between study days varied.",
        &[0.1, 0.2, 0.3, 0.5]
            .map(|step| {
                (
                    format!("±{:.0}%", step * 100.0),
                    with(&|rule| rule.step = Some(step)),
                )
            })
            .into_iter()
            .chain([("unbounded".to_owned(), with(&|rule| rule.step = None))])
            .collect::<Vec<_>>(),
    );
    table(
        "Pace half-life",
        "The chosen rule with the pace's half-life varied, in study days.",
        &[3.0, 7.0, 14.0, 28.0].map(|half| {
            (
                format!("pace half-life {half:.0}"),
                with(&|rule| rule.pace_half_life = half),
            )
        }),
    );
    table(
        "Cold start",
        "The chosen rule with the study days the window must hold before leaving the cold start varied.",
        &[1, 3, 5, 7, 10].map(|days| {
            (
                format!("{days} study days"),
                with(&|rule| rule.cold_days = days),
            )
        }),
    );
    table(
        "Window",
        "The chosen rule with the study days the estimate reads varied.",
        &[14, 30, 60].map(|days| {
            (
                format!("{days} study days"),
                with(&|rule| rule.window = days),
            )
        }),
    );
    table(
        "Reviews set aside",
        "The chosen rule with the reviews the figure sets time aside for varied: the reviews due today as the issue first stated it, the collection's daily load, the larger of the two, or the daily load plus the reviews due beyond it spread over k days; and, not built, the figure bounded against the previous study day's, as if each day's figure were stored.",
        &[
            (
                "A: reviews due today".to_owned(),
                with(&|rule| rule.set_aside = SetAside::Due),
            ),
            (
                "B: reviews due today, figure bounded ±5 cards".to_owned(),
                with(&|rule| {
                    rule.set_aside = SetAside::Due;
                    rule.figure_step = Some(5);
                }),
            ),
            (
                "E: daily load".to_owned(),
                with(&|rule| rule.set_aside = SetAside::Load),
            ),
            (
                "F: larger of daily load and reviews due".to_owned(),
                with(&|rule| rule.set_aside = SetAside::LargerOfLoadAndDue),
            ),
            (
                "G: daily load + excess over 2 days".to_owned(),
                with(&|rule| rule.set_aside = SetAside::Spread(2.0)),
            ),
            (
                "G: daily load + excess over 3 days".to_owned(),
                with(&|rule| rule.set_aside = SetAside::Spread(3.0)),
            ),
            (
                "G: daily load + excess over 5 days".to_owned(),
                with(&|rule| rule.set_aside = SetAside::Spread(5.0)),
            ),
            (
                "G: daily load + excess over 7 days (chosen)".to_owned(),
                CHOSEN,
            ),
            (
                "G: daily load + excess over 10 days".to_owned(),
                with(&|rule| rule.set_aside = SetAside::Spread(10.0)),
            ),
            (
                "G: daily load + excess over 14 days".to_owned(),
                with(&|rule| rule.set_aside = SetAside::Spread(14.0)),
            ),
        ],
    );
    table(
        "Duration cap",
        "The chosen rule with the most of an answer's duration the estimate counts varied.",
        &[
            (
                "20 s".to_owned(),
                with(&|rule| rule.cap_ms = Some(20_000.0)),
            ),
            (
                "30 s".to_owned(),
                with(&|rule| rule.cap_ms = Some(30_000.0)),
            ),
            (
                "45 s".to_owned(),
                with(&|rule| rule.cap_ms = Some(45_000.0)),
            ),
            (
                "60 s".to_owned(),
                with(&|rule| rule.cap_ms = Some(60_000.0)),
            ),
            (
                "120 s".to_owned(),
                with(&|rule| rule.cap_ms = Some(120_000.0)),
            ),
            (
                "300 s".to_owned(),
                with(&|rule| rule.cap_ms = Some(300_000.0)),
            ),
            ("none".to_owned(), with(&|rule| rule.cap_ms = None)),
        ],
    );
}
