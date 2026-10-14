//! A fuzz factor moves the due time of a review, never its state.

use smartman_engine::{FuzzFactor, Rating, Timestamp, review};

const DAY: i64 = 86_400;

fn factor(value: f64) -> FuzzFactor {
    FuzzFactor::new(value).expect("factor is in [0, 1)")
}

fn interval_days(rating: Rating, fuzz: Option<FuzzFactor>) -> i64 {
    let (_, due) = review(None, rating, Timestamp(0), fuzz).expect("a new card accepts any time");
    due.0 / DAY
}

#[test]
fn a_first_good_due_in_two_days_is_not_fuzzed() {
    assert_eq!(interval_days(Rating::Good, None), 2);
    for value in [0.0, 0.5, 0.999] {
        assert_eq!(interval_days(Rating::Good, Some(factor(value))), 2);
    }
    // Control: a first Easy, due in 8 days, is fuzzed to either end of its range.
    assert_eq!(interval_days(Rating::Easy, None), 8);
    assert_eq!(interval_days(Rating::Easy, Some(factor(0.0))), 6);
    assert_eq!(interval_days(Rating::Easy, Some(factor(0.999))), 11);
}

#[test]
fn a_fuzz_factor_leaves_the_state_unchanged() {
    let fuzzed = review(None, Rating::Easy, Timestamp(0), Some(factor(0.0)));
    let plain = review(None, Rating::Easy, Timestamp(0), None);
    assert_eq!(fuzzed.map(|(state, _)| state), plain.map(|(state, _)| state));
    // Control: the due times differ, so the factor took effect.
    assert_ne!(fuzzed.map(|(_, due)| due), plain.map(|(_, due)| due));
}
