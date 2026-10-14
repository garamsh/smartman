//! FSRS-6 formulas, written from the published algorithm description.

use crate::Rating;

/// FSRS-6 default parameters `w[0]..w[20]`.
const W: [f64; 21] = [
    0.212, 1.2931, 2.3065, 8.2956, 6.4133, 0.8334, 3.0194, 0.001, 1.8722, 0.1666, 0.796, 1.4835,
    0.0614, 0.2629, 1.6483, 0.6014, 1.8729, 0.5425, 0.0912, 0.0658, 0.1542,
];

const DESIRED_RETENTION: f64 = 0.9;
const MAXIMUM_INTERVAL_DAYS: u32 = 36_500;

pub(crate) const STABILITY_MIN: f64 = 0.001;
pub(crate) const DIFFICULTY_MIN: f64 = 1.0;
pub(crate) const DIFFICULTY_MAX: f64 = 10.0;

fn decay() -> f64 {
    -W[20]
}

/// Chosen so that retrievability is 0.9 when elapsed days equal stability.
fn factor() -> f64 {
    0.9_f64.powf(1.0 / decay()) - 1.0
}

fn grade(rating: Rating) -> f64 {
    f64::from(rating as u8)
}

fn clamp_stability(stability: f64) -> f64 {
    stability.max(STABILITY_MIN)
}

fn clamp_difficulty(difficulty: f64) -> f64 {
    difficulty.clamp(DIFFICULTY_MIN, DIFFICULTY_MAX)
}

pub(crate) fn retrievability(elapsed_days: f64, stability: f64) -> f64 {
    (1.0 + factor() * elapsed_days / stability).powf(decay())
}

pub(crate) fn initial_stability(rating: Rating) -> f64 {
    clamp_stability(W[rating as usize - 1])
}

fn unclamped_initial_difficulty(rating: Rating) -> f64 {
    W[4] - (W[5] * (grade(rating) - 1.0)).exp() + 1.0
}

pub(crate) fn initial_difficulty(rating: Rating) -> f64 {
    clamp_difficulty(unclamped_initial_difficulty(rating))
}

/// Linear damping toward 10, then mean reversion toward the initial difficulty of `Easy`.
pub(crate) fn next_difficulty(difficulty: f64, rating: Rating) -> f64 {
    let delta = -W[6] * (grade(rating) - 3.0);
    let damped = difficulty + delta * (10.0 - difficulty) / 9.0;
    let reverted = W[7] * unclamped_initial_difficulty(Rating::Easy) + (1.0 - W[7]) * damped;
    clamp_difficulty(reverted)
}

/// Stability after a review less than one day after the previous one.
pub(crate) fn short_term_stability(stability: f64, rating: Rating) -> f64 {
    let increase = (W[17] * (grade(rating) - 3.0 + W[18])).exp() * stability.powf(-W[19]);
    let increase = match rating {
        Rating::Again => increase,
        Rating::Hard | Rating::Good | Rating::Easy => increase.max(1.0),
    };
    clamp_stability(stability * increase)
}

pub(crate) fn next_stability(
    difficulty: f64,
    stability: f64,
    retrievability: f64,
    rating: Rating,
) -> f64 {
    let next = match rating {
        Rating::Again => forget_stability(difficulty, stability, retrievability),
        Rating::Hard | Rating::Good | Rating::Easy => {
            recall_stability(difficulty, stability, retrievability, rating)
        }
    };
    clamp_stability(next)
}

fn recall_stability(difficulty: f64, stability: f64, retrievability: f64, rating: Rating) -> f64 {
    let hard_penalty = if rating == Rating::Hard { W[15] } else { 1.0 };
    let easy_bonus = if rating == Rating::Easy { W[16] } else { 1.0 };
    stability
        * (1.0
            + W[8].exp()
                * (11.0 - difficulty)
                * stability.powf(-W[9])
                * (((1.0 - retrievability) * W[10]).exp() - 1.0)
                * hard_penalty
                * easy_bonus)
}

