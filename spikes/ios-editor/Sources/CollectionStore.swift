import Foundation
import Darwin

struct StoredDocument: Sendable {
    let collection: String
    let name: String
    let source: String
    let baseline: Data
    let durabilityWarning: String?

    init(collection: String, name: String, source: String, baseline: Data, durabilityWarning: String? = nil) {
        self.collection = collection
        self.name = name
        self.source = source
        self.baseline = baseline
        self.durabilityWarning = durabilityWarning
    }
}

enum CollectionStoreError: Error, LocalizedError, Sendable, Equatable {
    case invalidRoot
    case invalidName(String)
    case collision(String)
    case notFound(String)
    case unsafeEntry(String)
    case collectionLimit
    case documentLimit
    case tooLarge
    case invalidUTF8
    case conflict
    case io(operation: String, code: Int32)
    case collectionDurabilityUncertain(String)

    var errorDescription: String? {
        switch self {
        case .invalidRoot: "The collection folder must be an absolute app-owned file URL with no symbolic links."
        case .invalidName(let name): "“\(name)” is not a supported name. Use a visible name without separators, control characters, reserved names, or a trailing dot or space; documents must end in .md or .mrk."
        case .collision(let name): "“\(name)” already exists, including equivalent capitalization or Unicode spelling."
        case .notFound(let name): "“\(name)” no longer exists."
        case .unsafeEntry(let name): "“\(name)” is not a supported ordinary file or folder. Symbolic links and multiply linked files are refused."
        case .collectionLimit: "This folder supports at most 64 collections."
        case .documentLimit: "A collection supports at most 512 documents."
        case .tooLarge: "Documents must be at most 1 MiB of UTF-8."
        case .invalidUTF8: "The document is not valid UTF-8. Its bytes have not been changed."
        case .conflict: "Another saved version was found. It has not been overwritten. Your edits remain open."
        case .io(let operation, let code): "Storage could not \(operation) (system error \(code))."
        case .collectionDurabilityUncertain(let name): "“\(name)” was created, but its folder could not be synchronized to storage."
        }
    }
}

