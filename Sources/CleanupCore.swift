import Foundation

struct CacheSpec: Identifiable, Codable {
    let id: String
    let name: String
    let detail: String
    let processHints: [String]
}

struct CacheScan: Identifiable {
    var id: String { spec.id }
    let spec: CacheSpec
    let bytes: Int64
    let inode: UInt64
    let blocked: String?
}

struct CleanupEvent: Codable {
    let date: Date
    let cache: String
    let path: String
    let measuredBytes: Int64
    let outcome: String
}

struct CleanupResult {
    let events: [CleanupEvent]
    let before: Int64?
    let after: Int64?
    let historyWarning: String?
}

enum CleanupError: LocalizedError {
    case unsafePath, unavailable, running, changed
    var errorDescription: String? {
        switch self {
        case .unsafePath: return "Path failed the safety check. Nothing was deleted."
        case .unavailable: return "Cache is missing or could not be measured. Scan again."
        case .running: return "The app or package tool is running. Close it and scan again."
        case .changed: return "Cache changed since the scan. Scan again before deleting."
        }
    }
}

final class CleanupCore {
    // These are cache paths only. Never add Application Support, personal folders,
    // browser profiles, macOS files, or arbitrary user-supplied deletion paths.
    static let specs: [CacheSpec] = [
        .init(id: "Library/Caches/Google/Chrome", name: "Chrome", detail: "Cached web content across Chrome profiles. Cookies and profiles stay.", processHints: ["/Google Chrome.app/"]),
        .init(id: "Library/Caches/com.spotify.client", name: "Spotify", detail: "Temporary playback and app cache. Download storage stays.", processHints: ["/Spotify.app/"]),
        .init(id: "Library/Caches/Firefox", name: "Firefox", detail: "Cached web content. Browser profiles stay.", processHints: ["/Firefox.app/"]),
        .init(id: "Library/Caches/Comet", name: "Comet", detail: "Cached web content. Browser profiles stay.", processHints: ["/Comet.app/"]),
        .init(id: "Library/Caches/pip", name: "Python / pip", detail: "Downloaded Python package cache.", processHints: ["/pip ", "/pip3 ", " -m pip "]),
        .init(id: ".npm/_cacache", name: "npm", detail: "Downloaded JavaScript package cache.", processHints: ["npm ", "npm exec", "npx "]),
        .init(id: "Library/Caches/Homebrew", name: "Homebrew", detail: "Downloaded packages. Installed software stays.", processHints: ["/brew ", "brew.rb"]),
        .init(id: "Library/Caches/go-build", name: "Go", detail: "Compiled build cache. Projects stay.", processHints: ["/go build", "/go test", "/go run"]),
        .init(id: "Library/Caches/node-gyp", name: "Node build tools", detail: "Downloaded headers for native Node builds.", processHints: ["node-gyp", "npm "]),
        .init(id: "Library/Caches/typescript", name: "TypeScript", detail: "Downloaded editor type definitions.", processHints: ["/Cursor.app/", "/Visual Studio Code.app/", "tsserver", "typingsInstaller"])
    ]

    let home: URL
    let historyURL: URL
    private let processes: () -> String
    private let fm = FileManager.default

    init(home: URL = FileManager.default.homeDirectoryForCurrentUser,
         historyURL: URL? = nil,
         processes: @escaping () -> String = CleanupCore.processList) {
        self.home = home.resolvingSymlinksInPath().standardizedFileURL
        self.historyURL = historyURL ?? home.appendingPathComponent("Library/Application Support/Pankaj Mac Cleanup/history.jsonl")
        self.processes = processes
    }

