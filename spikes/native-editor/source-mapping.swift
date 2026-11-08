import Foundation
import AppKit
// Headless TextKit storage probe. No window/application is opened.
let samples = ["A😀B\r\nnext", "cafe\u{301}\n中文", "👩🏽‍💻\n|a|b|", "```swift\r\nlet x=1\r\n```"]
for source in samples {
    let storage = NSTextStorage(string: source)
    precondition(storage.string == source)
    let full = NSRange(location: 0, length: storage.length)
    storage.addAttribute(.foregroundColor, value: NSColor.labelColor, range: full)
    precondition(storage.string == source, "Preview attributes changed source")
    precondition(storage.length == source.utf16.count)
    for index in source.indices {
        let range = NSRange(index..<source.index(after:index), in: source)
        precondition(Range(range,in:source) != nil)
        let text = (source as NSString).substring(with:range)
        precondition(text == String(source[index]))
    }
    // End-of-document insertion uses UTF-16, never grapheme count.
    storage.replaceCharacters(in:NSRange(location:storage.length,length:0),with:"\nnew")
    precondition(storage.string == source+"\nnew")
}
print("TextKit source storage: 4 Unicode/CRLF fixtures passed; no UI/IME/VoiceOver validation claimed")
