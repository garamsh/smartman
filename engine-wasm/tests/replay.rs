//! An empty history replays to `null` as JavaScript reads it, as the declared type says.

use knowno_engine_wasm::replay;
use wasm_bindgen::prelude::*;
use wasm_bindgen_test::wasm_bindgen_test;

#[wasm_bindgen(inline_js = r#"
export function describe(outcome) {
  if (!("ok" in outcome)) return "error";
  return outcome.ok === null ? "null" : typeof outcome.ok;
}
"#)]
extern "C" {
    /// Names what an `Outcome` holds under `ok`, as JavaScript sees it.
    fn describe(outcome: JsValue) -> String;
}

#[wasm_bindgen_test]
fn an_empty_history_replays_to_null() {
    let outcome = replay(Vec::new()).expect("replay throws nothing");
    assert_eq!(describe(outcome.into()), "null");
}
