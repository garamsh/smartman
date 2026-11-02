//! The engine's operations as a WebAssembly module, for the web app.
//!
//! Times are whole seconds since the Unix epoch (UTC), as the engine's `Timestamp` holds
//! them, and `bigint` in TypeScript. Every engine refusal is returned as an [`EngineError`]
//! inside the [`Outcome`], never thrown. An argument TypeScript's types rule out, such as a
//! `number` for a time, is thrown, as a programming error.

#![deny(
    missing_docs,
    clippy::panic,
    clippy::unwrap_used,
    clippy::expect_used,
    clippy::indexing_slicing
)]

use serde::{Deserialize, Serialize};
use knowno_engine as engine;
use tsify::{Ts, Tsify};
use wasm_bindgen::prelude::*;

/// The app's two answer buttons.
#[derive(Tsify, Serialize, Deserialize, Clone, Copy, Debug, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum Answer {
    /// "Know": rated `Good`.
    Know,
    /// "Don't know": rated `Again`.
    DontKnow,
}

/// The parts of a card's memory state that a caller persists.
#[derive(Tsify, Serialize, Deserialize, Clone, Copy, Debug, PartialEq)]
#[serde(rename_all = "camelCase")]
#[tsify(large_number_types_as_bigints)]
pub struct MemoryStateParts {
    /// Days until retrievability falls to 0.9.
    pub stability: f64,
    /// Difficulty, from 1 to 10.
    pub difficulty: f64,
    /// Time of the review that produced this state.
    pub last_review: i64,
}

/// A card's state after a review, and when it is next due.
#[derive(Tsify, Serialize, Deserialize, Clone, Copy, Debug, PartialEq)]
#[serde(rename_all = "camelCase")]
#[tsify(large_number_types_as_bigints)]
pub struct Scheduled {
    /// The new memory state.
    pub state: MemoryStateParts,
    /// When the card is next due.
    pub due: i64,
}

/// One review in a card's history.
#[derive(Tsify, Serialize, Deserialize, Clone, Copy, Debug, PartialEq)]
#[serde(rename_all = "camelCase")]
#[tsify(large_number_types_as_bigints)]
pub struct ReviewRecord {
    /// The answer given.
    pub answer: Answer,
    /// When it was given.
    pub at: i64,
}

/// A card as today's list reads it: when it is due, absent for a card never reviewed, and its
/// reviews, in any order, those outside the study day included or not.
#[derive(Tsify, Serialize, Deserialize, Clone, Debug, PartialEq)]
#[serde(rename_all = "camelCase")]
#[tsify(large_number_types_as_bigints, missing_as_null)]
pub struct TodayCard {
    /// When the card is due.
    pub due: Option<i64>,
    /// The card's reviews.
    pub reviews: Vec<ReviewRecord>,
}

/// Where a card stands in today's list.
#[derive(Tsify, Serialize, Deserialize, Clone, Copy, Debug, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum Today {
    /// Not in today's list: not due before the day ends and not answered in it.
    Absent,
    /// Still to study today: due before the day ends and not answered in it, or answered
    /// "Don't know" last in it.
    Left,
    /// Done today: answered "Know" last in it.
    Done,
}

/// A floating-point quantity the engine takes.
#[derive(Tsify, Serialize, Deserialize, Clone, Copy, Debug, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum Quantity {
    /// Stability: at least 0.001 days.
    Stability,
    /// Difficulty: from 1 to 10.
    Difficulty,
    /// Fuzz factor: from 0, inclusive, to 1, exclusive.
    FuzzFactor,
}

/// Why the engine refused its input; one variant per engine `Error` variant, told apart by `kind`.
#[derive(Tsify, Serialize, Deserialize, Clone, Copy, Debug, PartialEq)]
#[serde(
    tag = "kind",
    rename_all = "camelCase",
    rename_all_fields = "camelCase"
)]
#[tsify(large_number_types_as_bigints)]
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

/// What an operation returns: its value under `ok`, or the engine's refusal under `error`.
#[derive(Tsify, Serialize, Deserialize, Clone, Copy, Debug, PartialEq)]
#[serde(rename_all = "camelCase")]
#[tsify(large_number_types_as_bigints, missing_as_null)]
pub enum Outcome<T> {
    /// The operation's value.
    Ok(T),
    /// Why the engine refused the input.
    Error(EngineError),
}

