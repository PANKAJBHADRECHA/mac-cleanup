import SwiftUI
import AppKit

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    static var working = false
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if Self.working { explainWait(); return .terminateCancel }
        return .terminateNow
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if Self.working { explainWait(); return false }
        return true
    }
    private func explainWait() {
        let alert = NSAlert()
        alert.messageText = "A scan or cleanup is still running"
        alert.informativeText = "Please let it finish before closing the app. The result will show when the work is complete."
        alert.addButton(withTitle: "Keep open")
        alert.runModal()
    }
}

func size(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .decimal)
}

@MainActor final class CleanupModel: ObservableObject {
    @Published var entries: [CacheScan] = []
    @Published var selected: Set<String> = []
    @Published var busy = false { didSet { AppDelegate.working = busy } }
    @Published var scanned = false
    @Published var status = "Ready when you are"
    @Published var free: Int64?
    @Published var result: CleanupResult?
    @Published var reviewFolder: URL?
    @Published var reviewScan: FileReviewScan?
    @Published var minimumFileBytes: Int64 = 10_000_000
    @Published var reviewStatus = "Choose a folder to review personal files."
    @Published var backup: BackupStatus?
    @Published var movedFiles: [TrashReceipt] = []
    var reviewEngine: FileReviewCore?
    let core = CleanupCore()
    var selectedEntries: [CacheScan] { entries.filter { selected.contains($0.id) && $0.blocked == nil } }
    var selectedBytes: Int64 { selectedEntries.reduce(0) { $0 + $1.bytes } }

    func scan() {
        guard !busy else { return }
        busy = true
        selected = []
        result = nil
        status = "Measuring caches… Nothing is being deleted."
        let engine = core
        Task {
            let data = await Task.detached { (engine.scan(), CleanupCore.freeBytes()) }.value
            entries = data.0
            free = data.1
            scanned = true
            busy = false
            status = "Scan complete. Select the caches you want to clear."
        }
    }

    func clean() {
        guard !busy, !selectedEntries.isEmpty else { return }
        let approved = selectedEntries
        busy = true
        status = "Clearing selected caches… Keep this window open."
        let engine = core
        Task {
            let report = await Task.detached { engine.clean(approved) }.value
            result = report
            free = report.after
            let successful = Set(report.events.filter { $0.outcome == "Cleared" }.map { $0.path })
            entries.removeAll { successful.contains(engine.home.appendingPathComponent($0.id).path) }
            selected = []
            busy = false
            status = "Cleanup finished. No cleanup is running in the background."
        }
    }
}

