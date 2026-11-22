import Foundation

@main struct FileReviewTests {
    static func main() throws {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appendingPathComponent("file-review-tests-\(UUID().uuidString)").resolvingSymlinksInPath()
        try fm.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: base) }
        var count = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            precondition(condition(), message)
            count += 1
            print("PASS: \(message)")
        }
        func expectFailure(_ message: String, _ work: () throws -> Void) {
            do { try work(); fatalError("Expected rejection: \(message)") }
            catch { check(true, message) }
        }
        func write(_ url: URL, bytes: Int) throws {
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(repeating: 3, count: bytes).write(to: url)
        }
        func fixture(_ name: String) throws -> (URL, URL, URL) {
            let home = base.appendingPathComponent(name)
            let docs = home.appendingPathComponent("Documents")
            let trash = home.appendingPathComponent("Fixture Trash")
            try fm.createDirectory(at: docs, withIntermediateDirectories: true)
            try fm.createDirectory(at: trash, withIntermediateDirectories: true)
            return (home, docs, trash)
        }
        func engine(_ home: URL, _ docs: URL, _ trash: URL,
                    cloud: @escaping (URL) throws -> Bool = { _ in false }) throws -> FileReviewCore {
            try FileReviewCore(root: docs, home: home, historyURL: home.appendingPathComponent("history.jsonl"), cloudCheck: cloud,
                               moveToTrash: { url in
                let destination = trash.appendingPathComponent(UUID().uuidString + "-" + url.lastPathComponent)
                try fm.moveItem(at: url, to: destination)
                return destination
            })
        }
        let (home, docs, trash) = try fixture("normal")
        let large = docs.appendingPathComponent("large.pdf")
        let small = docs.appendingPathComponent("small.pdf")
        try write(large, bytes: 8192)
        try write(small, bytes: 1024)
        let core = try engine(home, docs, trash)
        let scan = try core.scan(minimumBytes: 0)
        check(scan.files.count == 2 && scan.files[0].url == large, "files are sorted largest first")
        check(fm.fileExists(atPath: large.path), "review scan does not move or delete anything")
        check(scan.files[0].modified <= Date() && scan.files[0].bytes == 8192, "size and modification date are recorded")
        let receipt = try core.trash(scan.files[0]).0
        check(!fm.fileExists(atPath: large.path) && fm.fileExists(atPath: receipt.trashPath), "approved file is moved to the fixture Trash")
        check(fm.fileExists(atPath: small.path), "unapproved sibling survives")
        check(receipt.outcome.contains("not reclaimed"), "Trash move is not reported as freed space")
        check(fm.fileExists(atPath: core.historyURL.path), "file movement is recorded")
        try write(large, bytes: 9000)
        expectFailure("stale file cannot be moved") { _ = try core.trash(scan.files[0]) }
        check(fm.fileExists(atPath: large.path), "changed file stays in place")
        let filtered = try core.scan(minimumBytes: 5000)
        check(filtered.files.count == 1, "minimum size filter works")
        let limited = try core.scan(minimumBytes: 0, limit: 1)
        check(limited.files.count == 1 && limited.matchingCount == 2, "display limit still reports total matches")
        let bounded = try core.scan(minimumBytes: 0, visitLimit: 1)
        check(bounded.stoppedEarly, "bounded scan reports that it is partial")

        let outside = home.appendingPathComponent("Library/private.txt")
        try write(outside, bytes: 300)
        expectFailure("Library is not a review root") { _ = try engine(home, home.appendingPathComponent("Library"), trash) }
        let other = home.appendingPathComponent("Downloads/other.pdf")
        try write(other, bytes: 200)
        let forged = ReviewFile(url: other, bytes: 200, modified: Date(), inode: 1, device: 1)
        expectFailure("file outside the chosen folder is rejected") { _ = try core.trash(forged) }
        check(fm.fileExists(atPath: other.path), "outside file is preserved")

        try fm.createSymbolicLink(at: docs.appendingPathComponent("linked.pdf"), withDestinationURL: outside)
        try write(docs.appendingPathComponent(".hidden/secret.pdf"), bytes: 1000)
        try write(docs.appendingPathComponent("Example.app/inside.pdf"), bytes: 1000)
        try write(docs.appendingPathComponent("Album.photoslibrary/inside.pdf"), bytes: 1000)
        try write(docs.appendingPathComponent("node_modules/inside.pdf"), bytes: 1000)
        let protectedScan = try core.scan(minimumBytes: 0)
        check(protectedScan.files.count == 2, "links, hidden folders, app packages, photo libraries and dependencies are excluded")
        check(fm.fileExists(atPath: outside.path), "symlink destination remains intact")

        let cloud = docs.appendingPathComponent("cloud.pdf")
        try write(cloud, bytes: 500)
        let cloudEngine = try engine(home, docs, trash, cloud: { $0.lastPathComponent == "cloud.pdf" })
        let cloudScan = try cloudEngine.scan(minimumBytes: 0)
        check(cloudScan.files.allSatisfy { $0.url != cloud }, "cloud files are excluded")
        expectFailure("cloud root is rejected") { _ = try engine(home, docs, trash, cloud: { _ in true }) }
        let aliasRoot = home.appendingPathComponent("Desktop")
        try fm.createSymbolicLink(at: aliasRoot, withDestinationURL: docs)
        expectFailure("symlinked review root is rejected") { _ = try engine(home, aliasRoot, trash) }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let now = Date()
        let recent = "/Backups/" + formatter.string(from: now.addingTimeInterval(-3600)) + ".backup"
        let old = "/Backups/" + formatter.string(from: now.addingTimeInterval(-9 * 86400)) + ".backup"
        check(!BackupStatus.from(output: recent, now: now).needsAcknowledgement, "recent backup passes the backup check")
        check(BackupStatus.from(output: old, now: now).needsAcknowledgement, "old backup requires acknowledgement")
        check(BackupStatus.from(output: "Failed to mount destination", now: now).needsAcknowledgement, "unavailable backup requires acknowledgement")
        print("\(count) file-review checks passed. No personal files or actual Trash were touched.")
    }
}
