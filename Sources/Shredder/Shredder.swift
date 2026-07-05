import SwiftUI
import AppKit
import Darwin
import Security

@main
struct ShredderApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(width: 620)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .commands { CommandGroup(replacing: .newItem) { } }
    }
}

@MainActor
final class ShredderModel: ObservableObject {
    @Published var items: [URL] = []
    @Published var isWorking = false
    @Published var status = "Drop files or folders here"
    @Published var progress = 0.0
    @Published var errorMessage: String?

    func add(_ urls: [URL]) {
        guard !isWorking else { return }
        let existing = Set(items.map(\.standardizedFileURL.path))
        items.append(contentsOf: urls.filter { !existing.contains($0.standardizedFileURL.path) })
        status = items.isEmpty ? "Drop files or folders here" : "\(items.count) item\(items.count == 1 ? "" : "s") ready"
    }

    func choose() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.canCreateDirectories = false
        panel.prompt = "Choose"
        if panel.runModal() == .OK { add(panel.urls) }
    }

    func confirmAndShred() {
        guard !items.isEmpty, !isWorking else { return }
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "Permanently shred \(items.count) selected item\(items.count == 1 ? "" : "s")?"
        let configuredPasses = UserDefaults.standard.integer(forKey: "overwritePasses")
        let passes = [1, 3, 7].contains(configuredPasses) ? configuredPasses : 3
        alert.informativeText = "This performs \(passes) overwrite pass\(passes == 1 ? "" : "es"), truncates, and unlinks each file. This cannot be undone. APFS, SSD wear-leveling, snapshots, and backups may retain earlier data blocks."
        alert.addButton(withTitle: "Shred Permanently")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        start()
    }

    private func start() {
        let targets = items
        let defaults = UserDefaults.standard
        let configuredPasses = defaults.integer(forKey: "overwritePasses")
        let settings = ShredSettings(
            passes: [1, 3, 7].contains(configuredPasses) ? configuredPasses : 3,
            randomEveryPass: defaults.bool(forKey: "randomEveryPass"),
            obfuscateNames: defaults.object(forKey: "obfuscateNames") as? Bool ?? true
        )
        let playCompletionSound = defaults.object(forKey: "completionSound") as? Bool ?? true
        isWorking = true
        progress = 0
        status = "Preparing…"
        errorMessage = nil
        Task {
            do {
                try await ShredEngine.shred(targets, settings: settings) { [weak self] value, message in
                    Task { @MainActor in
                        self?.progress = value
                        self?.status = message
                    }
                }
                items.removeAll()
                progress = 1
                status = "Shredding complete"
                if playCompletionSound { NSSound(named: "Glass")?.play() }
            } catch {
                errorMessage = error.localizedDescription
                status = "Shredding stopped"
            }
            isWorking = false
        }
    }

}

private final class FirstClickButton: NSButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private struct ShredButton: NSViewRepresentable {
    let enabled: Bool
    let action: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(action: action) }

    func makeNSView(context: Context) -> NSButton {
        let button = FirstClickButton(title: "Shred Permanently", target: context.coordinator, action: #selector(Coordinator.performAction))
        button.bezelStyle = .rounded
        button.bezelColor = .systemRed
        button.contentTintColor = .white
        button.controlSize = .large
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        button.isEnabled = enabled
        context.coordinator.action = action
    }

    final class Coordinator: NSObject {
        var action: () -> Void
        init(action: @escaping () -> Void) { self.action = action }
        @objc func performAction() { action() }
    }
}

struct ContentView: View {
    @StateObject private var model = ShredderModel()
    @State private var targeted = false
    @State private var showingSettings = false