/// One actor owns one private container folder. All operations are synchronous within
/// actor isolation. This is not coordination with uncooperative external processes.
/// The caller supplies a canonical app-container parent; no root path component is
/// followed through a symlink. No import, deletion, synchronization, or recovery API.
actor CollectionStore {
    static let maximumDocumentBytes = 1_048_576
    static let maximumCollections = 64
    static let maximumDocuments = 512
    private let root: URL

    init(root: URL) { self.root = root }

    func collections() throws -> [String] {
        let directory = try openRoot()
        defer { Darwin.close(directory) }
        return try collectionNames(directory)
    }

    func createCollection(_ name: String) throws {
        try validateName(name)
        let directory = try openRoot()
        defer { Darwin.close(directory) }
        let names = try collectionNames(directory)
        try refuseCollision(name, names: names)
        guard names.count < Self.maximumCollections else { throw CollectionStoreError.collectionLimit }
        guard mkdirat(directory, name, 0o700) == 0 else {
            if errno == EEXIST { throw CollectionStoreError.collision(name) }
            throw failure("create collection")
        }
        guard fsync(directory) == 0 else { throw CollectionStoreError.collectionDurabilityUncertain(name) }
    }

    func documents(in collection: String) throws -> [String] {
        let directory = try openCollection(collection)
        defer { Darwin.close(directory) }
        return try documentNames(directory)
    }

    func createDocument(collection: String, name: String, source: String = "") throws -> StoredDocument {
        try validateName(name, document: true)
        let bytes = try encoded(source)
        let directory = try openCollection(collection)
        defer { Darwin.close(directory) }
        let names = try documentNames(directory)
        try refuseCollision(name, names: names)
        guard names.count < Self.maximumDocuments else { throw CollectionStoreError.documentLimit }
        let temporary = try writeTemporary(bytes, in: directory)
        defer { _ = unlinkat(directory, temporary, 0) }
        // Linking a fully written temporary inode publishes without clobbering an
        // existing destination, even if one appears after the directory listing.
        guard linkat(directory, temporary, directory, name, 0) == 0 else {
            if errno == EEXIST { throw CollectionStoreError.collision(name) }
            throw failure("publish document")
        }
        let cleanupFailed = unlinkat(directory, temporary, 0) != 0
        let warning = committedWarning(directory, cleanupFailed: cleanupFailed)
        return StoredDocument(collection: collection, name: name, source: source, baseline: bytes, durabilityWarning: warning)
    }

    func open(collection: String, name: String) throws -> StoredDocument {
        try validateName(name, document: true)
        let directory = try openCollection(collection)
        defer { Darwin.close(directory) }
        try requireExactName(name, names: documentNames(directory))
        let bytes = try readDocument(name, in: directory)
        let source = String(decoding: bytes, as: UTF8.self)
        // Round-trip validation rejects repaired/overlong encodings and preserves
        // a leading BOM as authored source, unlike BOM-aware Foundation decoders.
        guard source.utf8.elementsEqual(bytes) else { throw CollectionStoreError.invalidUTF8 }
        return StoredDocument(collection: collection, name: name, source: source, baseline: bytes)
    }

    func save(_ document: StoredDocument, source: String) throws -> StoredDocument {
        try validateName(document.name, document: true)
        let bytes = try encoded(source)
        let directory = try openCollection(document.collection)
        defer { Darwin.close(directory) }
        try requireExactName(document.name, names: documentNames(directory))
        guard try readDocument(document.name, in: directory) == document.baseline else { throw CollectionStoreError.conflict }
        let temporary = try writeTemporary(bytes, in: directory)
        defer { _ = unlinkat(directory, temporary, 0) }
        // Recheck after writing as a courtesy to accidental outside writers. The
        // actor's guarantee is serialization of its own operations, not a POSIX CAS.
        guard try readDocument(document.name, in: directory) == document.baseline else { throw CollectionStoreError.conflict }
        guard renameat(directory, temporary, directory, document.name) == 0 else { throw failure("replace document") }
        // Replacement already committed. A directory fsync failure must not discard
        // the new baseline or invite a retry using the stale baseline.
        return StoredDocument(collection: document.collection, name: document.name, source: source, baseline: bytes,
                              durabilityWarning: committedWarning(directory))
    }

    private func openRoot() throws -> Int32 {
        let path = root.path
        let parts = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard root.isFileURL, path.hasPrefix("/"), !parts.isEmpty, parts.count <= 256,
              path.utf8.count <= 4096, !path.utf8.contains(0),
              parts.allSatisfy({ $0 != "." && $0 != ".." }) else { throw CollectionStoreError.invalidRoot }
        var directory = Darwin.open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
        guard directory >= 0 else { throw failure("open container") }
        do {
            for (index, part) in parts.enumerated() {
                var child = openat(directory, part, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
                if child < 0, errno == ENOENT, index == parts.count - 1 {
                    if mkdirat(directory, part, 0o700) != 0, errno != EEXIST { throw failure("create collection folder") }
                    guard fsync(directory) == 0 else { throw failure("synchronize collection folder") }
                    child = openat(directory, part, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
                }
                guard child >= 0 else { throw CollectionStoreError.unsafeEntry(part) }
                Darwin.close(directory)
                directory = child
            }
            return directory
        } catch {
            Darwin.close(directory)
            throw error
        }
    }

    private func openCollection(_ name: String) throws -> Int32 {
        try validateName(name)
        let directory = try openRoot()
        defer { Darwin.close(directory) }
        try requireExactName(name, names: collectionNames(directory))
        let child = openat(directory, name, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
        guard child >= 0 else { throw CollectionStoreError.unsafeEntry(name) }
        return child
    }

    private func collectionNames(_ directory: Int32) throws -> [String] {
        try names(in: directory, limit: Self.maximumCollections, documents: false)
    }

    private func documentNames(_ directory: Int32) throws -> [String] {
        try names(in: directory, limit: Self.maximumDocuments, documents: true)
    }

    private func names(in directory: Int32, limit: Int, documents: Bool) throws -> [String] {
        // Opening "." creates an independent directory offset. dup() alone would
        // share the offset and could make a subsequent listing appear empty.
        let listing = openat(directory, ".", O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
        guard listing >= 0 else { throw failure("list folder") }
        guard let stream = fdopendir(listing) else { Darwin.close(listing); throw failure("list folder") }
        defer { closedir(stream) }
        var result: [String] = []
        var keys = Set<String>()
        while true {
            errno = 0
            guard let entry = readdir(stream) else {
                if errno != 0 { throw failure("read folder entries") }
                break
            }
            let nameLength = Int(entry.pointee.d_namlen)
            let name = withUnsafePointer(to: &entry.pointee.d_name) { pointer in
                String(bytes: UnsafeRawBufferPointer(start: UnsafeRawPointer(pointer), count: nameLength), encoding: .utf8)
            }
            guard let name else { throw CollectionStoreError.unsafeEntry("non-UTF-8 name") }
            if name == "." || name == ".." { continue }
            guard result.count < limit else {
                throw documents ? CollectionStoreError.documentLimit : CollectionStoreError.collectionLimit
            }
            try validateName(name, document: documents)
            try checkType(name, in: directory, directoryExpected: !documents)
            guard keys.insert(collisionKey(name)).inserted else { throw CollectionStoreError.collision(name) }
            result.append(name)
        }
        return result.sorted { collisionKey($0) < collisionKey($1) }
    }

    private func checkType(_ name: String, in directory: Int32, directoryExpected: Bool) throws {
        var info = stat()
        guard fstatat(directory, name, &info, AT_SYMLINK_NOFOLLOW) == 0 else { throw failure("inspect entry") }
        let expected = directoryExpected ? mode_t(S_IFDIR) : mode_t(S_IFREG)
        guard info.st_mode & mode_t(S_IFMT) == expected, directoryExpected || info.st_nlink == 1 else {
            throw CollectionStoreError.unsafeEntry(name)
        }
    }

    private func readDocument(_ name: String, in directory: Int32) throws -> Data {
        // O_NONBLOCK prevents a replaced FIFO from blocking before fstat rejects it.
        let file = openat(directory, name, O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK)
        guard file >= 0 else { throw CollectionStoreError.unsafeEntry(name) }
        defer { Darwin.close(file) }
        var info = stat()
        guard fstat(file, &info) == 0 else { throw failure("inspect document") }
        guard info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG), info.st_nlink == 1 else { throw CollectionStoreError.unsafeEntry(name) }
        guard info.st_size >= 0, info.st_size <= Self.maximumDocumentBytes else { throw CollectionStoreError.tooLarge }
        var bytes = Data()
        var buffer = [UInt8](repeating: 0, count: 16_384)
        while true {
            let count = buffer.withUnsafeMutableBytes { Darwin.read(file, $0.baseAddress, $0.count) }
            if count < 0 {
                if errno == EINTR { continue }
                throw failure("read document")
            }
            if count == 0 { return bytes }
            guard bytes.count + count <= Self.maximumDocumentBytes else { throw CollectionStoreError.tooLarge }
            bytes.append(contentsOf: buffer.prefix(count))
        }
    }

    private func writeTemporary(_ bytes: Data, in directory: Int32) throws -> String {
        let name = ".markright-write-" + UUID().uuidString
        let file = openat(directory, name, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, mode_t(0o600))
        guard file >= 0 else { throw failure("create temporary document") }
        var completed = false
        defer {
            Darwin.close(file)
            if !completed { _ = unlinkat(directory, name, 0) }
        }
        try bytes.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let count = Darwin.write(file, buffer.baseAddress!.advanced(by: offset), buffer.count - offset)
                if count < 0, errno == EINTR { continue }
                guard count > 0 else { throw failure("write document") }
                offset += count
            }
        }
        guard fsync(file) == 0 else { throw failure("synchronize document") }
        completed = true
        return name
    }

    private func committedWarning(_ directory: Int32, cleanupFailed: Bool = false) -> String? {
        let synchronized = fsync(directory) == 0
        if !synchronized { return "The document was written, but storage durability could not be confirmed. Keep it open and retry saving." }
        if cleanupFailed { return "The document was written, but storage cleanup failed. Keep it open and retry saving." }
        return nil
    }

    private func encoded(_ source: String) throws -> Data {
        guard source.utf8.count <= Self.maximumDocumentBytes else { throw CollectionStoreError.tooLarge }
        return Data(source.utf8)
    }

    private func validateName(_ name: String, document: Bool = false) throws {
        let invalid = CollectionStoreError.invalidName(name)
        guard !name.isEmpty, name.utf8.count <= 255, !name.hasPrefix("."),
              !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) || "/\\:*?\"<>|".unicodeScalars.contains($0) }),
              let last = name.unicodeScalars.last, last != ".", !CharacterSet.whitespacesAndNewlines.contains(last) else { throw invalid }
        let stem = String(name.split(separator: ".", omittingEmptySubsequences: false)[0]).uppercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let reserved = ["CON", "PRN", "AUX", "NUL", "CLOCK$", "CONIN$", "CONOUT$", "COM¹", "COM²", "COM³", "LPT¹", "LPT²", "LPT³"]
            + (1...9).flatMap { ["COM\($0)", "LPT\($0)"] }
        guard !reserved.contains(stem) else { throw invalid }
        if document {
            guard let dot = name.lastIndex(of: "."), dot != name.startIndex,
                  ["md", "mrk"].contains(name[name.index(after: dot)...].lowercased()) else { throw invalid }
        }
    }

    private func collisionKey(_ name: String) -> String {
        name.precomposedStringWithCanonicalMapping.folding(options: [.caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .precomposedStringWithCanonicalMapping
    }

    private func refuseCollision(_ name: String, names: [String]) throws {
        guard !names.contains(where: { collisionKey($0) == collisionKey(name) }) else { throw CollectionStoreError.collision(name) }
    }

    private func requireExactName(_ name: String, names: [String]) throws {
        guard names.contains(where: { $0.utf8.elementsEqual(name.utf8) }) else { throw CollectionStoreError.notFound(name) }
    }

    private func failure(_ operation: String) -> CollectionStoreError { .io(operation: operation, code: errno) }
}