/// Reviews a new card for the first time, its interval fuzzed by the fuzz factor, a value
/// in `[0, 1)`, or not fuzzed when it is absent.
#[wasm_bindgen(js_name = reviewNewCard, unchecked_return_type = "Outcome<Scheduled>")]
pub fn review_new_card(
    answer: Ts<Answer>,
    at: i64,
    #[wasm_bindgen(js_name = fuzzFactor)] fuzz_factor: Option<f64>,
) -> Result<Ts<Outcome<Scheduled>>, JsError> {
    let answer = answer.to_rust()?;
    let scheduled = fuzz(fuzz_factor).and_then(|fuzz| {
        engine::review(None, answer.into(), engine::Timestamp(at), fuzz).map(scheduled)
    });
    Ok(outcome(scheduled).into_ts()?)
}

/// Reviews a card whose state the caller persisted as `state`, its interval fuzzed by
/// the fuzz factor, a value in `[0, 1)`, or not fuzzed when it is absent.
#[wasm_bindgen(js_name = reviewCard, unchecked_return_type = "Outcome<Scheduled>")]
pub fn review_card(
    state: Ts<MemoryStateParts>,
    answer: Ts<Answer>,
    at: i64,
    #[wasm_bindgen(js_name = fuzzFactor)] fuzz_factor: Option<f64>,
) -> Result<Ts<Outcome<Scheduled>>, JsError> {
    let state = state.to_rust()?;
    let answer = answer.to_rust()?;
    let scheduled = engine::MemoryState::try_from(state).and_then(|state| {
        let fuzz = fuzz(fuzz_factor)?;
        engine::review(Some(&state), answer.into(), engine::Timestamp(at), fuzz).map(scheduled)
    });
    Ok(outcome(scheduled).into_ts()?)
}

/// Replays a history, in the order the reviews happened, into the card's state; `null` when empty.
#[wasm_bindgen(unchecked_return_type = "Outcome<MemoryStateParts | null>")]
pub fn replay(
    history: Vec<Ts<ReviewRecord>>,
) -> Result<Ts<Outcome<Option<MemoryStateParts>>>, JsError> {
    let history = history
        .into_iter()
        .map(|record| record.to_rust().map(engine::Review::from))
        .collect::<Result<Vec<_>, _>>()?;
    let state = engine::replay(&history).map(|state| state.map(MemoryStateParts::from));
    Ok(outcome(state).into_ts()?)
}

/// Probability of recall at `at` of a card whose state the caller persisted as `state`.
#[wasm_bindgen(unchecked_return_type = "Outcome<number>")]
pub fn retrievability(state: Ts<MemoryStateParts>, at: i64) -> Result<Ts<Outcome<f64>>, JsError> {
    let state = state.to_rust()?;
    let recall = engine::MemoryState::try_from(state)
        .and_then(|state| state.retrievability(engine::Timestamp(at)));
    Ok(outcome(recall).into_ts()?)
}

/// Where each card stands in the list of the study day from `dayStart`, inclusive, to `dayEnd`,
/// exclusive, in the order given.
#[wasm_bindgen(js_name = todaysList, unchecked_return_type = "Today[]")]
pub fn todays_list(
    cards: Vec<Ts<TodayCard>>,
    #[wasm_bindgen(js_name = dayStart)] day_start: i64,
    #[wasm_bindgen(js_name = dayEnd)] day_end: i64,
) -> Result<Vec<Ts<Today>>, JsError> {
    let day = engine::StudyDay {
        start: engine::Timestamp(day_start),
        end: engine::Timestamp(day_end),
    };
    cards
        .into_iter()
        .map(|card| {
            let card = card.to_rust()?;
            let reviews: Vec<engine::Review> =
                card.reviews.into_iter().map(engine::Review::from).collect();
            let today = engine::today(card.due.map(engine::Timestamp), &reviews, day);
            Ok(Today::from(today).into_ts()?)
        })
        .collect()
}

fn outcome<T>(result: Result<T, engine::Error>) -> Outcome<T> {
    match result {
        Ok(value) => Outcome::Ok(value),
        Err(error) => Outcome::Error(error.into()),
    }
}

fn fuzz(factor: Option<f64>) -> Result<Option<engine::FuzzFactor>, engine::Error> {
    factor.map(engine::FuzzFactor::new).transpose()
}

fn scheduled((state, due): (engine::MemoryState, engine::Timestamp)) -> Scheduled {
    Scheduled {
        state: state.into(),
        due: due.0,
    }
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

impl From<engine::Today> for Today {
    fn from(today: engine::Today) -> Self {
        match today {
            engine::Today::Absent => Today::Absent,
            engine::Today::Left => Today::Left,
            engine::Today::Done => Today::Done,
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
