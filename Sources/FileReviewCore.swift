import Foundation

struct ReviewFile: Identifiable {
    var id: String { url.path }
    let url: URL
    let bytes: Int64
    let modified: Date
    let inode: UInt64
    let device: UInt64
}

struct FileReviewScan {
    let files: [ReviewFile]
    let inspected: Int
    let omitted: Int
    let stoppedEarly: Bool
    let matchingCount: Int
}

struct TrashReceipt: Codable {
    let date: Date
    let originalPath: String
    let trashPath: String
    let bytes: Int64
    let outcome: String
}

enum ReviewError: LocalizedError {
    case outsideScope, protectedItem, changed, unreadable
    var errorDescription: String? {
        switch self {
        case .outsideScope: return "Choose a local folder inside Documents, Downloads or Desktop."
        case .protectedItem: return "iCloud files, links, hidden folders and app libraries are excluded. Use Finder to review this item."
        case .changed: return "This file changed after the scan. Scan again before moving it."
        case .unreadable: return "This folder could not be read. Choose it again and allow access if macOS asks."
        }
    }
}

final class FileReviewCore {
    let home: URL
    let root: URL
    let historyURL: URL
    private let fm = FileManager.default
    private let cloudCheck: (URL) throws -> Bool
    private let moveToTrash: (URL) throws -> URL
    private let excludedDirectories = Set(["node_modules", "venv", "__pycache__"])
    private let excludedPackages = Set(["app", "photoslibrary", "photolibrary", "fcpbundle", "logicx", "band"])

    init(root: URL, home: URL = FileManager.default.homeDirectoryForCurrentUser,
         historyURL: URL? = nil,
         cloudCheck: @escaping (URL) throws -> Bool = FileReviewCore.isCloud,
         moveToTrash: @escaping (URL) throws -> URL = FileReviewCore.systemTrash) throws {
        self.home = home.resolvingSymlinksInPath().standardizedFileURL
        self.root = root.standardizedFileURL
        self.historyURL = historyURL ?? home.appendingPathComponent("Library/Application Support/Pankaj Mac Cleanup/files-history.jsonl")
        self.cloudCheck = cloudCheck
        self.moveToTrash = moveToTrash
        try validatePath(self.root, allowRoot: true)
        let values = try self.root.resourceValues(forKeys: [.isDirectoryKey])
        guard values.isDirectory == true else { throw ReviewError.outsideScope }
    }

    static func isCloud(_ url: URL) throws -> Bool {
        try url.resourceValues(forKeys: [.isUbiquitousItemKey]).isUbiquitousItem == true
    }

