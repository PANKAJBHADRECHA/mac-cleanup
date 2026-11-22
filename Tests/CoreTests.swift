import Foundation

@main struct CoreTests {
    static func main() throws {
        if CommandLine.arguments.contains("--scan-only") {
            for entry in CleanupCore().scan() {
                print("\(entry.spec.name): \(entry.bytes) bytes; \(entry.blocked ?? "available")")
            }
            print("Read-only scan completed. Nothing was deleted.")
            return
        }
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("mac-cleanup-tests-\(UUID().uuidString)").resolvingSymlinksInPath()
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        var count = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            precondition(condition(), message)
            count += 1
            print("PASS: \(message)")
        }
        func fixture(_ name: String) throws -> (CleanupCore, URL) {
            let home = root.appendingPathComponent(name)
            try fm.createDirectory(at: home, withIntermediateDirectories: true)
            return (CleanupCore(home: home, historyURL: home.appendingPathComponent("history.jsonl"), processes: { "" }), home)
        }
        func cache(_ home: URL) throws -> URL {
            let path = home.appendingPathComponent("Library/Caches/pip")
            try fm.createDirectory(at: path, withIntermediateDirectories: true)
            try Data(repeating: 7, count: 16384).write(to: path.appendingPathComponent("package.whl"))
            return path
        }

        let (core, home) = try fixture("normal")
        let path = try cache(home)
        let personal = home.appendingPathComponent("Documents/keep.txt")
        try fm.createDirectory(at: personal.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("keep".utf8).write(to: personal)
        let scanned = core.scan()
        check(scanned.count == 1 && scanned[0].bytes > 0, "scan measures only supported existing caches")
        check(fm.fileExists(atPath: path.path), "scan never deletes files")
        let cleared = core.clean(scanned)
        check(cleared.events[0].outcome == "Cleared" && !fm.fileExists(atPath: path.path), "approved cache is removed")
        check(fm.fileExists(atPath: personal.path), "personal documents survive cleanup")
        check(fm.fileExists(atPath: core.historyURL.path), "cleanup writes a local audit record")
        do { _ = try core.checkedURL("Documents"); fatalError("arbitrary path accepted") }
        catch { check(true, "arbitrary paths are rejected") }

        let (_, busyHome) = try fixture("busy")
        _ = try cache(busyHome)
        let busy = CleanupCore(home: busyHome, processes: { "/usr/bin/python3 -m pip install something" })
        let blocked = busy.scan()
        check(blocked[0].blocked != nil, "running package install blocks cleanup")
        check(busy.clean(blocked).events[0].outcome != "Cleared", "blocked scan cannot be deleted")

        let (_, startedHome) = try fixture("started")
        let startedPath = try cache(startedHome)
        var processList = ""
        let started = CleanupCore(home: startedHome, processes: { processList })
        let earlier = started.scan()
        processList = "/usr/bin/python3 -m pip install something"
        _ = started.clean(earlier)
        check(fm.fileExists(atPath: startedPath.path), "app started after scanning is checked again")

        let (changed, changedHome) = try fixture("changed")
        let changedPath = try cache(changedHome)
        let old = changed.scan()
        try Data(repeating: 2, count: 2_000_000).write(to: changedPath.appendingPathComponent("new.whl"))
        _ = changed.clean(old)
        check(fm.fileExists(atPath: changedPath.path), "substantial growth requires a new scan")

        let (replaced, replacedHome) = try fixture("replaced")
        let replacedPath = try cache(replacedHome)
        let original = replaced.scan()
        try fm.moveItem(at: replacedPath, to: replacedHome.appendingPathComponent("old-cache"))
        _ = try cache(replacedHome)
        _ = replaced.clean(original)
        check(fm.fileExists(atPath: replacedPath.path), "replacement directory requires a new scan")

        let (nested, nestedHome) = try fixture("nested-link")
        let nestedPath = try cache(nestedHome)
        try fm.createSymbolicLink(at: nestedPath.appendingPathComponent("linked-document"), withDestinationURL: personal)
        _ = nested.clean(nested.scan())
        check(fm.fileExists(atPath: personal.path), "symlink within cache does not delete its external target")

        let (_, chromeHome) = try fixture("chrome-running")
        let chromePath = chromeHome.appendingPathComponent("Library/Caches/Google/Chrome")
        try fm.createDirectory(at: chromePath, withIntermediateDirectories: true)
        let chrome = CleanupCore(home: chromeHome, processes: { "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" })
        let chromeScan = chrome.scan()
        check(chromeScan[0].blocked != nil, "running Chrome blocks browser cache deletion")

        let (linkCore, linkHome) = try fixture("symlink")
        let linkPath = linkHome.appendingPathComponent("Library/Caches/pip")
        try fm.createDirectory(at: linkPath.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.createSymbolicLink(at: linkPath, withDestinationURL: personal.deletingLastPathComponent())
        let links = linkCore.scan()
        check(links[0].blocked != nil, "cache symlink is blocked")
        _ = linkCore.clean(links)
        check(fm.fileExists(atPath: personal.path), "symlink target is preserved")

        let (parentCore, parentHome) = try fixture("parent-symlink")
        try fm.createSymbolicLink(at: parentHome.appendingPathComponent("Library"), withDestinationURL: home.appendingPathComponent("Documents"))
        do { _ = try parentCore.checkedURL("Library/Caches/pip"); fatalError("parent symlink accepted") }
        catch { check(true, "symlink in an ancestor path is blocked") }

        let (_, failedHome) = try fixture("process-check-failed")
        let failedPath = try cache(failedHome)
        let failed = CleanupCore(home: failedHome, processes: { "__PROCESS_CHECK_FAILED__" })
        let failedScan = failed.scan()
        _ = failed.clean(failedScan)
        check(fm.fileExists(atPath: failedPath.path), "failed process inspection prevents cleanup")
        print("\(count) safety checks passed. Only temporary test fixtures were deleted.")
    }
}
