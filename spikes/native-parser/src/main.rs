use pulldown_cmark::{Options, Parser, html};
fn compare_comrak() {
    let cases: serde_json::Value =
        serde_json::from_str(include_str!("../../../fixtures/commonmark-0.31.2.json")).unwrap();
    let mut options = comrak::Options::default();
    options.render.r#unsafe = true;
    let mut failed = Vec::new();
    for c in cases.as_array().unwrap() {
        let actual = comrak::markdown_to_html(c["markdown"].as_str().unwrap(), &options);
        if actual != c["html"].as_str().unwrap() {
            failed.push(c["example"].as_u64().unwrap());
        }
    }
    assert!(failed.is_empty(), "comrak CommonMark drift");
    println!(
        "comrak 0.59.0 CommonMark exact {}/652; nonmatches: {:?}",
        652 - failed.len(),
        failed
    );
    let cases: serde_json::Value =
        serde_json::from_str(include_str!("../../../fixtures/gfm-0.29.json")).unwrap();
    options.extension.table = true;
    options.extension.strikethrough = true;
    options.extension.autolink = true;
    options.extension.tasklist = true;
    for parser in ["comrak", "pulldown"] {
        let mut failed = Vec::new();
        for c in cases.as_array().unwrap() {
            let source = c["markdown"].as_str().unwrap();
            let actual = if parser == "comrak" {
                comrak::markdown_to_html(source, &options)
            } else {
                let mut out = String::new();
                let flags = Options::ENABLE_TABLES
                    | Options::ENABLE_STRIKETHROUGH
                    | Options::ENABLE_TASKLISTS
                    | Options::ENABLE_GFM;
                html::push_html(&mut out, Parser::new_ext(source, flags));
                out
            };
            if actual != c["html"].as_str().unwrap() {
                failed.push(c["example"].as_u64().unwrap());
                if std::env::args().any(|a| a == "--diffs") {
                    println!(
                        "{}",
                        serde_json::json!({"parser":parser,"example":c["example"],"expected":c["html"],"actual":actual})
                    );
                }
            }
        }
        let expected = if parser == "comrak" {
            vec![279, 280, 652]
        } else {
            vec![
                198, 199, 200, 201, 202, 204, 205, 279, 280, 621, 622, 623, 624, 625, 626, 627,
                628, 629, 630, 631, 652,
            ]
        };
        assert_eq!(failed, expected, "GFM comparison drift requires review");
        println!(
            "{parser} GFM extension exact {}/24; nonmatches: {:?}",
            24 - failed.len(),
            failed
        );
    }
}
fn main() {
    compare_comrak();
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

#[cfg(test)]
mod source_mapping {
    fn starts(source: &str) -> Vec<usize> {
        let b = source.as_bytes();
        let mut out = vec![0];
        let mut i = 0;
        while i < b.len() {
            if b[i] == b'\r' {
                if i + 1 < b.len() && b[i + 1] == b'\n' {
                    i += 1;
                }
                out.push(i + 1);
            } else if b[i] == b'\n' {
                out.push(i + 1);
            }
            i += 1;
        }
        out
    }
    fn utf16_offset(source: &str, byte: usize) -> Option<usize> {
        source.get(..byte).map(|s| s.encode_utf16().count())
    }
    #[test]
    fn byte_positions_map_to_utf16_without_normalizing_source() {
        for newline in ["\n", "\r\n", "\r"] {
            let source = format!("title{newline}{newline}😀 **café** 中文{newline}");
            let arena = comrak::Arena::new();
            let root = comrak::parse_document(&arena, &source, &comrak::Options::default());
            let lines = starts(&source);
            let mut found = false;
            for node in root.descendants() {
                let data = node.data.borrow();
                if matches!(data.value, comrak::nodes::NodeValue::Strong) {
                    let p = data.sourcepos;
                    let start = lines[p.start.line - 1] + p.start.column - 1;
                    let end = lines[p.end.line - 1] + p.end.column;
                    assert_eq!(&source[start..end], "**café**");
                    let a = utf16_offset(&source, start).unwrap();
                    let b = utf16_offset(&source, end).unwrap();
                    assert_eq!(
                        String::from_utf16(&source.encode_utf16().collect::<Vec<_>>()[a..b])
                            .unwrap(),
                        "**café**"
                    );
                    found = true;
                }
            }
            assert!(found);
        }
    }
    #[test]
    fn commonmark_native_positions_are_classified_before_mapping() {
        let cases: serde_json::Value =
            serde_json::from_str(include_str!("../../../fixtures/commonmark-0.31.2.json")).unwrap();
        let (mut mapped, mut unspecified, mut invalid) = (0, 0, Vec::new());
        for case in cases.as_array().unwrap() {
            let source = case["markdown"].as_str().unwrap();
            let lines = starts(source);
            let arena = comrak::Arena::new();
            let root = comrak::parse_document(&arena, source, &comrak::Options::default());
            for node in root.descendants() {
                let data = node.data.borrow();
                let p = data.sourcepos;
                if p.start.line == 0 || p.end.line == 0 || p.start.column == 0 || p.end.column == 0
                {
                    unspecified += 1;
                    continue;
                }
                let a = lines
                    .get(p.start.line - 1)
                    .map(|base| base + p.start.column - 1);
                let b = lines.get(p.end.line - 1).map(|base| base + p.end.column);
                if let (Some(a), Some(b)) = (a, b) {
                    if a <= b
                        && utf16_offset(source, a).is_some()
                        && utf16_offset(source, b).is_some()
                    {
                        mapped += 1;
                        continue;
                    }
                }
                invalid.push(case["example"].as_u64().unwrap());
            }
        }
        println!(
            "native AST positions mapped={mapped}, unspecified={unspecified}, invalid examples={invalid:?}"
        );
        assert_eq!(mapped, 3301);
        assert_eq!(unspecified, 6);
        assert!(invalid.is_empty());
    }
    #[test]
    fn scalar_boundaries_and_mid_scalar_rejection() {
        let source = "a😀e\u{301}中";
        assert_eq!(utf16_offset(source, 1), Some(1));
        assert_eq!(utf16_offset(source, 5), Some(3));
        for byte in [2, 3, 4, 7, 9, 10] {
            assert_eq!(utf16_offset(source, byte), None);
        }
        assert_eq!(utf16_offset(source, source.len()), Some(6));
    }
}