@main struct MacCleanupApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var model = CleanupModel()
    var body: some Scene {
        WindowGroup("Pankaj Mac Cleanup") {
            CleanupRootView(model: model).frame(minWidth: 820, minHeight: 740)
                .onAppear {
                    NSApp.activate(ignoringOtherApps: true)
                    DispatchQueue.main.async { NSApp.windows.first?.delegate = delegate }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .commands { CommandGroup(replacing: .newItem) {} }
    }
}

struct CleanupView: View {
    @ObservedObject var model: CleanupModel
    @State private var confirm = false
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("A little more room.").font(.system(size: 31, weight: .bold, design: .rounded))
                    Text("Pankaj Mac Cleanup · Local, manual, and in your control")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "internaldrive.fill").font(.system(size: 36)).foregroundStyle(.teal)
            }.padding(.top, 15)

            HStack(spacing: 15) {
                metric("Free on your Mac", model.free.map(size) ?? "Scan to check", "internaldrive")
                metric("Selected cache", size(model.selectedBytes), "checkmark.circle")
                metric("Runs automatically", "Never", "hand.raised")
            }

            HStack {
                Label(model.status, systemImage: model.busy ? "hourglass" : "checkmark.shield")
                    .font(.callout).foregroundStyle(.secondary)
                Spacer()
                if model.busy { ProgressView().controlSize(.small) }
            }

            if let report = model.result {
                VStack(alignment: .leading, spacing: 6) {
                    let total = report.events.filter { $0.outcome == "Cleared" }.reduce(Int64(0)) { $0 + $1.measuredBytes }
                    Text("Cleared \(size(total)) of measured cache").font(.headline)
                    if let before = report.before, let after = report.after {
                        Text("Free space: \(size(before)) → \(size(after)). Other apps can also change free space.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(Array(report.events.enumerated()), id: \.offset) { _, event in
                        Text("\(event.cache): \(event.outcome)").font(.caption).textSelection(.enabled)
                    }
                    if let warning = report.historyWarning { Text(warning).foregroundStyle(.orange).font(.caption) }
                }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.teal.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
            }

            ScrollView {
                LazyVStack(spacing: 9) {
                    if !model.scanned {
                        VStack(spacing: 14) {
                            Image(systemName: "magnifyingglass").font(.system(size: 38)).foregroundStyle(.teal)
                            Text("Start with a scan").font(.title2.bold())
                            Text("See what is taking space before choosing anything.\nScanning never deletes files.")
                                .multilineTextAlignment(.center).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity).padding(.vertical, 65)
                    } else if model.entries.isEmpty {
                        Label("No supported caches found. Your Mac has room to breathe.", systemImage: "sparkles")
                            .padding(40)
                    }
                    ForEach(model.entries) { entry in
                        HStack(alignment: .top, spacing: 13) {
                            Toggle("Select \(entry.spec.name)", isOn: Binding(
                                get: { model.selected.contains(entry.id) },
                                set: { if $0 { model.selected.insert(entry.id) } else { model.selected.remove(entry.id) } }
                            )).labelsHidden().toggleStyle(.checkbox)
                                .disabled(model.busy || entry.blocked != nil)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(entry.spec.name).font(.headline)
                                Text(entry.spec.detail).font(.caption).foregroundStyle(.secondary)
                                Text(model.core.home.appendingPathComponent(entry.id).path)
                                    .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled)
                                if let reason = entry.blocked {
                                    Label(reason, systemImage: "lock.fill").font(.caption).foregroundStyle(.orange)
                                }
                            }
                            Spacer(minLength: 10)
                            Text(size(entry.bytes)).font(.headline.monospacedDigit())
                        }.padding(13).frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
                    }
                }
            }

            Text("Close apps and pause package installs before cleaning. Caches rebuild as you use apps. This tab handles caches only. Use Review files for individual local documents. Browser profiles, system files and emptying Trash stay outside this tool’s scope.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)

            HStack {
                Button("Show cleanup history") {
                    let folder = model.core.historyURL.deletingLastPathComponent()
                    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    NSWorkspace.shared.open(folder)
                }.buttonStyle(.link).disabled(model.busy)
                Spacer()
                Button(model.scanned ? "Scan again" : "Scan caches", action: model.scan)
                    .disabled(model.busy).controlSize(.large)
                Button("Clear selected · \(size(model.selectedBytes))") { confirm = true }
                    .buttonStyle(.borderedProminent).tint(.teal).controlSize(.large)
                    .disabled(model.busy || model.selectedEntries.isEmpty)
            }
        }.padding(26)
            .alert("Permanently clear selected caches?", isPresented: $confirm) {
                Button("Cancel", role: .cancel) {}
                Button("Clear caches", role: .destructive) { model.clean() }
            } message: {
                Text("\(model.selectedEntries.map { $0.spec.name }.joined(separator: ", "))\n\nAbout \(size(model.selectedBytes)). This bypasses Trash. These caches can rebuild. Apps and paths are checked again before deletion.")
            }
    }

    func metric(_ label: String, _ value: String, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(label, systemImage: icon).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.system(size: 22, weight: .semibold, design: .rounded)).lineLimit(1).minimumScaleFactor(0.7)
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.teal.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
    }
}