    var body: some View {
        VStack(spacing: 18) {
            HStack {
                Image(systemName: "doc.badge.gearshape")
                    .font(.system(size: 25, weight: .semibold))
                    .foregroundStyle(.red)
                Text("Shredder").font(.system(size: 28, weight: .bold, design: .rounded))
                Spacer()
                Button { showingSettings = true } label: {
                    Image(systemName: "gearshape.fill").font(.title3)
                }
                .buttonStyle(.borderless)
                .help("Settings")
            }

            VStack(spacing: 12) {
                Image(systemName: targeted ? "arrow.down.doc.fill" : "arrow.down.doc")
                    .font(.system(size: 50, weight: .light))
                    .foregroundStyle(targeted ? .red : .secondary)
                Text(model.status).font(.title3.weight(.semibold))
                Text("Files are overwritten 3 times before removal")
                    .foregroundStyle(.secondary)
                Button("Choose Files or Folders…") { model.choose() }
                    .disabled(model.isWorking)
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 32)
            .frame(maxWidth: .infinity, minHeight: 150)
            .background(targeted ? Color.red.opacity(0.10) : Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(targeted ? Color.red : Color.secondary.opacity(0.25), style: StrokeStyle(lineWidth: 2, dash: [8])))
            .onDrop(of: [.fileURL], isTargeted: $targeted) { providers in
                for provider in providers {
                    _ = provider.loadObject(ofClass: URL.self) { url, _ in
                        if let url { Task { @MainActor in model.add([url]) } }
                    }
                }
                return true
            }

            if !model.items.isEmpty {
                List {
                    ForEach(model.items, id: \.standardizedFileURL) { url in
                        HStack {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 24, height: 24)
                            VStack(alignment: .leading) {
                                Text(url.lastPathComponent).lineLimit(1)
                                Text(url.deletingLastPathComponent().path).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                            if !model.isWorking {
                                Button { model.items.removeAll { $0 == url } } label: { Image(systemName: "xmark.circle.fill") }
                                    .buttonStyle(.plain).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .listStyle(.inset)
                .frame(height: 130)
            }

            if model.isWorking { ProgressView(value: model.progress) }
            if let error = model.errorMessage { Text(error).foregroundStyle(.red).font(.caption).textSelection(.enabled) }

            HStack {
                Text("Not guaranteed against SSD wear-leveling, APFS snapshots, or backups.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                ShredButton(enabled: !model.items.isEmpty && !model.isWorking) {
                    model.confirmAndShred()
                }
                .fixedSize()
            }
        }
        .padding(24)
        .sheet(isPresented: $showingSettings) { SettingsView() }
    }
}

private struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("overwritePasses") private var overwritePasses = 3
    @AppStorage("randomEveryPass") private var randomEveryPass = false
    @AppStorage("obfuscateNames") private var obfuscateNames = true
    @AppStorage("completionSound") private var completionSound = true

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                Text("Settings").font(.title2.bold())
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }

            GroupBox("Overwrite") {
                VStack(alignment: .leading, spacing: 14) {
                    Picker("Passes", selection: $overwritePasses) {
                        Text("1 (Fast)").tag(1)
                        Text("3 (Default)").tag(3)
                        Text("7 (Thorough)").tag(7)
                    }
                    .pickerStyle(.segmented)
                    Toggle("Use cryptographically random data on every pass", isOn: $randomEveryPass)
                    Text(randomEveryPass
                         ? "Every pass uses fresh random bytes."
                         : "Passes alternate zeros, ones, and fresh random bytes.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(8)
            }

            GroupBox("Removal") {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Replace file and folder names before unlinking", isOn: $obfuscateNames)
                    Toggle("Play a sound when shredding completes", isOn: $completionSound)
                }
                .padding(8)
            }

            Label("Confirmation before shredding is always required.", systemImage: "lock.shield")
                .font(.callout).foregroundStyle(.secondary)
            Text("No overwrite setting can guarantee physical erasure on APFS, SSDs, snapshots, or backups.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(26)
        .frame(width: 520)
    }
}

enum ShredError: LocalizedError {
    case unsupported(String), system(String, Int32)
    var errorDescription: String? {
        switch self {
        case .unsupported(let path): return "Unsupported file type: \(path)"
        case .system(let operation, let code): return "\(operation): \(String(cString: strerror(code)))"
        }
    }
}

struct ShredSettings: Sendable {
    var passes = 3
    var randomEveryPass = false
    var obfuscateNames = true
}

enum ShredEngine {
    typealias Progress = @Sendable (Double, String) -> Void

    static func shred(_ roots: [URL], settings: ShredSettings = ShredSettings(), progress: @escaping Progress) async throws {
        try await Task.detached(priority: .userInitiated) {
            var files: [URL] = []
            var directories: [URL] = []
            for root in roots { try collect(root, files: &files, directories: &directories) }
            let total = max(files.count, 1)
            for (index, file) in files.enumerated() {
                progress(Double(index) / Double(total), "Shredding \(file.lastPathComponent)…")
                try overwriteAndRemove(file, settings: settings)
            }
            for directory in directories.sorted(by: { $0.path.count > $1.path.count }) {
                try removeDirectory(directory, obfuscateName: settings.obfuscateNames)
            }
            progress(1, "Shredding complete")
        }.value
    }

    private static func collect(_ url: URL, files: inout [URL], directories: inout [URL]) throws {
        var info = stat()
        guard lstat(url.path, &info) == 0 else { throw ShredError.system("Inspect \(url.path)", errno) }
        let kind = info.st_mode & S_IFMT
        if kind == S_IFREG || kind == S_IFLNK {
            files.append(url)
        } else if kind == S_IFDIR {
            let children = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: [])
            for child in children { try collect(child, files: &files, directories: &directories) }
            directories.append(url)
        } else {
            throw ShredError.unsupported(url.path)
        }
    }

    private static func overwriteAndRemove(_ url: URL, settings: ShredSettings) throws {
        var info = stat()
        guard lstat(url.path, &info) == 0 else { throw ShredError.system("Inspect \(url.path)", errno) }
        if (info.st_mode & S_IFMT) == S_IFLNK {
            guard unlink(url.path) == 0 else { throw ShredError.system("Remove link \(url.path)", errno) }
            return
        }
        let fd = open(url.path, O_WRONLY | O_NOFOLLOW)
        guard fd >= 0 else { throw ShredError.system("Open \(url.path)", errno) }
        defer { close(fd) }
        let length = info.st_size
        for pass in 0..<settings.passes {
            guard lseek(fd, 0, SEEK_SET) >= 0 else { throw ShredError.system("Seek \(url.path)", errno) }
            try writePass(fd: fd, length: length, pass: pass, randomEveryPass: settings.randomEveryPass, path: url.path)
            guard fsync(fd) == 0 else { throw ShredError.system("Sync \(url.path)", errno) }
        }
        guard ftruncate(fd, 0) == 0 else { throw ShredError.system("Truncate \(url.path)", errno) }
        guard fsync(fd) == 0 else { throw ShredError.system("Sync \(url.path)", errno) }
        if settings.obfuscateNames {
            let renamed = url.deletingLastPathComponent().appendingPathComponent(".shred-\(UUID().uuidString)")
            guard rename(url.path, renamed.path) == 0 else { throw ShredError.system("Rename \(url.path)", errno) }
            guard unlink(renamed.path) == 0 else { throw ShredError.system("Remove \(renamed.path)", errno) }
        } else if unlink(url.path) != 0 {
            throw ShredError.system("Remove \(url.path)", errno)
        }
    }

    private static func writePass(fd: Int32, length: off_t, pass: Int, randomEveryPass: Bool, path: String) throws {
        let chunk = 1024 * 1024
        var buffer = [UInt8](repeating: pass == 1 ? 0xFF : 0, count: chunk)
        var remaining = Int64(length)
        while remaining > 0 {
            let count = min(chunk, Int(remaining))
            if randomEveryPass || pass % 3 == 2 {
                let status = SecRandomCopyBytes(kSecRandomDefault, count, &buffer)
                guard status == errSecSuccess else { throw ShredError.system("Generate random data", EIO) }
            }
            var written = 0
            while written < count {
                let result = buffer.withUnsafeBytes { bytes in
                    Darwin.write(fd, bytes.baseAddress!.advanced(by: written), count - written)
                }
                guard result > 0 else { throw ShredError.system("Overwrite \(path)", errno) }
                written += result
            }
            remaining -= Int64(count)
        }
    }

    private static func removeDirectory(_ url: URL, obfuscateName: Bool) throws {
        if obfuscateName {
            let renamed = url.deletingLastPathComponent().appendingPathComponent(".shred-dir-\(UUID().uuidString)")
            guard rename(url.path, renamed.path) == 0 else { throw ShredError.system("Rename folder \(url.path)", errno) }
            guard rmdir(renamed.path) == 0 else { throw ShredError.system("Remove folder \(renamed.path)", errno) }
        } else if rmdir(url.path) != 0 {
            throw ShredError.system("Remove folder \(url.path)", errno)
        }
    }
}
