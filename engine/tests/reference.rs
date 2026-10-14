//! The engine against reference values from py-fsrs, written by `fixtures/generate.py`.

use serde::Deserialize;
use smartman_engine::{MemoryState, Rating, Review, Timestamp, replay, review};

/// Relative tolerance for stability, difficulty, and retrievability.
///
/// Both sides compute in IEEE 754 binary64 through different `exp` and `pow`
/// implementations, which may differ in the last bit of each call and compound over a
/// sequence; measured on macOS, the largest error over these fixtures is below 1e-14.
/// 1e-9 leaves room for another platform's libm, and stays below the 1e-4 relative step
/// of the last digit of a four-digit default parameter. Interval and due are exact.
const RELATIVE_TOLERANCE: f64 = 1e-9;

const FIXTURES: &str = include_str!("fixtures/reference.json");

#[derive(Deserialize)]
struct Fixtures {
    generator: String,
    sequences: Vec<Sequence>,
}

#[derive(Deserialize)]
struct Sequence {
    name: String,
    reviews: Vec<Expected>,
}

#[derive(Deserialize)]
struct Expected {
    rating: u8,
    at: i64,
    retrievability: Option<f64>,
    stability: f64,
    difficulty: f64,
    interval_days: i64,
    due: i64,
}

fn rating(value: u8) -> Rating {
    Rating::try_from(value).expect("fixture rating is an FSRS rating")
}

fn assert_close(what: &str, actual: f64, expected: f64) {
    let error = ((actual - expected) / expected).abs();
    assert!(
        error <= RELATIVE_TOLERANCE,
        "{what}: engine {actual}, reference {expected}, relative error {error:e}"
    );
}

fn fixtures() -> Fixtures {
    let fixtures: Fixtures = serde_json::from_str(FIXTURES).expect("reference.json parses");
    assert_eq!(fixtures.generator, "py-fsrs 6.3.2");
    assert!(
        !fixtures.sequences.is_empty(),
        "reference.json holds no sequence"
    );
    fixtures
}

#[test]
fn every_fixture_review_matches_py_fsrs() {
    let fixtures = fixtures();
    let mut checked = 0;
    for sequence in &fixtures.sequences {
        let mut state: Option<MemoryState> = None;
        for (index, expected) in sequence.reviews.iter().enumerate() {
            let at = Timestamp(expected.at);
            let what = format!("{} review {index}", sequence.name);

            match (&state, expected.retrievability) {
                (None, None) => {}
                (Some(previous), Some(reference)) => assert_close(
                    &format!("{what} retrievability"),
                    previous
                        .retrievability(at)
                        .expect("review is not before the last"),
                    reference,
                ),
                _ => panic!("{what}: retrievability is present on one side only"),
            }

            let (next, due) = review(state.as_ref(), rating(expected.rating), at)
                .expect("fixture reviews are in order");
            assert_close(
                &format!("{what} stability"),
                next.stability(),
                expected.stability,
            );
            assert_close(
                &format!("{what} difficulty"),
                next.difficulty(),
                expected.difficulty,
            );
            assert_eq!(
                (due.0 - at.0) / 86_400,
                expected.interval_days,
                "{what} interval days"
            );
            assert_eq!(due, Timestamp(expected.due), "{what} due");

            state = Some(next);
            checked += 1;
        }

        let history: Vec<Review> = sequence
            .reviews
            .iter()
            .map(|step| Review {
                rating: rating(step.rating),
                at: Timestamp(step.at),
            })
            .collect();
        assert_eq!(replay(&history), Ok(state), "{} replay", sequence.name);
    }
    println!(
        "checked {checked} reviews in {} sequences from {}",
        fixtures.sequences.len(),
        fixtures.generator
    );
}