    static func run(_ executable: String, _ arguments: [String]) throws -> (Int32, String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    static func processList() -> String {
        // Arguments are inspected locally for package installs, never saved or shown.
        guard let (status, output) = try? run("/bin/ps", ["-axo", "command="]), status == 0 else {
            return "__PROCESS_CHECK_FAILED__"
        }
        return output
    }

    func checkedURL(_ id: String) throws -> URL {
        guard Self.specs.contains(where: { $0.id == id }) else { throw CleanupError.unsafePath }
        let url = home.appendingPathComponent(id).standardizedFileURL
        guard url.path.hasPrefix(home.path + "/"), url.resolvingSymlinksInPath().path == url.path else {
            throw CleanupError.unsafePath
        }
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else { throw CleanupError.unsafePath }
        return url
    }

    private func measure(_ url: URL) throws -> Int64 {
        let (status, output) = try Self.run("/usr/bin/du", ["-sk", url.path])
        guard status == 0, let value = output.split(whereSeparator: { $0.isWhitespace }).first,
              let kib = Int64(value), kib >= 0 else { throw CleanupError.unavailable }
        return kib * 1024
    }

    private func inode(_ url: URL) throws -> UInt64 {
        let attrs = try fm.attributesOfItem(atPath: url.path)
        guard let number = attrs[.systemFileNumber] as? NSNumber else { throw CleanupError.unavailable }
        return number.uint64Value
    }

    private func isRunning(_ spec: CacheSpec, _ list: String) -> Bool {
        list.contains("__PROCESS_CHECK_FAILED__") || spec.processHints.contains { list.localizedCaseInsensitiveContains($0) }
    }

    func scan() -> [CacheScan] {
        let list = processes()
        return Self.specs.compactMap { spec in
            let raw = home.appendingPathComponent(spec.id)
            guard fm.fileExists(atPath: raw.path) || ((try? raw.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true) else { return nil }
            do {
                let url = try checkedURL(spec.id)
                return CacheScan(spec: spec, bytes: try measure(url), inode: try inode(url),
                                 blocked: isRunning(spec, list) ? "Close the app or package tool, then scan again." : nil)
            } catch {
                return CacheScan(spec: spec, bytes: 0, inode: 0, blocked: error.localizedDescription)
            }
        }.sorted { $0.bytes > $1.bytes }
    }

    static func freeBytes() -> Int64? {
        guard let (status, output) = try? run("/bin/df", ["-k", "/"]), status == 0,
              let line = output.split(separator: "\n").last else { return nil }
        let fields = line.split(whereSeparator: { $0.isWhitespace })
        guard fields.count > 3, let kib = Int64(fields[3]) else { return nil }
        return kib * 1024
    }

    func clean(_ approved: [CacheScan]) -> CleanupResult {
        let before = Self.freeBytes()
        var events: [CleanupEvent] = []
        var historyWarning: String?
        for entry in approved {
            let path = home.appendingPathComponent(entry.id).path
            var bytes: Int64 = 0
            var outcome: String
            do {
                guard entry.blocked == nil else { throw CleanupError.running }
                let url = try checkedURL(entry.id)
                guard let spec = Self.specs.first(where: { $0.id == entry.id }) else { throw CleanupError.unsafePath }
                guard !isRunning(spec, processes()) else { throw CleanupError.running }
                guard try inode(url) == entry.inode else { throw CleanupError.changed }
                bytes = try measure(url)
                // Do not silently clear substantially more than the user reviewed.
                guard bytes <= entry.bytes + max(1_048_576, entry.bytes / 20) else { throw CleanupError.changed }
                _ = try checkedURL(entry.id)
                try fm.removeItem(at: url)
                outcome = "Cleared"
            } catch {
                // A filesystem failure can occur after some files were removed.
                outcome = "Skipped or incomplete: \(error.localizedDescription)"
            }
            let event = CleanupEvent(date: Date(), cache: entry.spec.name, path: path, measuredBytes: bytes, outcome: outcome)
            events.append(event)
            do { try appendHistory(event) }
            catch { historyWarning = "Could not save all cleanup history: \(error.localizedDescription)" }
        }
        return CleanupResult(events: events, before: before, after: Self.freeBytes(), historyWarning: historyWarning)
    }

    private func appendHistory(_ event: CleanupEvent) throws {
        guard historyURL.resolvingSymlinksInPath().path == historyURL.standardizedFileURL.path else {
            throw CleanupError.unsafePath
        }
        try fm.createDirectory(at: historyURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var data = try encoder.encode(event)
        data.append(0x0a)
        if !fm.fileExists(atPath: historyURL.path) { try data.write(to: historyURL, options: .atomic); return }
        let handle = try FileHandle(forWritingTo: historyURL)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
    }
}
