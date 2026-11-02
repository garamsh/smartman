//! Today's list reaches JavaScript as one value per card, in the order given.

use knowno_engine_wasm::{Answer, ReviewRecord, TodayCard, todays_list};
use tsify::Tsify;
use wasm_bindgen::prelude::*;
use wasm_bindgen_test::wasm_bindgen_test;

const HOUR: i64 = 3_600;
/// 2026-10-18 04:00 UTC.
const START: i64 = 1_792_296_000;
const END: i64 = START + 24 * HOUR;

#[wasm_bindgen(inline_js = r#"
export function describe(value) {
  return typeof value === "string" ? value : `not a string: ${typeof value}`;
}
"#)]
extern "C" {
    /// Reads one entry of the returned list as JavaScript sees it.
    fn describe(value: JsValue) -> String;
}

fn card(due: Option<i64>, reviews: &[(Answer, i64)]) -> tsify::Ts<TodayCard> {
    TodayCard {
        due,
        reviews: reviews
            .iter()
            .map(|&(answer, at)| ReviewRecord { answer, at })
            .collect(),
    }
    .into_ts()
    .expect("the card serializes")
}

#[wasm_bindgen_test]
fn each_card_reads_as_its_place_in_today_s_list() {
    let list = todays_list(
        vec![
            card(Some(START + 5 * HOUR), &[]),
            card(Some(END + 5 * HOUR), &[(Answer::DontKnow, START + HOUR)]),
            card(
                Some(END + 5 * HOUR),
                &[
                    (Answer::DontKnow, START + HOUR),
                    (Answer::Know, START + 2 * HOUR),
                ],
            ),
            card(Some(END + 5 * HOUR), &[(Answer::Know, START - HOUR)]),
            card(None, &[]),
        ],
        START,
        END,
    )
    .expect("the list is returned");
    let read: Vec<String> = list
        .into_iter()
        .map(|today| describe(today.into()))
        .collect();
    assert_eq!(read, ["left", "left", "done", "absent", "absent"]);
}
