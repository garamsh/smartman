//! Today's list: a card failed today stays until it is passed today, from the day's reviews.

use smartman_engine::{Answer, Rating, Review, StudyDay, Timestamp, Today, today};

const HOUR: i64 = 3_600;

/// 2026-10-18 04:00 UTC to 2026-10-19 04:00 UTC.
const DAY: StudyDay = StudyDay {
    start: Timestamp(1_792_296_000),
    end: Timestamp(1_792_296_000 + 24 * HOUR),
};

/// An answer `hours` after the day's start; negative is before it.
fn at(hours: i64, answer: Answer) -> Review {
    Review {
        rating: answer.into(),
        at: Timestamp(DAY.start.0 + hours * HOUR),
    }
}

/// A due time `hours` after the day's start.
fn due(hours: i64) -> Option<Timestamp> {
    Some(Timestamp(DAY.start.0 + hours * HOUR))
}

const TOMORROW: i64 = 30;

#[test]
fn a_card_due_before_the_day_ends_and_not_answered_is_left() {
    assert_eq!(today(due(5), &[], DAY), Today::Left);
    assert_eq!(today(due(-48), &[], DAY), Today::Left, "an overdue card");
    // Control: due after the day ends, it is not in today's list.
    assert_eq!(today(due(TOMORROW), &[], DAY), Today::Absent);
}

#[test]
fn a_card_never_reviewed_and_not_answered_today_is_absent() {
    assert_eq!(today(None, &[], DAY), Today::Absent);
    // Control: answered today, a new card is in today's list.
    assert_eq!(today(None, &[at(2, Answer::Know)], DAY), Today::Done);
}

#[test]
fn know_after_dont_know_is_done() {
    let reviews = [at(1, Answer::DontKnow), at(3, Answer::Know)];
    assert_eq!(today(due(TOMORROW), &reviews, DAY), Today::Done);
}

#[test]
fn dont_know_after_know_is_left() {
    let reviews = [at(1, Answer::Know), at(3, Answer::DontKnow)];
    assert_eq!(today(due(TOMORROW), &reviews, DAY), Today::Left);
}

#[test]
fn dont_know_twice_stays_left_though_its_state_falls_due_tomorrow() {
    let reviews = [at(1, Answer::DontKnow), at(3, Answer::DontKnow)];
    assert_eq!(today(due(TOMORROW), &reviews, DAY), Today::Left);
}

#[test]
fn a_card_due_today_and_failed_today_is_left_until_passed() {
    assert_eq!(today(due(2), &[at(4, Answer::DontKnow)], DAY), Today::Left);
    assert_eq!(
        today(due(2), &[at(4, Answer::DontKnow), at(5, Answer::Know)], DAY),
        Today::Done
    );
}

#[test]
fn the_latest_review_counts_whatever_their_order() {
    let reviews = [at(5, Answer::Know), at(1, Answer::DontKnow)];
    assert_eq!(today(due(TOMORROW), &reviews, DAY), Today::Done);
    let reviews = [at(5, Answer::DontKnow), at(1, Answer::Know)];
    assert_eq!(today(due(TOMORROW), &reviews, DAY), Today::Left);
}

#[test]
fn of_two_reviews_at_one_time_the_later_given_counts() {
    let reviews = [at(5, Answer::DontKnow), at(5, Answer::Know)];
    assert_eq!(today(due(TOMORROW), &reviews, DAY), Today::Done);
    let reviews = [at(5, Answer::Know), at(5, Answer::DontKnow)];
    assert_eq!(today(due(TOMORROW), &reviews, DAY), Today::Left);
}

#[test]
fn the_day_runs_from_its_start_inclusive_to_its_end_exclusive() {
    let before_start = Review {
        rating: Answer::DontKnow.into(),
        at: Timestamp(DAY.start.0 - 1),
    };
    let at_start = Review {
        rating: Answer::DontKnow.into(),
        at: DAY.start,
    };
    let at_end = Review {
        rating: Answer::DontKnow.into(),
        at: DAY.end,
    };
    // Failed a second before 04:00, the card belongs to yesterday's list.
    assert_eq!(today(due(TOMORROW), &[before_start], DAY), Today::Absent);
    // Failed at 04:00, it is today's.
    assert_eq!(today(due(TOMORROW), &[at_start], DAY), Today::Left);
    // Failed at the next 04:00, it is tomorrow's.
    assert_eq!(today(due(TOMORROW), &[at_end], DAY), Today::Absent);
    // A review before the day does not decide a card due today.
    let passed_yesterday = Review {
        rating: Answer::Know.into(),
        at: Timestamp(DAY.start.0 - 1),
    };
    assert_eq!(today(due(2), &[passed_yesterday], DAY), Today::Left);
}

#[test]
fn a_card_due_at_the_day_s_end_is_tomorrow_s() {
    assert_eq!(today(Some(DAY.end), &[], DAY), Today::Absent);
    assert_eq!(today(Some(Timestamp(DAY.end.0 - 1)), &[], DAY), Today::Left);
}

#[test]
fn a_day_whose_end_is_not_after_its_start_holds_no_review() {
    let empty = StudyDay {
        start: DAY.start,
        end: DAY.start,
    };
    assert_eq!(
        today(None, &[at(0, Answer::DontKnow)], empty),
        Today::Absent
    );
}

#[test]
fn hard_and_easy_count_as_done_as_good_does_and_again_does_not() {
    for rating in [Rating::Hard, Rating::Good, Rating::Easy] {
        let review = Review {
            rating,
            at: Timestamp(DAY.start.0 + HOUR),
        };
        assert_eq!(
            today(due(TOMORROW), &[review], DAY),
            Today::Done,
            "{rating:?}"
        );
    }
    let again = Review {
        rating: Rating::Again,
        at: Timestamp(DAY.start.0 + HOUR),
    };
    assert_eq!(today(due(TOMORROW), &[again], DAY), Today::Left);
}

#[test]
fn a_day_whose_end_is_before_its_start_holds_no_review() {
    let inverted = StudyDay {
        start: DAY.end,
        end: DAY.start,
    };
    let reviews = [at(1, Answer::DontKnow), at(25, Answer::DontKnow)];
    assert_eq!(today(None, &reviews, inverted), Today::Absent);
    // Control: the same reviews in the day as it runs.
    assert_eq!(today(None, &reviews, DAY), Today::Left);
}

#[test]
fn a_card_due_inside_the_day_with_reviews_only_outside_it_is_left() {
    let outside = [at(-2, Answer::Know), at(26, Answer::Know)];
    assert_eq!(today(due(10), &outside, DAY), Today::Left);
    // Control: a review inside the day decides it.
    assert_eq!(
        today(due(10), &[at(-2, Answer::Know), at(3, Answer::Know)], DAY),
        Today::Done
    );
}
