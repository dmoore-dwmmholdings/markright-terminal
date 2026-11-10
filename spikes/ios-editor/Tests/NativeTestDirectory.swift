import Foundation
import Darwin

/// Resolve only the OS-provided trusted temporary parent. Foundation on macOS
/// can shorten /private/var back to the /var symlink, which is intentionally
/// refused by the store's component-by-component O_NOFOLLOW traversal.
enum NativeTestDirectory {
    static func parent() throws -> URL {
        let temporary = FileManager.default.temporaryDirectory.path
        guard let physical = temporary.withCString({ realpath($0, nil) }) else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        defer { free(physical) }
        return URL(fileURLWithPath: String(cString: physical), isDirectory: true)
    }
}