    static func systemTrash(_ url: URL) throws -> URL {
        var result: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &result)
        // The move succeeded even if macOS did not report a destination.
        return (result as URL?) ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash")
    }

    private func validatePath(_ url: URL, allowRoot: Bool = false) throws {
        let path = url.standardizedFileURL.path
        let allowed = ["Documents", "Downloads", "Desktop"].contains { name in
            let base = home.appendingPathComponent(name).path
            return path == base || path.hasPrefix(base + "/")
        }
        guard allowed, path == url.path,
              (allowRoot && path == root.path) || path.hasPrefix(root.path + "/") else { throw ReviewError.outsideScope }
        guard url.resolvingSymlinksInPath().path == path else { throw ReviewError.protectedItem }
        let relative = String(path.dropFirst(home.path.count + 1))
        var ancestor = home
        for component in relative.split(separator: "/") {
            let part = String(component)
            guard !part.hasPrefix("."), !excludedDirectories.contains(part),
                  !excludedPackages.contains(URL(fileURLWithPath: part).pathExtension.lowercased()) else { throw ReviewError.protectedItem }
            ancestor.appendPathComponent(part)
            let values = try ancestor.resourceValues(forKeys: [.isSymbolicLinkKey, .isAliasFileKey, .isPackageKey])
            guard values.isSymbolicLink != true, values.isAliasFile != true,
                  values.isPackage != true, try !cloudCheck(ancestor) else { throw ReviewError.protectedItem }
        }
    }

    private func snapshot(_ url: URL) throws -> ReviewFile {
        try validatePath(url)
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey])
        guard values.isRegularFile == true, let modified = values.contentModificationDate,
              let bytes = values.fileSize else { throw ReviewError.protectedItem }
        let attrs = try fm.attributesOfItem(atPath: url.path)
        guard let inode = attrs[.systemFileNumber] as? NSNumber,
              let device = attrs[.systemNumber] as? NSNumber else { throw ReviewError.unreadable }
        return ReviewFile(url: url, bytes: Int64(bytes), modified: modified,
                          inode: inode.uint64Value, device: device.uint64Value)
    }

    func scan(minimumBytes: Int64 = 10_000_000, limit: Int = 500, visitLimit: Int = 100_000) throws -> FileReviewScan {
        try validatePath(root, allowRoot: true)
        // Reading the root first makes denied access an error instead of an empty success.
        _ = try fm.contentsOfDirectory(atPath: root.path)
        var omitted = 0
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey, .isPackageKey, .isAliasFileKey]
        guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: keys,
                                             options: [.skipsHiddenFiles, .skipsPackageDescendants],
                                             errorHandler: { _, _ in omitted += 1; return true }) else { throw ReviewError.unreadable }
        var files: [ReviewFile] = []
        var inspected = 0
        var visited = 0
        var matching = 0
        var stopped = false
        for case let rawURL as URL in enumerator {
            let url = rawURL.standardizedFileURL
            visited += 1
            if visited > visitLimit { stopped = true; break }
            do {
                let values = try url.resourceValues(forKeys: Set(keys))
                try validatePath(url)
                if values.isDirectory == true { continue }
                let file = try snapshot(url)
                inspected += 1
                if file.bytes >= minimumBytes {
                    matching += 1
                    files.append(file)
                    if files.count >= max(2, limit * 2) {
                        files.sort { $0.bytes > $1.bytes }
                        files = Array(files.prefix(limit))
                    }
                }
            } catch {
                omitted += 1
                enumerator.skipDescendants()
            }
        }
        files.sort { $0.bytes == $1.bytes ? $0.url.path < $1.url.path : $0.bytes > $1.bytes }
        return FileReviewScan(files: Array(files.prefix(limit)), inspected: inspected, omitted: omitted,
                              stoppedEarly: stopped, matchingCount: matching)
    }

    func trash(_ approved: ReviewFile) throws -> (TrashReceipt, String?) {
        // A fresh URL avoids cached URL resource values when rechecking changes.
        let fresh = try snapshot(URL(fileURLWithPath: approved.url.path))
        guard fresh.inode == approved.inode, fresh.device == approved.device,
              fresh.bytes == approved.bytes, fresh.modified == approved.modified else { throw ReviewError.changed }
        let destination = try moveToTrash(fresh.url)
        let receipt = TrashReceipt(date: Date(), originalPath: fresh.url.path, trashPath: destination.path,
                                   bytes: fresh.bytes, outcome: "Moved to Trash; space not reclaimed yet")
        var warning: String?
        do { try save(receipt) } catch { warning = "File was moved, but history could not be saved: \(error.localizedDescription)" }
        return (receipt, warning)
    }

    private func save(_ receipt: TrashReceipt) throws {
        guard historyURL.resolvingSymlinksInPath().path == historyURL.standardizedFileURL.path else { throw ReviewError.protectedItem }
        try fm.createDirectory(at: historyURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var data = try encoder.encode(receipt)
        data.append(0x0a)
        if !fm.fileExists(atPath: historyURL.path) { try data.write(to: historyURL, options: .atomic); return }
        let handle = try FileHandle(forWritingTo: historyURL)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
    }
}

struct BackupStatus {
    let message: String
    let needsAcknowledgement: Bool

    static func from(output: String, now: Date = Date()) -> BackupStatus {
        let pattern = #"\d{4}-\d{2}-\d{2}-\d{6}"#
        guard let range = output.range(of: pattern, options: .regularExpression) else {
            return BackupStatus(message: "Could not verify a Time Machine backup. Back up important files before reviewing personal files.", needsAcknowledgement: true)
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        guard let date = formatter.date(from: String(output[range])), date <= now.addingTimeInterval(300) else {
            return BackupStatus(message: "Could not verify the backup date. Back up important files before continuing.", needsAcknowledgement: true)
        }
        let old = now.timeIntervalSince(date) > 7 * 24 * 60 * 60
        return BackupStatus(message: "Latest accessible Time Machine backup: \(date.formatted(date: .abbreviated, time: .shortened))." + (old ? " It is older than a week; make a fresh backup first." : ""), needsAcknowledgement: old)
    }

    static func check() -> BackupStatus {
        // Do not let an unavailable backup disk hang the app indefinitely.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tmutil")
        process.arguments = ["latestbackup"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            let deadline = Date().addingTimeInterval(12)
            while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.1) }
            if process.isRunning {
                process.terminate()
                return from(output: "")
            }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard process.terminationStatus == 0 else { return from(output: "") }
            return from(output: String(decoding: data, as: UTF8.self))
        } catch { return from(output: "") }
    }
}
