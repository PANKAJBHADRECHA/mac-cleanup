import SwiftUI
import AppKit

struct CleanupRootView: View {
    @ObservedObject var model: CleanupModel
    @State private var tab = 0
    var body: some View {
        VStack(spacing: 0) {
            Picker("Cleanup mode", selection: $tab) {
                Text("Quick clean · Caches").tag(0)
                Text("Review files · Documents").tag(1)
            }.pickerStyle(.segmented).frame(maxWidth: 490).padding(.top, 22).padding(.bottom, 8)
                .disabled(model.busy)
            if tab == 0 { CleanupView(model: model) }
            else { FileReviewView(model: model) }
        }
    }
}

extension CleanupModel {
    func checkBackup(then: @escaping (BackupStatus) -> Void) {
        guard !busy else { return }
        busy = true
        reviewStatus = "Checking the latest accessible Time Machine backup…"
        Task {
            let value = await Task.detached { BackupStatus.check() }.value
            backup = value
            busy = false
            reviewStatus = "Choose a local folder. Scanning reads file details only."
            then(value)
        }
    }

    func scanFiles(in folder: URL) {
        guard !busy else { return }
        do {
            let engine = try FileReviewCore(root: folder)
            reviewEngine = engine
            reviewFolder = folder
            reviewScan = nil
            busy = true
            reviewStatus = "Reviewing file sizes and dates… Nothing is being moved."
            let minimum = minimumFileBytes
            Task {
                let data = await Task.detached { () -> (FileReviewScan?, String?, Int64?) in
                    do { return (try engine.scan(minimumBytes: minimum), nil, CleanupCore.freeBytes()) }
                    catch { return (nil, error.localizedDescription, CleanupCore.freeBytes()) }
                }.value
                reviewScan = data.0
                free = data.2
                reviewStatus = data.1 ?? "Review complete. Check each file before moving it to Trash."
                busy = false
            }
        } catch {
            reviewScan = nil
            reviewFolder = nil
            reviewEngine = nil
            reviewStatus = error.localizedDescription
        }
    }

    func trashFile(_ file: ReviewFile) {
        guard !busy, let engine = reviewEngine else { return }
        busy = true
        reviewStatus = "Moving the confirmed file to Trash…"
        Task {
            let data = await Task.detached { () -> (TrashReceipt?, String?, Int64?) in
                do {
                    let result = try engine.trash(file)
                    return (result.0, result.1, CleanupCore.freeBytes())
                } catch { return (nil, error.localizedDescription, CleanupCore.freeBytes()) }
            }.value
            if let receipt = data.0 {
                movedFiles.append(receipt)
                if let previous = reviewScan {
                    reviewScan = FileReviewScan(files: previous.files.filter { $0.id != file.id },
                                               inspected: previous.inspected, omitted: previous.omitted,
                                               stoppedEarly: previous.stoppedEarly, matchingCount: max(0, previous.matchingCount - 1))
                }
                reviewStatus = data.1 ?? "Moved to Trash. You can restore it in Finder. No space reclaimed yet."
            } else { reviewStatus = data.1 ?? "Could not move this file. Review it in Finder." }
            free = data.2
            busy = false
        }
    }
}