/// Post-lapse stability, capped so a lapse never raises stability above its same-day value.
fn forget_stability(difficulty: f64, stability: f64, retrievability: f64) -> f64 {
    let long_term = W[11]
        * difficulty.powf(-W[12])
        * ((stability + 1.0).powf(W[13]) - 1.0)
        * ((1.0 - retrievability) * W[14]).exp();
    let short_term = stability / (W[17] * W[18]).exp();
    long_term.min(short_term)
}

/// Whole days until retrievability falls to the desired retention.
pub(crate) fn interval_days(stability: f64) -> u32 {
    let days = (stability / factor()) * (DESIRED_RETENTION.powf(1.0 / decay()) - 1.0);
    // Ties round to even, as the reference implementation's `round` does.
    let rounded = days.round_ties_even().max(1.0);
    if rounded >= f64::from(MAXIMUM_INTERVAL_DAYS) {
        MAXIMUM_INTERVAL_DAYS
    } else {
        rounded as u32
    }
}

/// Intervals shorter than this many days are not fuzzed.
const FUZZ_MIN_DAYS: f64 = 2.5;

/// `(start, end, factor)`: each day of the interval between `start` and `end` widens the
/// fuzz range by `factor` days on either side.
const FUZZ_RANGES: [(f64, f64, f64); 3] = [
    (2.5, 7.0, 0.15),
    (7.0, 20.0, 0.1),
    (20.0, f64::INFINITY, 0.05),
];

/// `interval` days fuzzed as py-fsrs does: a whole number of days in a range around it, picked
/// by `factor` in `[0, 1)`; an interval under 2.5 days is returned unchanged.
pub(crate) fn fuzzed_interval_days(interval: u32, factor: f64) -> u32 {
    let days = f64::from(interval);
    if days < FUZZ_MIN_DAYS {
        return interval;
    }
    // Summed from 1 in order, as the reference does, so the rounding below sees the same value.
    let delta = FUZZ_RANGES.iter().fold(1.0, |delta, (start, end, step)| {
        delta + step * (days.min(*end) - start).max(0.0)
    });
    let maximum = f64::from(MAXIMUM_INTERVAL_DAYS);
    let max_days = (days + delta).round_ties_even().min(maximum);
    let min_days = (days - delta).round_ties_even().max(2.0).min(max_days);
    // The pick can round to one past `max_days`, as the reference's can.
    let fuzzed = (factor * (max_days - min_days + 1.0) + min_days).round_ties_even();
    fuzzed.min(maximum) as u32
}

#[cfg(test)]
mod tests {
    use super::*;

    /// The largest factor below 1.
    const FACTOR_MAX: f64 = 1.0 - f64::EPSILON / 2.0;

    #[test]
    fn intervals_under_two_and_a_half_days_are_never_fuzzed() {
        for days in [1, 2] {
            for factor in [0.0, 0.5, FACTOR_MAX] {
                assert_eq!(
                    fuzzed_interval_days(days, factor),
                    days,
                    "{days} at {factor}"
                );
            }
        }
        // Control: three days, the shortest interval fuzzed, moves at both factor ends.
        assert_eq!(fuzzed_interval_days(3, 0.0), 2);
        assert_eq!(fuzzed_interval_days(3, FACTOR_MAX), 5);
    }

    /// Each row is `(interval, at factor 0, at the largest factor below 1)`, as py-fsrs
    /// 6.3.2's `Scheduler._get_fuzzed_interval` returns them with `random` returning each.
    const BOUNDS: [(u32, u32, u32); 6] = [
        (3, 2, 5),
        (8, 6, 11),
        (20, 17, 24),
        (100, 93, 108),
        (36_000, 34_198, 36_500),
        (36_500, 34_673, 36_500),
    ];

    #[test]
    fn the_least_and_greatest_factor_give_the_ends_of_the_fuzz_range() {
        for (days, least, greatest) in BOUNDS {
            assert_eq!(fuzzed_interval_days(days, 0.0), least, "{days} at 0");
            assert_eq!(
                fuzzed_interval_days(days, FACTOR_MAX),
                greatest,
                "{days} at max"
            );
            // Control: a factor between them lands inside the range, not on either end.
            let middle = fuzzed_interval_days(days, 0.5);
            assert!(
                least < middle && middle < greatest,
                "{days} at 0.5: {middle}"
            );
        }
    }
}
