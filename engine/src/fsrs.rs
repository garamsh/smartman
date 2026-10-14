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
