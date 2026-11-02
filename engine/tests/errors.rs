//! Invalid input is refused with a typed error; each refusal is paired with a control.

use knowno_engine::{
    Error, FuzzFactor, MemoryState, Quantity, Rating, Review, Timestamp, replay, review,
};

const DAY: i64 = 86_400;

fn reviewed_at(at: i64) -> MemoryState {
    review(None, Rating::Good, Timestamp(at), None)
        .expect("a new card accepts any time")
        .0
}

#[test]
fn a_review_before_the_last_review_is_refused() {
    let state = reviewed_at(10 * DAY);
    assert_eq!(
        review(Some(&state), Rating::Good, Timestamp(10 * DAY - 1), None),
        Err(Error::ReviewBeforeLastReview {
            last_review: Timestamp(10 * DAY),
            review: Timestamp(10 * DAY - 1),
        })
    );
    // Control: a review at the same instant has zero elapsed time and is accepted.
    assert!(review(Some(&state), Rating::Good, Timestamp(10 * DAY), None).is_ok());
}

#[test]
fn replaying_a_history_out_of_order_is_refused() {
    let first = Review {
        rating: Rating::Good,
        at: Timestamp(DAY),
    };
    let second = Review {
        rating: Rating::Again,
        at: Timestamp(5 * DAY),
    };
    assert_eq!(
        replay(&[second, first]),
        Err(Error::ReviewBeforeLastReview {
            last_review: Timestamp(5 * DAY),
            review: Timestamp(DAY),
        })
    );
    // Control: the same reviews in order replay.
    assert!(matches!(replay(&[first, second]), Ok(Some(_))));
}

#[test]
fn retrievability_before_the_last_review_is_refused() {
    let state = reviewed_at(10 * DAY);
    assert_eq!(
        state.retrievability(Timestamp(9 * DAY)),
        Err(Error::ReviewBeforeLastReview {
            last_review: Timestamp(10 * DAY),
            review: Timestamp(9 * DAY),
        })
    );
    // Control: at the last review nothing has elapsed, so recall is certain.
    assert_eq!(state.retrievability(Timestamp(10 * DAY)), Ok(1.0));
}

#[test]
fn a_number_outside_one_to_four_is_not_a_rating() {
    assert_eq!(Rating::try_from(0), Err(Error::UnknownRating(0)));
    assert_eq!(Rating::try_from(5), Err(Error::UnknownRating(5)));
    // Control: the four FSRS numbers parse to their ratings.
    assert_eq!(
        [1, 2, 3, 4].map(Rating::try_from),
        [
            Ok(Rating::Again),
            Ok(Rating::Hard),
            Ok(Rating::Good),
            Ok(Rating::Easy)
        ]
    );
}

#[test]
fn non_finite_parts_are_refused() {
    let at = Timestamp(0);
    for value in [f64::NAN, f64::INFINITY, f64::NEG_INFINITY] {
        assert_eq!(
            MemoryState::from_parts(value, 5.0, at),
            Err(Error::NonFinite(Quantity::Stability))
        );
        assert_eq!(
            MemoryState::from_parts(1.0, value, at),
            Err(Error::NonFinite(Quantity::Difficulty))
        );
    }
    // Control: finite parts in range are accepted.
    assert!(MemoryState::from_parts(1.0, 5.0, at).is_ok());
}

#[test]
fn out_of_range_parts_are_refused() {
    let at = Timestamp(0);
    assert_eq!(
        MemoryState::from_parts(0.0009, 5.0, at),
        Err(Error::OutOfRange {
            quantity: Quantity::Stability,
            value: 0.0009
        })
    );
    for difficulty in [0.99, 10.01] {
        assert_eq!(
            MemoryState::from_parts(1.0, difficulty, at),
            Err(Error::OutOfRange {
                quantity: Quantity::Difficulty,
                value: difficulty
            })
        );
    }
    // Control: the bounds themselves are in range.
    assert!(MemoryState::from_parts(0.001, 1.0, at).is_ok());
    assert!(MemoryState::from_parts(0.001, 10.0, at).is_ok());
}

#[test]
fn a_fuzz_factor_outside_zero_to_one_is_refused() {
    for value in [f64::NAN, f64::INFINITY, f64::NEG_INFINITY] {
        assert_eq!(
            FuzzFactor::new(value),
            Err(Error::NonFinite(Quantity::FuzzFactor))
        );
    }
    for value in [-0.001, 1.0, 1.5] {
        assert_eq!(
            FuzzFactor::new(value),
            Err(Error::OutOfRange {
                quantity: Quantity::FuzzFactor,
                value
            })
        );
    }
    // Control: 0 and the largest value below 1 are in range.
    let largest = 1.0 - f64::EPSILON / 2.0;
    assert_eq!(FuzzFactor::new(0.0).map(|factor| factor.value()), Ok(0.0));
    assert_eq!(
        FuzzFactor::new(largest).map(|factor| factor.value()),
        Ok(largest)
    );
}

#[test]
fn a_replayed_state_round_trips_through_its_parts() {
    let history: Vec<Review> = [(0, Rating::Again), (1, Rating::Good), (4, Rating::Easy)]
        .into_iter()
        .map(|(day, rating)| Review {
            rating,
            at: Timestamp(day * DAY),
        })
        .collect();
    let state = replay(&history)
        .expect("history is in order")
        .expect("history is not empty");
    let rebuilt =
        MemoryState::from_parts(state.stability(), state.difficulty(), state.last_review());
    assert_eq!(rebuilt, Ok(state));
    // A rebuilt state schedules the next review as the replayed one does.
    let next = Timestamp(30 * DAY);
    assert_eq!(
        review(rebuilt.as_ref().ok(), Rating::Good, next, None),
        review(Some(&state), Rating::Good, next, None)
    );
}
