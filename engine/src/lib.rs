//! FSRS-6 scheduling: a card's memory state and next due time from its review history.
//!
//! Every function is pure. The engine reads no clock and stores nothing: the caller
//! passes the time of each review and keeps the history.

mod fsrs;

const SECONDS_PER_DAY: i64 = 86_400;

/// An FSRS rating of one review.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Rating {
    Again = 1,
    Hard = 2,
    Good = 3,
    Easy = 4,
}

/// The app's two answer buttons.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Answer {
    Know,
    DontKnow,
}

impl From<Answer> for Rating {
    fn from(answer: Answer) -> Self {
        match answer {
            Answer::Know => Rating::Good,
            Answer::DontKnow => Rating::Again,
        }
    }
}

/// A point in time, in whole seconds since the Unix epoch (UTC).
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
pub struct Timestamp(pub i64);

impl Timestamp {
    /// Whole days from `earlier` to `self`, rounded toward negative infinity.
    fn days_since(self, earlier: Timestamp) -> i64 {
        (self.0 - earlier.0).div_euclid(SECONDS_PER_DAY)
    }

    fn plus_days(self, days: u32) -> Timestamp {
        Timestamp(self.0.saturating_add(i64::from(days) * SECONDS_PER_DAY))
    }
}

/// One review in a card's history.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Review {
    pub rating: Rating,
    pub at: Timestamp,
}

/// A card's memory state after at least one review. Only the engine constructs it.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct MemoryState {
    stability: f64,
    difficulty: f64,
    last_review: Timestamp,
}

impl MemoryState {
    /// Days until retrievability falls to 0.9.
    pub fn stability(&self) -> f64 {
        self.stability
    }

    /// Difficulty in `[1, 10]`.
    pub fn difficulty(&self) -> f64 {
        self.difficulty
    }

    /// Time of the review that produced this state.
    pub fn last_review(&self) -> Timestamp {
        self.last_review
    }

    /// Probability of recall at `now`, counting only whole elapsed days.
    pub fn retrievability(&self, now: Timestamp) -> f64 {
        let elapsed = now.days_since(self.last_review).max(0);
        fsrs::retrievability(elapsed as f64, self.stability)
    }
}

/// Reviews a card, or a new card when `state` is `None`, and returns its new state and due time.
pub fn review(
    state: Option<&MemoryState>,
    rating: Rating,
    now: Timestamp,
) -> (MemoryState, Timestamp) {
    let (stability, difficulty) = match state {
        None => (
            fsrs::initial_stability(rating),
            fsrs::initial_difficulty(rating),
        ),
        Some(state) => {
            let stability = if now.days_since(state.last_review) < 1 {
                fsrs::short_term_stability(state.stability, rating)
            } else {
                fsrs::next_stability(
                    state.difficulty,
                    state.stability,
                    state.retrievability(now),
                    rating,
                )
            };
            (stability, fsrs::next_difficulty(state.difficulty, rating))
        }
    };
    let next = MemoryState {
        stability,
        difficulty,
        last_review: now,
    };
    (next, now.plus_days(fsrs::interval_days(stability)))
}

/// Replays a history, in the order the reviews happened, into the card's state; `None` when empty.
pub fn replay(history: &[Review]) -> Option<MemoryState> {
    history.iter().fold(None, |state, step| {
        Some(review(state.as_ref(), step.rating, step.at).0)
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn know_answers_good_and_dont_know_answers_again() {
        assert_eq!(Rating::from(Answer::Know), Rating::Good);
        assert_eq!(Rating::from(Answer::DontKnow), Rating::Again);
    }
}
