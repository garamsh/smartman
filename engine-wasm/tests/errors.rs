//! A refused input reaches JavaScript as a returned `EngineError` it can switch on, not a throw.

use smartman_engine_wasm::{Answer, MemoryStateParts, review_card};
use tsify::Tsify;
use wasm_bindgen::prelude::*;
use wasm_bindgen_test::wasm_bindgen_test;

const DAY: i64 = 86_400;

#[wasm_bindgen(inline_js = r#"
export function describe(outcome) {
  if (typeof outcome !== "object" || outcome === null) return `not an object: ${typeof outcome}`;
  if ("ok" in outcome) return "ok";
  const error = outcome.error;
  switch (error.kind) {
    case "reviewBeforeLastReview":
      return `reviewBeforeLastReview ${typeof error.lastReview} ${error.lastReview} ${error.review}`;
    case "unknownRating":
      return `unknownRating ${error.value}`;
    case "nonFinite":
      return `nonFinite ${error.quantity}`;
    case "outOfRange":
      return `outOfRange ${error.quantity} ${error.value}`;
    default:
      return `unknown kind: ${String(error.kind)}`;
  }
}
"#)]
extern "C" {
    /// Reads an operation's returned value as JavaScript switching on its `EngineError` would.
    fn describe(outcome: JsValue) -> String;
}

fn review_at(at: i64, fuzz_factor: Option<f64>) -> String {
    let state = MemoryStateParts {
        stability: 3.0,
        difficulty: 5.0,
        last_review: 10 * DAY,
    };
    let outcome = review_card(
        state.into_ts().expect("the state serializes"),
        Answer::Know.into_ts().expect("the answer serializes"),
        at,
        fuzz_factor,
    )
    .expect("a refusal is returned, not thrown");
    describe(outcome.into())
}

#[wasm_bindgen_test]
fn a_review_before_the_last_review_returns_its_engine_error() {
    assert_eq!(
        review_at(10 * DAY - 1, None),
        "reviewBeforeLastReview bigint 864000 863999"
    );
    // Control: a review at the same instant is accepted.
    assert_eq!(review_at(10 * DAY, None), "ok");
}

#[wasm_bindgen_test]
fn a_fuzz_factor_out_of_range_returns_its_engine_error() {
    assert_eq!(review_at(12 * DAY, Some(1.0)), "outOfRange fuzzFactor 1");
    // Control: the greatest factor below 1 is accepted.
    assert_eq!(review_at(12 * DAY, Some(0.999)), "ok");
}
