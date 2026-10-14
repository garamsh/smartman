//! Correcting the last answer by replaying the history with that rating changed.

use smartman_engine::{Answer, Rating, Review, Timestamp, replay, review};

const DAY: i64 = 86_400;

fn history() -> Vec<Review> {
    [(0, Answer::Know), (2, Answer::Know), (13, Answer::Know)]
        .into_iter()
        .map(|(day, answer)| Review {
            rating: answer.into(),
            at: Timestamp(day * DAY),
        })
        .collect()
}

#[test]
fn flipping_the_last_good_to_again_equals_reviewing_fresh_with_again() {
    let original = history();
    let (last, earlier) = original.split_last().expect("history is not empty");
    assert_eq!(last.rating, Rating::Good);

    let reviewed = replay(earlier).expect("history is in order");
    let fresh_again = review(reviewed.as_ref(), Rating::Again, last.at, None)
        .expect("review is after the last")
        .0;
    let fresh_good = review(reviewed.as_ref(), Rating::Good, last.at, None)
        .expect("review is after the last")
        .0;

    let mut corrected = original.clone();
    corrected.last_mut().expect("history is not empty").rating = Rating::Again;

    assert_eq!(replay(&corrected), Ok(Some(fresh_again)));
    // Control: the unchanged history replays to the original state, which the flip changes.
    assert_eq!(replay(&original), Ok(Some(fresh_good)));
    assert_ne!(fresh_again, fresh_good);
}
