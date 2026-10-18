//! Today's list: which cards a study day still holds, from its reviews and the cards' due times.
//!
//! This is today's learning, apart from the long-term memory FSRS keeps: a card failed today
//! stays in today's list until it is passed today, whatever its state's due time says.

use crate::{Rating, Review, Timestamp};

/// A study day: from `start`, inclusive, to `end`, exclusive. The caller sets its bounds,
/// such as 04:00 to 04:00 in the user's zone; a day whose end is not after its start holds
/// no review.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct StudyDay {
    /// When the day begins.
    pub start: Timestamp,
    /// When the next day begins.
    pub end: Timestamp,
}

impl StudyDay {
    fn holds(&self, at: Timestamp) -> bool {
        self.start <= at && at < self.end
    }
}

/// Where a card stands in today's list.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Today {
    /// Not in today's list: not due before the day ends and not reviewed in it.
    Absent,
    /// In today's list and still to study: due before the day ends and not reviewed in it, or
    /// failed (`Again`) in its latest review of the day.
    Left,
    /// In today's list and done: its latest review of the day passed it, rated above `Again`.
    Done,
}

/// Where a card stands in `day`'s list, from its due time, `None` for a card never reviewed,
/// and its reviews, in any order; those outside the day are ignored. Of two reviews at the
/// same time, the later in `reviews` is the latest.
pub fn today(due: Option<Timestamp>, reviews: &[Review], day: StudyDay) -> Today {
    let latest = reviews.iter().filter(|review| day.holds(review.at)).fold(
        None::<&Review>,
        |latest, review| match latest {
            Some(earlier) if earlier.at > review.at => Some(earlier),
            _ => Some(review),
        },
    );
    match latest {
        Some(review) if review.rating == Rating::Again => Today::Left,
        Some(_) => Today::Done,
        None if due.is_some_and(|due| due < day.end) => Today::Left,
        None => Today::Absent,
    }
}
