//! The exported surface against the engine's reference values from py-fsrs, run as WebAssembly.
//!
//! The surface takes the app's two answers, so the sequences checked are those whose every
//! rating is Again or Good; the Hard and Easy sequences are checked by `engine/tests/reference.rs`.

use serde::Deserialize;
use smartman_engine_wasm::{
    Answer, MemoryStateParts, Outcome, ReviewRecord, Scheduled, replay, retrievability,
    review_card, review_new_card,
};
use tsify::{Ts, Tsify};
use wasm_bindgen_test::{console_log, wasm_bindgen_test};

/// The tolerance of `engine/tests/reference.rs`: both sides compute in IEEE 754 binary64
/// through different `exp` and `pow` implementations. Interval and due are exact.
const RELATIVE_TOLERANCE: f64 = 1e-9;

const FIXTURES: &str = include_str!("../../engine/tests/fixtures/reference.json");

const SELECTION: &str = "the sequences of engine/tests/fixtures/reference.json whose every rating is Again (1) or Good (3)";

#[derive(Deserialize)]
struct Fixtures {
    generator: String,
    /// Run without fuzzing.
    sequences: Vec<Sequence>,
    /// The same steps run with fuzzing, under fixed seeds.
    fuzzed_sequences: Vec<Sequence>,
}

#[derive(Deserialize)]
struct Sequence {
    name: String,
    seed: Option<u64>,
    reviews: Vec<Expected>,
}

#[derive(Deserialize)]
struct Expected {
    /// The factor py-fsrs drew for this review; absent when it fuzzed nothing.
    fuzz_factor: Option<f64>,
    rating: u8,
    at: i64,
    retrievability: Option<f64>,
    stability: f64,
    difficulty: f64,
    interval_days: i64,
    due: i64,
}

impl Sequence {
    /// The sequence's answers, or `None` when a rating is Hard or Easy, which no answer gives.
    fn answers(&self) -> Option<Vec<Answer>> {
        self.reviews
            .iter()
            .map(|review| match review.rating {
                1 => Some(Answer::DontKnow),
                3 => Some(Answer::Know),
                _ => None,
            })
            .collect()
    }
}

fn fixtures() -> Fixtures {
    let fixtures: Fixtures = serde_json::from_str(FIXTURES).expect("reference.json parses");
    assert_eq!(fixtures.generator, "py-fsrs 6.3.2");
    fixtures
}

fn assert_close(what: &str, actual: f64, expected: f64) {
    let error = ((actual - expected) / expected).abs();
    assert!(
        error <= RELATIVE_TOLERANCE,
        "{what}: engine {actual}, reference {expected}, relative error {error:e}"
    );
}

/// The value of an outcome the JavaScript side received, failing on a refusal.
fn ok<T>(outcome: Ts<Outcome<T>>, what: &str) -> T
where
    Outcome<T>: Tsify + serde::de::DeserializeOwned,
    <Outcome<T> as Tsify>::JsType: Clone,
{
    match outcome.to_rust().expect("the outcome deserializes") {
        Outcome::Ok(value) => value,
        Outcome::Error(error) => panic!("{what}: refused with {error:?}"),
    }
}

fn ts<T: Tsify + serde::Serialize>(value: T) -> Ts<T> {
    value.into_ts().expect("the argument serializes")
}

/// Runs every review of each sequence whose ratings are all answers through the exported
/// functions, each from the state parts the previous one returned, passing each its
/// recorded fuzz factor; returns how many sequences and reviews it checked.
fn check(sequences: &[Sequence]) -> (usize, usize) {
    let (mut checked_sequences, mut checked_reviews) = (0, 0);
    for sequence in sequences {
        let Some(answers) = sequence.answers() else {
            continue;
        };
        let name = match sequence.seed {
            Some(seed) => format!("{} seed {seed}", sequence.name),
            None => sequence.name.clone(),
        };
        let mut state: Option<MemoryStateParts> = None;
        for (index, (expected, answer)) in sequence.reviews.iter().zip(&answers).enumerate() {
            let what = format!("{name} review {index}");
            let returned = match (state, expected.retrievability) {
                (None, None) => review_new_card(ts(*answer), expected.at, expected.fuzz_factor),
                (Some(previous), Some(reference)) => {
                    let recall = retrievability(ts(previous), expected.at)
                        .expect("retrievability throws nothing");
                    assert_close(
                        &format!("{what} retrievability"),
                        ok(recall, &what),
                        reference,
                    );
                    review_card(ts(previous), ts(*answer), expected.at, expected.fuzz_factor)
                }
                _ => panic!("{what}: retrievability is present on one side only"),
            };
            let Scheduled { state: next, due } =
                ok(returned.expect("review throws nothing"), &what);
            assert_close(
                &format!("{what} stability"),
                next.stability,
                expected.stability,
            );
            assert_close(
                &format!("{what} difficulty"),
                next.difficulty,
                expected.difficulty,
            );
            assert_eq!(next.last_review, expected.at, "{what} last review");
            assert_eq!(
                (due - expected.at) / 86_400,
                expected.interval_days,
                "{what} interval days"
            );
            assert_eq!(due, expected.due, "{what} due");
            state = Some(next);
            checked_reviews += 1;
        }

        let history = sequence
            .reviews
            .iter()
            .zip(&answers)
            .map(|(review, answer)| {
                ts(ReviewRecord {
                    answer: *answer,
                    at: review.at,
                })
            })
            .collect();
        let replayed = replay(history).expect("replay throws nothing");
        assert_eq!(ok(replayed, &name), state, "{name} replay");
        checked_sequences += 1;
    }
    (checked_sequences, checked_reviews)
}

#[wasm_bindgen_test]
fn every_answer_fixture_review_matches_py_fsrs() {
    let fixtures = fixtures();
    let (sequences, reviews) = check(&fixtures.sequences);
    assert!(reviews > 0, "no review was selected by: {SELECTION}");
    console_log!(
        "checked {reviews} reviews in {sequences} of {} unfuzzed sequences from {}, selected as {SELECTION}",
        fixtures.sequences.len(),
        fixtures.generator
    );
}

#[wasm_bindgen_test]
fn every_fuzzed_answer_fixture_review_matches_py_fsrs() {
    let fixtures = fixtures();
    let fuzzed = fixtures
        .fuzzed_sequences
        .iter()
        .filter(|sequence| sequence.answers().is_some())
        .flat_map(|sequence| &sequence.reviews)
        .filter(|review| review.fuzz_factor.is_some())
        .count();
    assert!(
        fuzzed > 0,
        "no selected fuzzed review carries a fuzz factor"
    );
    let (sequences, reviews) = check(&fixtures.fuzzed_sequences);
    console_log!(
        "checked {reviews} reviews, {fuzzed} with a fuzz factor, in {sequences} of {} fuzzed sequences from {}, selected as {SELECTION}",
        fixtures.fuzzed_sequences.len(),
        fixtures.generator
    );
}
