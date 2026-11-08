use pulldown_cmark::{Options, Parser, html};
fn main() {
    let cases: serde_json::Value =
        serde_json::from_str(include_str!("../../../fixtures/commonmark-0.31.2.json")).unwrap();
    let mut passed = 0;
    let mut failed = Vec::new();
    for case in cases.as_array().unwrap() {
        let source = case["markdown"].as_str().unwrap();
        let expected = case["html"].as_str().unwrap();
        let mut actual = String::new();
        // Normative HTML string comparison only. Never render fixture output.
        html::push_html(&mut actual, Parser::new_ext(source, Options::empty()));
        if actual == expected {
            passed += 1;
        } else {
            failed.push(case["example"].as_u64().unwrap());
            if std::env::args().any(|arg| arg == "--diffs") {
                println!(
                    "{}",
                    serde_json::json!({"example":case["example"],"source":source,"expected":expected,"actual":actual})
                );
            }
        }
        for (_, range) in Parser::new_ext(source, Options::empty()).into_offset_iter() {
            assert!(range.start <= range.end && range.end <= source.len());
            assert!(source.is_char_boundary(range.start) && source.is_char_boundary(range.end));
        }
    }
    assert_eq!(
        failed,
        vec![
            12, 14, 27, 41, 91, 175, 209, 210, 211, 343, 352, 359, 363, 380, 385, 395, 508, 590,
            619, 620, 624, 632
        ],
        "Pinned comparison drift requires review"
    );
    println!(
        "pulldown-cmark 0.13.6 CommonMark 0.31.2: {passed}/652 exact HTML matches; nonmatches: {failed:?}"
    );
}