struct FileReviewView: View {
    @ObservedObject var model: CleanupModel
    @State private var backupWarning = false
    @State private var pendingFile: ReviewFile?
    @State private var confirmTrash = false
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            folderControls
                .alert("Back up before reviewing personal files", isPresented: $backupWarning) {
                    Button("Cancel", role: .cancel) {}
                    Button("Continue to file review") { chooseFolder() }
                } message: {
                    Text((model.backup?.message ?? "Backup could not be verified.") + "\n\nContinue anyway? Files will only move to Trash after you confirm each one.")
                }
            if let backup = model.backup {
                Label(backup.message, systemImage: backup.needsAcknowledgement ? "externaldrive.badge.exclamationmark" : "externaldrive.badge.checkmark")
                    .font(.caption).foregroundStyle(backup.needsAcknowledgement ? Color.orange : Color.secondary)
                    .textSelection(.enabled)
            }
            HStack {
                Text(model.reviewStatus).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                Spacer()
                if model.busy { ProgressView().controlSize(.small) }
            }
            if !model.movedFiles.isEmpty { trashSummary }
            fileList
            footer
        }.padding(26)
            .alert("Move this file to Trash?", isPresented: $confirmTrash, presenting: pendingFile) { file in
                Button("Cancel", role: .cancel) { pendingFile = nil }
                Button("Move to Trash", role: .destructive) { model.trashFile(file); pendingFile = nil }
            } message: { file in
                Text("\(file.url.lastPathComponent)\n\(file.url.path)\n\nSize: \(size(file.bytes))\nModified: \(file.modified.formatted(date: .abbreviated, time: .shortened))\n\nThis confirms only this file. Restore it using Finder’s Trash → Put Back. Space is not reclaimed until you empty Trash yourself.")
            }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Keep what matters.").font(.system(size: 31, weight: .bold, design: .rounded))
                Text("Review local files · Largest first · Confirm one file at a time")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text("Free on your Mac").font(.caption).foregroundStyle(.secondary)
                Text(model.free.map(size) ?? "Scan to check").font(.title2.bold())
            }
        }.padding(.top, 12)
    }

    private var folderControls: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Button(model.reviewFolder == nil ? "Choose folder…" : "Change folder…") {
                    model.checkBackup { status in
                        if status.needsAcknowledgement { backupWarning = true }
                        else { chooseFolder() }
                    }
                }.controlSize(.large)
                Picker("Show", selection: $model.minimumFileBytes) {
                    Text("All sizes").tag(Int64(0))
                    Text("10 MB+").tag(Int64(10_000_000))
                    Text("100 MB+").tag(Int64(100_000_000))
                    Text("1 GB+").tag(Int64(1_000_000_000))
                }.frame(width: 170)
                Spacer()
                Button("Scan again") {
                    if let folder = model.reviewFolder { model.scanFiles(in: folder) }
                }.disabled(model.reviewFolder == nil).controlSize(.large)
            }.disabled(model.busy)
            if let folder = model.reviewFolder {
                Text(folder.path).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled)
            } else {
                Text("Choose Documents, Downloads, Desktop, or a local subfolder inside them.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.padding(14).background(Color.teal.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
            .onChange(of: model.minimumFileBytes) { _ in
                if !model.busy, let folder = model.reviewFolder { model.scanFiles(in: folder) }
            }
    }

    private var fileList: some View {
        ScrollView {
            LazyVStack(spacing: 9) {
                if let scan = model.reviewScan {
                    Text("Showing \(scan.files.count) of \(scan.matchingCount) matching files · \(scan.inspected) files inspected · \(scan.omitted) inaccessible or excluded items")
                        .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                    if scan.stoppedEarly {
                        Text("This is a partial scan. Choose a smaller subfolder to review the rest.")
                            .font(.caption).foregroundStyle(.orange)
                    }
                    if scan.matchingCount > scan.files.count {
                        Text("Only the 500 largest matches are shown. Choose a smaller folder for more detail.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if scan.files.isEmpty {
                        Text("No eligible files at this size. Try All sizes or choose another local folder.")
                            .foregroundStyle(.secondary).padding(36)
                    }
                    ForEach(scan.files) { file in
                        ReviewFileRow(file: file, busy: model.busy) {
                            pendingFile = file
                            confirmTrash = true
                        }
                    }
                } else if !model.busy {
                    VStack(spacing: 12) {
                        Image(systemName: "doc.text.magnifyingglass").font(.system(size: 40)).foregroundStyle(.teal)
                        Text("Your files deserve a closer look.").font(.title2.bold())
                        Text("Choose a folder to see names, sizes and dates.\nNothing is selected or moved automatically.")
                            .multilineTextAlignment(.center).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity).padding(.vertical, 45)
                }
            }
        }
    }

    private var trashSummary: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("Moved this session: \(model.movedFiles.count) file(s), \(size(model.movedFiles.reduce(0) { $0 + $1.bytes }))")
                    .font(.headline)
                Text("Waiting in Trash. Empty it yourself only after you are sure.").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Open Trash") { NSWorkspace.shared.open(model.core.home.appendingPathComponent(".Trash")) }
        }.padding(12).background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("CHECK WITH ME · Every file needs its own confirmation. iCloud files, links, hidden folders, packages and libraries are excluded. Avoid folders managed by other sync apps. This app never empties Trash. Preview with Show in Finder, then press Space.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Show cleanup history") {
                    let folder = model.core.historyURL.deletingLastPathComponent()
                    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    NSWorkspace.shared.open(folder)
                }.buttonStyle(.link)
                Spacer()
                Text("No automatic deletion. No background schedule.").font(.caption).foregroundStyle(.secondary)
            }.disabled(model.busy)
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose a local folder to review"
        panel.message = "Choose Documents, Downloads, Desktop, or a subfolder. Cloud locations and libraries are excluded."
        panel.prompt = "Review folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.directoryURL = model.reviewFolder ?? model.core.home.appendingPathComponent("Documents")
        if panel.runModal() == .OK, let url = panel.url { model.scanFiles(in: url) }
    }
}

private struct ReviewFileRow: View {
    let file: ReviewFile
    let busy: Bool
    let requestTrash: () -> Void
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "doc").font(.title2).foregroundStyle(.teal).padding(.top, 3)
            VStack(alignment: .leading, spacing: 5) {
                Text(file.url.lastPathComponent).font(.headline).textSelection(.enabled)
                Text(file.url.path).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled)
                Text("Modified \(file.modified.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption).foregroundStyle(.secondary)
                if file.modified > Date().addingTimeInterval(-30 * 24 * 60 * 60) {
                    Text("Recent file · modified in the last 30 days").font(.caption).foregroundStyle(.orange)
                }
                HStack {
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([file.url]) }
                    Button("Move to Trash", role: .destructive, action: requestTrash)
                }.font(.caption).disabled(busy)
            }
            Spacer(minLength: 8)
            Text(size(file.bytes)).font(.headline.monospacedDigit())
        }.padding(13).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
    }
}
