import Foundation

// Headless executable checks: no AppKit, WebKit, application launch or network.
let page = URL(fileURLWithPath: "/synthetic/Editor/index.html")
let policy = BundledNavigationPolicy(pageURL: page)
let cases: [(String?, Bool, Bool, Bool)] = [
    (page.absoluteString, true, false, true),
    (page.absoluteString + "#section", true, false, true),
    ("file:///synthetic/Editor/../Editor/index.html", true, false, true),
    (nil, true, false, false),
    ("https://example.invalid/", true, false, false),
    ("http://127.0.0.1:18790/", true, false, false),
    ("javascript:alert(1)", true, false, false),
    ("data:text/html,example", true, false, false),
    ("file:///etc/passwd", true, false, false),
    ("file:///synthetic/Editor/bundle.js", true, false, false),
    ("file:///synthetic/Editor/index.html?query", true, false, false),
    ("file://remote.invalid/synthetic/Editor/index.html", true, false, false),
    (page.absoluteString, false, false, false),
    (page.absoluteString, true, true, false)
]
for (text, mainFrame, download, expected) in cases {
    let actual = policy.permits(text.flatMap(URL.init(string:)), mainFrame: mainFrame, download: download)
    precondition(actual == expected, "Unexpected navigation policy for \(text ?? "nil")")
}
print("Passed \(cases.count) headless bundled-navigation policy checks.")
