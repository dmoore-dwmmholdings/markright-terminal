import Foundation
import Darwin
import CryptoKit

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
    case recoveryLimit
    case interruptedWriteLimit
    case malformedRecovery(String)

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
        case .recoveryLimit: "The recovery folder supports at most 32 entries. Preserve or restore existing drafts before adding another checkpoint."
        case .interruptedWriteLimit: "A collection supports at most 32 interrupted document writes. Its existing files have been preserved."
        case .malformedRecovery(let name): "“\(name)” is not a valid supported recovery record. It has been preserved."
        }
    }
}

/// One actor owns one private container folder. All operations are synchronous within
/// actor isolation. This is not coordination with uncooperative external processes.
/// The caller supplies a canonical app-container parent; no root path component is
/// followed through a symlink. Recovery is private research storage, not external
/// coordination, a power-loss guarantee, or a production recovery contract.
actor CollectionStore {
    static let maximumDocumentBytes = 1_048_576
    static let maximumCollections = 64
    static let maximumDocuments = 512
    static let maximumRecoveryEntries = 32
    static let maximumInterruptedWrites = 32
    static let maximumCollectionRawEntries = maximumDocuments + maximumInterruptedWrites
    static let maximumRecoveryBytes = 2 * maximumDocumentBytes + 1024
    private static let recoveryDirectoryName = ".markright-recovery"
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

    func documents(in collection: String, createRootIfMissing: Bool = true) throws -> [String] {
        let directory = try openCollection(collection, createRootIfMissing: createRootIfMissing)
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

    func open(collection: String, name: String, createRootIfMissing: Bool = true) throws -> StoredDocument {
        try validateName(name, document: true)
        let directory = try openCollection(collection, createRootIfMissing: createRootIfMissing)
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

    /// Acknowledges only after the file and its publication directory synchronize.
    /// A completed pending file is deliberately preserved if publication fails.
    func checkpoint(_ document: StoredDocument, source: String, sessionID: UUID) throws -> RecoveryDraft {
        let draft = RecoveryDraft(sessionID: sessionID, collection: document.collection,
                                  name: document.name, source: source, baseline: document.baseline)
        let bytes = try encodeRecovery(draft)
        let directory = try requiredRecoveryDirectory()
        defer { Darwin.close(directory) }
        let entries = try recoveryEntries(directory)
        // Reserve the staging slot too: the raw directory never intentionally
        // exceeds the bound, even while replacing an existing session record.
        guard entries.count < Self.maximumRecoveryEntries else { throw CollectionStoreError.recoveryLimit }
        if entries.contains(where: { $0.name == draft.fileName }) {
            _ = try readRecovery(draft.fileName, in: directory)
        }
        let pending = try writeRecoveryTemporary(bytes, in: directory)
        guard fsync(directory) == 0 else { throw failure("synchronize pending recovery record") }
        guard renameat(directory, pending, directory, draft.fileName) == 0 else { throw failure("publish recovery checkpoint") }
        guard fsync(directory) == 0 else { throw failure("synchronize recovery checkpoint") }
        return draft
    }

    /// The caller must first confirm that saving the document or a separate copy
    /// completed durably. An older token cannot remove a newer session checkpoint.
    func completeCheckpoint(_ draft: RecoveryDraft) throws {
        _ = try encodeRecovery(draft)
        try validateRecoveryFileName(draft.fileName, sessionID: draft.sessionID)
        guard let directory = try openRecoveryDirectory(create: false) else { return }
        defer { Darwin.close(directory) }
        _ = try recoveryEntries(directory)
        var info = stat()
        if fstatat(directory, draft.fileName, &info, AT_SYMLINK_NOFOLLOW) != 0 {
            guard errno == ENOENT else { throw failure("inspect recovery checkpoint") }
            guard fsync(directory) == 0 else { throw failure("synchronize completed recovery checkpoint") }
            return
        }
        try requireMatchingRecovery(draft, in: directory)
        guard unlinkat(directory, draft.fileName, 0) == 0 else { throw failure("retire recovery checkpoint") }
        guard fsync(directory) == 0 else { throw failure("synchronize completed recovery checkpoint") }
    }

    func recoveries() throws -> RecoveryInventory {
        guard let directory = try openRecoveryDirectory(create: false) else {
            return RecoveryInventory(drafts: [], issues: [])
        }
        defer { Darwin.close(directory) }
        let entries = try recoveryEntries(directory)
        var drafts: [RecoveryDraft] = []
        var issues: [String] = []
        for entry in entries {
            guard let name = entry.name else {
                issues.append("A non-UTF-8 recovery entry was preserved.")
                continue
            }
            do { drafts.append(try readRecovery(name, in: directory)) }
            catch { issues.append("\(name): \(error.localizedDescription)") }
        }
        return RecoveryInventory(drafts: drafts.sorted { $0.fileName < $1.fileName }, issues: issues.sorted())
    }

    /// Always publishes a new document through createDocument's no-clobber path.
    /// A successful copy receipt is retained even if retiring recovery then fails.
    func restoreRecovery(_ draft: RecoveryDraft, collection: String, name: String) throws -> RecoveryRestoreReceipt {
        guard let directory = try openRecoveryDirectory(create: false) else { throw CollectionStoreError.notFound(draft.fileName) }
        do {
            _ = try recoveryEntries(directory)
            try requireMatchingRecovery(draft, in: directory)
        } catch {
            Darwin.close(directory)
            throw error
        }
        Darwin.close(directory)
        let document = try createDocument(collection: collection, name: name, source: draft.source)
        if document.durabilityWarning != nil {
            return RecoveryRestoreReceipt(document: document,
                retirementWarning: "The recovery draft was retained because the recovered copy's storage durability could not be confirmed.")
        }
        do {
            try completeCheckpoint(draft)
            return RecoveryRestoreReceipt(document: document, retirementWarning: nil)
        } catch {
            return RecoveryRestoreReceipt(document: document,
                retirementWarning: "The recovered copy was saved, but recovery cleanup could not be confirmed: \(error.localizedDescription)")
        }
    }

    /// Interrupted ordinary document writes are visible evidence, never documents
    /// and never automatically deleted, including link-before-unlink artifacts.
    func interruptedWrites(in collection: String) throws -> [String] {
        let directory = try openCollection(collection)
        defer { Darwin.close(directory) }
        _ = try documentNames(directory)
        return try rawEntries(in: directory, limit: Self.maximumCollectionRawEntries,
                              limitError: .interruptedWriteLimit).compactMap { entry in
            guard let name = entry.name, name.hasPrefix(".markright-write-") else { return nil }
            try checkInterruptedWrite(name, in: directory)
            return name
        }.sorted()
    }

    private func openRoot(createRootIfMissing: Bool = true) throws -> Int32 {
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
                if child < 0, errno == ENOENT, index == parts.count - 1, createRootIfMissing {
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

    private func openCollection(_ name: String, createRootIfMissing: Bool = true) throws -> Int32 {
        try validateName(name)
        let directory = try openRoot(createRootIfMissing: createRootIfMissing)
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
        var rawCount = 0
        var interruptedCount = 0
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
            rawCount += 1
            let rawLimit = documents ? Self.maximumCollectionRawEntries : Self.maximumCollections + 1
            guard rawCount <= rawLimit else {
                throw documents ? CollectionStoreError.interruptedWriteLimit : CollectionStoreError.collectionLimit
            }
            if !documents, name == Self.recoveryDirectoryName {
                try checkType(name, in: directory, directoryExpected: true)
                continue
            }
            if documents, name.hasPrefix(".markright-write-") {
                try checkInterruptedWrite(name, in: directory)
                interruptedCount += 1
                guard interruptedCount <= Self.maximumInterruptedWrites else { throw CollectionStoreError.interruptedWriteLimit }
                continue
            }
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
        guard info.st_mode & mode_t(S_IFMT) == expected else {
            throw CollectionStoreError.unsafeEntry(name)
        }
        if !directoryExpected { try checkDocumentLinks(info, name: name, in: directory) }
    }

    private func readDocument(_ name: String, in directory: Int32) throws -> Data {
        // O_NONBLOCK prevents a replaced FIFO from blocking before fstat rejects it.
        let file = openat(directory, name, O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK)
        guard file >= 0 else { throw CollectionStoreError.unsafeEntry(name) }
        defer { Darwin.close(file) }
        var info = stat()
        guard fstat(file, &info) == 0 else { throw failure("inspect document") }
        guard info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG) else { throw CollectionStoreError.unsafeEntry(name) }
        try checkDocumentLinks(info, name: name, in: directory)
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
        // Reserve the staging slot before writing, so an interruption cannot
        // push an otherwise bounded collection beyond its recovery scan limit.
        let entries = try rawEntries(in: directory, limit: Self.maximumCollectionRawEntries,
                                     limitError: .interruptedWriteLimit)
        var interrupted = 0
        for entry in entries {
            if let name = entry.name, name.hasPrefix(".markright-write-") {
                try checkInterruptedWrite(name, in: directory)
                interrupted += 1
            }
        }
        guard interrupted < Self.maximumInterruptedWrites,
              entries.count < Self.maximumCollectionRawEntries else { throw CollectionStoreError.interruptedWriteLimit }
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

private extension CollectionStore {
    struct RawEntry {
        let name: String?
    }

    func rawEntries(in directory: Int32, limit: Int, limitError: CollectionStoreError) throws -> [RawEntry] {
        let listing = openat(directory, ".", O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
        guard listing >= 0 else { throw failure("list folder") }
        guard let stream = fdopendir(listing) else { Darwin.close(listing); throw failure("list folder") }
        defer { closedir(stream) }
        var entries: [RawEntry] = []
        while true {
            errno = 0
            guard let entry = readdir(stream) else {
                if errno != 0 { throw failure("read folder entries") }
                return entries
            }
            let length = Int(entry.pointee.d_namlen)
            let name = withUnsafePointer(to: &entry.pointee.d_name) { pointer in
                String(bytes: UnsafeRawBufferPointer(start: UnsafeRawPointer(pointer), count: length), encoding: .utf8)
            }
            if name == "." || name == ".." { continue }
            guard entries.count < limit else { throw limitError }
            entries.append(RawEntry(name: name))
        }
    }

    func recoveryEntries(_ directory: Int32) throws -> [RawEntry] {
        try rawEntries(in: directory, limit: Self.maximumRecoveryEntries, limitError: .recoveryLimit)
    }

    func checkInterruptedWrite(_ name: String, in directory: Int32) throws {
        let prefix = ".markright-write-"
        guard name.hasPrefix(prefix), name.utf8.count == prefix.utf8.count + 36,
              UUID(uuidString: String(name.dropFirst(prefix.count))) != nil else {
            throw CollectionStoreError.unsafeEntry(name)
        }
        var info = stat()
        guard fstatat(directory, name, &info, AT_SYMLINK_NOFOLLOW) == 0 else { throw failure("inspect interrupted write") }
        guard info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG), (1...2).contains(info.st_nlink) else {
            throw CollectionStoreError.unsafeEntry(name)
        }
    }

    func checkDocumentLinks(_ info: stat, name: String, in directory: Int32) throws {
        if info.st_nlink == 1 { return }
        guard info.st_nlink == 2 else { throw CollectionStoreError.unsafeEntry(name) }
        // Only the known createDocument link-before-unlink interruption is
        // accepted. Arbitrary second links and every third link remain refused.
        for entry in try rawEntries(in: directory, limit: Self.maximumCollectionRawEntries,
                                   limitError: .interruptedWriteLimit) {
            guard let sibling = entry.name, sibling.hasPrefix(".markright-write-") else { continue }
            try checkInterruptedWrite(sibling, in: directory)
            var staging = stat()
            guard fstatat(directory, sibling, &staging, AT_SYMLINK_NOFOLLOW) == 0 else { throw failure("inspect interrupted write") }
            if staging.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG), staging.st_nlink == 2,
               staging.st_ino == info.st_ino, staging.st_dev == info.st_dev { return }
        }
        throw CollectionStoreError.unsafeEntry(name)
    }

    func openRecoveryDirectory(create: Bool) throws -> Int32? {
        let directory = try openRoot()
        defer { Darwin.close(directory) }
        var info = stat()
        if fstatat(directory, Self.recoveryDirectoryName, &info, AT_SYMLINK_NOFOLLOW) != 0 {
            guard errno == ENOENT else { throw failure("inspect recovery folder") }
            guard create else { return nil }
            guard mkdirat(directory, Self.recoveryDirectoryName, 0o700) == 0 else { throw failure("create recovery folder") }
        }
        // Also retry a previous uncertain directory publication before any new
        // checkpoint can be acknowledged as durable.
        if create, fsync(directory) != 0 { throw failure("synchronize recovery folder") }
        let recovery = openat(directory, Self.recoveryDirectoryName, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard recovery >= 0 else { throw CollectionStoreError.unsafeEntry(Self.recoveryDirectoryName) }
        return recovery
    }

    func requiredRecoveryDirectory() throws -> Int32 {
        guard let directory = try openRecoveryDirectory(create: true) else { throw CollectionStoreError.invalidRoot }
        return directory
    }

    func validateRecoveryFileName(_ name: String, sessionID: UUID) throws {
        if name == sessionID.uuidString + ".draft" { return }
        if name.hasSuffix(".pending"), name.utf8.count == 36 + 8,
           let id = UUID(uuidString: String(name.dropLast(8))), name == id.uuidString + ".pending" { return }
        throw CollectionStoreError.malformedRecovery(name)
    }

    func encodeRecovery(_ draft: RecoveryDraft) throws -> Data {
        try validateName(draft.collection)
        try validateName(draft.name, document: true)
        try validateRecoveryFileName(draft.fileName, sessionID: draft.sessionID)
        let source = try encoded(draft.source)
        guard draft.baseline.count <= Self.maximumDocumentBytes else { throw CollectionStoreError.tooLarge }
        let baselineText = String(decoding: draft.baseline, as: UTF8.self)
        guard baselineText.utf8.elementsEqual(draft.baseline) else { throw CollectionStoreError.invalidUTF8 }
        var bytes = Data("MRKRCV01".utf8)
        appendRecoveryInteger(1, to: &bytes)
        bytes.append(contentsOf: draft.id.uuidString.utf8)
        bytes.append(contentsOf: draft.sessionID.uuidString.utf8)
        let fields = [Data(draft.collection.utf8), Data(draft.name.utf8), draft.baseline, source]
        for field in fields { appendRecoveryInteger(UInt32(field.count), to: &bytes) }
        for field in fields { bytes.append(field) }
        bytes.append(contentsOf: SHA256.hash(data: bytes))
        return bytes
    }

    func appendRecoveryInteger(_ value: UInt32, to bytes: inout Data) {
        bytes.append(contentsOf: [UInt8((value >> 24) & 255), UInt8((value >> 16) & 255),
                                  UInt8((value >> 8) & 255), UInt8(value & 255)])
    }

    func decodeRecovery(_ bytes: Data, fileName: String) throws -> RecoveryDraft {
        let invalid = CollectionStoreError.malformedRecovery(fileName)
        // Fixed fields, lengths and checksum are all covered, before interpreting
        // any payload. No document, URL, or executable decoder is involved.
        guard bytes.count >= 8 + 4 + 72 + 16 + 32,
              bytes.count <= Self.maximumRecoveryBytes else { throw invalid }
        let payload = bytes.dropLast(32)
        guard Data(SHA256.hash(data: payload)) == Data(bytes.suffix(32)) else { throw invalid }
        var offset = 0
        func take(_ count: Int) throws -> Data {
            guard count >= 0, count <= payload.count - offset else { throw invalid }
            let value = Data(payload[offset..<(offset + count)])
            offset += count
            return value
        }
        func integer() throws -> UInt32 {
            try take(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        }
        func text(_ data: Data) throws -> String {
            let value = String(decoding: data, as: UTF8.self)
            guard value.utf8.elementsEqual(data) else { throw invalid }
            return value
        }
        guard try take(8) == Data("MRKRCV01".utf8), try integer() == 1 else { throw invalid }
        let idText = try text(take(36))
        let sessionText = try text(take(36))
        guard let id = UUID(uuidString: idText), id.uuidString == idText,
              let sessionID = UUID(uuidString: sessionText), sessionID.uuidString == sessionText else { throw invalid }
        let collectionLength = Int(try integer())
        let nameLength = Int(try integer())
        let baselineLength = Int(try integer())
        let sourceLength = Int(try integer())
        guard (1...255).contains(collectionLength), (1...255).contains(nameLength),
              baselineLength <= Self.maximumDocumentBytes, sourceLength <= Self.maximumDocumentBytes,
              collectionLength + nameLength + baselineLength + sourceLength == payload.count - offset else { throw invalid }
        let collection = try text(take(collectionLength))
        let name = try text(take(nameLength))
        let baseline = try take(baselineLength)
        _ = try text(baseline)
        let source = try text(take(sourceLength))
        let draft = RecoveryDraft(id: id, sessionID: sessionID, fileName: fileName,
                                  collection: collection, name: name, source: source, baseline: baseline)
        do { _ = try encodeRecovery(draft) } catch { throw invalid }
        return draft
    }

    func readRecovery(_ name: String, in directory: Int32) throws -> RecoveryDraft {
        // Check filenames before opening; unknown entries remain inert evidence.
        guard name.utf8.count <= 44, name.hasSuffix(".draft") || name.hasSuffix(".pending") else {
            throw CollectionStoreError.malformedRecovery(name)
        }
        let file = openat(directory, name, O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK)
        guard file >= 0 else {
            if errno == ENOENT { throw CollectionStoreError.notFound(name) }
            throw CollectionStoreError.unsafeEntry(name)
        }
        defer { Darwin.close(file) }
        var info = stat()
        guard fstat(file, &info) == 0 else { throw failure("inspect recovery record") }
        guard info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG), info.st_nlink == 1 else {
            throw CollectionStoreError.unsafeEntry(name)
        }
        guard info.st_size >= 0, info.st_size <= Self.maximumRecoveryBytes else { throw CollectionStoreError.malformedRecovery(name) }
        var bytes = Data()
        var buffer = [UInt8](repeating: 0, count: 16_384)
        while true {
            let count = buffer.withUnsafeMutableBytes { Darwin.read(file, $0.baseAddress, $0.count) }
            if count < 0, errno == EINTR { continue }
            guard count >= 0 else { throw failure("read recovery record") }
            if count == 0 { break }
            guard bytes.count + count <= Self.maximumRecoveryBytes else { throw CollectionStoreError.malformedRecovery(name) }
            bytes.append(contentsOf: buffer.prefix(count))
        }
        return try decodeRecovery(bytes, fileName: name)
    }

    func requireMatchingRecovery(_ draft: RecoveryDraft, in directory: Int32) throws {
        let expected = try encodeRecovery(draft)
        let actual = try readRecovery(draft.fileName, in: directory)
        guard try encodeRecovery(actual) == expected else { throw CollectionStoreError.conflict }
    }

    func writeRecoveryTemporary(_ bytes: Data, in directory: Int32) throws -> String {
        let name = UUID().uuidString + ".pending"
        let file = openat(directory, name, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, mode_t(0o600))
        guard file >= 0 else { throw failure("create pending recovery record") }
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
                guard count > 0 else { throw failure("write recovery record") }
                offset += count
            }
        }
        guard fsync(file) == 0 else { throw failure("synchronize recovery record") }
        completed = true
        return name
    }
}
