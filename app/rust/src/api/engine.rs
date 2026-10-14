//! The engine functions and types the app calls through the bridge.
//!
//! Times are whole seconds since the Unix epoch (UTC), as the engine's `Timestamp` holds them.
//! Every engine refusal returns as an [`EngineError`]; nothing here panics across the bridge.

#![deny(
    missing_docs,
    clippy::panic,
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::indexing_slicing
)]

use smartman_engine as engine;

/// The app's two answer buttons.
pub enum Answer {
    /// "Know": rated `Good`.
    Know,
    /// "Don't know": rated `Again`.
    DontKnow,
}

/// The parts of a card's memory state that the app persists.
pub struct MemoryStateParts {
    /// Days until retrievability falls to 0.9.
    pub stability: f64,
    /// Difficulty, from 1 to 10.
    pub difficulty: f64,
    /// Time of the review that produced this state.
    pub last_review: i64,
}

/// A card's state after a review, and when it is next due.
pub struct Scheduled {
    /// The new memory state.
    pub state: MemoryStateParts,
    /// When the card is next due.
    pub due: i64,
}

/// One review in a card's history.
pub struct ReviewRecord {
    /// The answer given.
    pub answer: Answer,
    /// When it was given.
    pub at: i64,
}

/// A floating-point quantity the engine takes.
pub enum Quantity {
    /// Stability: at least 0.001 days.
    Stability,
    /// Difficulty: from 1 to 10.
    Difficulty,
    /// Fuzz factor: from 0, inclusive, to 1, exclusive.
    FuzzFactor,
}

/// Why the engine refused its input; one variant per engine `Error` variant.
pub enum EngineError {
    /// A review is dated before the card's last review.
    ReviewBeforeLastReview {
        /// The card's last review.
        last_review: i64,
        /// The refused review time.
        review: i64,
    },
    /// A number that is not one of the four FSRS ratings (1 to 4).
    UnknownRating {
        /// The refused number.
        value: u8,
    },
    /// A NaN or infinite value given for a quantity.
    NonFinite {
        /// The quantity given.
        quantity: Quantity,
    },
    /// A finite value outside the range the quantity allows.
    OutOfRange {
        /// The quantity given.
        quantity: Quantity,
        /// The refused value.
        value: f64,
    },
}

/// Reviews a new card for the first time, its interval fuzzed by `fuzz_factor`, a value in
/// `[0, 1)`, or not fuzzed when it is `None`.
pub fn review_new_card(
    answer: Answer,
    at: i64,
    fuzz_factor: Option<f64>,
) -> Result<Scheduled, EngineError> {
    scheduled(engine::review(
        None,
        answer.into(),
        engine::Timestamp(at),
        fuzz(fuzz_factor)?,
    )?)
}

/// Reviews a card whose state the app persisted as `state`, its interval fuzzed by
/// `fuzz_factor`, a value in `[0, 1)`, or not fuzzed when it is `None`.
pub fn review_card(
    state: MemoryStateParts,
    answer: Answer,
    at: i64,
    fuzz_factor: Option<f64>,
) -> Result<Scheduled, EngineError> {
    let state = engine::MemoryState::try_from(state)?;
    scheduled(engine::review(
        Some(&state),
        answer.into(),
        engine::Timestamp(at),
        fuzz(fuzz_factor)?,
    )?)
}

/// Replays a history, in the order the reviews happened, into the card's state; `None` when empty.
pub fn replay(history: Vec<ReviewRecord>) -> Result<Option<MemoryStateParts>, EngineError> {
    let history: Vec<engine::Review> = history.into_iter().map(engine::Review::from).collect();
    Ok(engine::replay(&history)?.map(MemoryStateParts::from))
}

/// Probability of recall at `at` of a card whose state the app persisted as `state`.
pub fn retrievability(state: MemoryStateParts, at: i64) -> Result<f64, EngineError> {
    Ok(engine::MemoryState::try_from(state)?.retrievability(engine::Timestamp(at))?)
}

fn fuzz(factor: Option<f64>) -> Result<Option<engine::FuzzFactor>, engine::Error> {
    factor.map(engine::FuzzFactor::new).transpose()
}

fn scheduled(
    (state, due): (engine::MemoryState, engine::Timestamp),
) -> Result<Scheduled, EngineError> {
    Ok(Scheduled {
        state: state.into(),
        due: due.0,
    })
}

impl From<Answer> for engine::Rating {
    fn from(answer: Answer) -> Self {
        engine::Answer::from(answer).into()
    }
}

impl From<Answer> for engine::Answer {
    fn from(answer: Answer) -> Self {
        match answer {
            Answer::Know => engine::Answer::Know,
            Answer::DontKnow => engine::Answer::DontKnow,
        }
    }
}

impl From<ReviewRecord> for engine::Review {
    fn from(record: ReviewRecord) -> Self {
        engine::Review {
            rating: record.answer.into(),
            at: engine::Timestamp(record.at),
        }
    }
}

impl TryFrom<MemoryStateParts> for engine::MemoryState {
    type Error = engine::Error;

    fn try_from(parts: MemoryStateParts) -> Result<Self, engine::Error> {
        engine::MemoryState::from_parts(
            parts.stability,
            parts.difficulty,
            engine::Timestamp(parts.last_review),
        )
    }
}

impl From<engine::MemoryState> for MemoryStateParts {
    fn from(state: engine::MemoryState) -> Self {
        MemoryStateParts {
            stability: state.stability(),
            difficulty: state.difficulty(),
            last_review: state.last_review().0,
        }
    }
}

impl From<engine::Quantity> for Quantity {
    fn from(quantity: engine::Quantity) -> Self {
        match quantity {
            engine::Quantity::Stability => Quantity::Stability,
            engine::Quantity::Difficulty => Quantity::Difficulty,
            engine::Quantity::FuzzFactor => Quantity::FuzzFactor,
        }
    }
}

impl From<engine::Error> for EngineError {
    fn from(error: engine::Error) -> Self {
        match error {
            engine::Error::ReviewBeforeLastReview {
                last_review,
                review,
            } => EngineError::ReviewBeforeLastReview {
                last_review: last_review.0,
                review: review.0,
            },
            engine::Error::UnknownRating(value) => EngineError::UnknownRating { value },
            engine::Error::NonFinite(quantity) => EngineError::NonFinite {
                quantity: quantity.into(),
            },
            engine::Error::OutOfRange { quantity, value } => EngineError::OutOfRange {
                quantity: quantity.into(),
                value,
            },
        }
    }
}

/// Installs flutter_rust_bridge's default panic and log handlers when Dart starts the library.
#[flutter_rust_bridge::frb(init)]
pub fn init_app() {
    flutter_rust_bridge::setup_default_user_utils();
}
