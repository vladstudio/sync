import SwiftUI

struct EditSyncView: View {
    @ObservedObject var store: ConfigStore
    @ObservedObject var manager: SyncManager

    @State private var config: SyncConfig
    @State private var remotes: [RcloneService.RemoteInfo] = []
    @State private var remotesLoaded = false
    @State private var remotesError: String?
    @State private var scheduleType: Int
    @State private var intervalMinutes: Int
    @State private var excludeText: String
    @State private var scheduleResetNotice = false
    @State private var showAdvanced = false
    @State private var showCleanupAlert = false
    @State private var showCleanupOnDemandAlert = false
    @State private var localBackupSize: String?
    @State private var cleaningUp = false

    let onChange: (SyncConfig) -> Void
    var onDelete: (() -> Void)?

    init(store: ConfigStore, manager: SyncManager, config: SyncConfig = SyncConfig(), onDelete: (() -> Void)? = nil, onChange: @escaping (SyncConfig) -> Void) {
        self.store = store
        self.manager = manager
        self.onChange = onChange
        self.onDelete = onDelete

        _config = State(initialValue: config)
        _excludeText = State(initialValue: config.excludePatterns.joined(separator: "\n"))

        switch config.schedule {
        case .manual:
            _scheduleType = State(initialValue: 0)
            _intervalMinutes = State(initialValue: 15)
        case .interval(let m):
            _scheduleType = State(initialValue: 1)
            _intervalMinutes = State(initialValue: m)
        case .onLocalChange:
            _scheduleType = State(initialValue: 2)
            _intervalMinutes = State(initialValue: 15)
        }
    }

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $config.name)

                HStack {
                    TextField("Local folder", text: $config.localPath)
                    Button("Browse") { pickFolder() }
                    if !config.localPath.isEmpty {
                        Button("Reveal") {
                            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: config.localPath)
                        }
                    }
                }

                if let error = remotesError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .font(.caption)
                } else if !remotesLoaded {
                    ProgressView().controlSize(.small)
                } else if remotes.isEmpty {
                    Label("No remotes found. Run \"rclone config\" to add one.", systemImage: "info.circle")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }

                Picker("Remote", selection: $config.remote) {
                    Text("Select...").tag("")
                    ForEach(remotes) { remote in
                        HStack {
                            RemoteIcon.icon(for: remote.type, size: 10)
                            Text(remote.name)
                        }
                        .tag(remote.name)
                    }
                }
                .onChange(of: config.remote) { _, newValue in
                    if let info = remotes.first(where: { $0.name == newValue }) {
                        config.remoteType = info.type
                    }
                }

                HStack {
                    TextField("Remote path", text: $config.remotePath)
                        .textFieldStyle(.roundedBorder)
                    if !config.remote.isEmpty {
                        Button("Open") { openRemote() }
                    }
                }

                Picker("Direction", selection: $config.direction) {
                    ForEach(Direction.allCases, id: \.self) { d in
                        Text(d.label).tag(d)
                    }
                }
                .onChange(of: config.direction) { _, newValue in
                    if newValue == .remoteToLocal && scheduleType == 2 {
                        scheduleType = 0
                        scheduleResetNotice = true
                        Task {
                            try? await Task.sleep(for: .seconds(4))
                            await MainActor.run { scheduleResetNotice = false }
                        }
                    }
                }

                Picker("Schedule", selection: $scheduleType) {
                    Text("Manual").tag(0)
                    Text("Interval").tag(1)
                    if config.direction != .remoteToLocal {
                        Text("On local change").tag(2)
                    }
                }

                if scheduleResetNotice {
                    Text("Schedule reset to Manual (not available for Remote → Local)")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                if scheduleType == 1 {
                    Picker("Interval", selection: $intervalMinutes) {
                        ForEach([1, 5, 10, 15, 30, 60], id: \.self) { m in
                            Text("Every \(m) minutes").tag(m)
                        }
                    }
                }

                if config.direction != .bidirectional {
                    Picker("Mode", selection: $config.mode) {
                        ForEach(SyncMode.allCases, id: \.self) { m in
                            Text(m.label).tag(m)
                        }
                    }
                }

                Toggle("Back up deleted files", isOn: $config.keepDeletedFiles)
                    .onChange(of: config.keepDeletedFiles) { _, newValue in
                        if !newValue { showCleanupAlert = true }
                    }

                if cleaningUp {
                    HStack(spacing: 4) {
                        ProgressView().controlSize(.small)
                        Text("Cleaning up backups…")
                            .foregroundStyle(.secondary)
                    }
                } else if config.keepDeletedFiles {
                    HStack {
                        Button("Reveal Local Backups") {
                            manager.revealBackups(id: config.id)
                        }
                        Button("Clean Up Backups") {
                            showCleanupOnDemandAlert = true
                        }
                        Spacer()
                        if let size = localBackupSize {
                            Text(size)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .onAppear { updateBackupSize() }
                }
            }

            Section(isExpanded: $showAdvanced) {
                Toggle("Compare by checksum", isOn: $config.useChecksum)
                    .help("Use file hash instead of modification time + size (slower but more accurate)")

                if config.direction != .bidirectional {
                    Toggle("Skip existing files", isOn: $config.ignoreExisting)
                        .help("Don't update files that already exist on the destination")
                }

                Picker("Parallel transfers", selection: $config.transfers) {
                    Text("Default (4)").tag(nil as Int?)
                    ForEach([1, 2, 4, 8, 16, 32], id: \.self) { n in
                        Text("\(n)").tag(n as Int?)
                    }
                }

                Picker("Parallel checkers", selection: $config.checkers) {
                    Text("Default (8)").tag(nil as Int?)
                    ForEach([1, 2, 4, 8, 16, 32, 64], id: \.self) { n in
                        Text("\(n)").tag(n as Int?)
                    }
                }

                TextField("Bandwidth limit", text: Binding(
                    get: { config.bandwidthLimit ?? "" },
                    set: { config.bandwidthLimit = $0.isEmpty ? nil : $0 }
                ), prompt: Text("e.g. 10M, 1.5G"))
                .textFieldStyle(.roundedBorder)

                VStack(alignment: .leading) {
                    Text("Exclude patterns (one per line)")
                        .font(.caption)
                    TextEditor(text: $excludeText)
                        .font(.system(.body, design: .monospaced))
                        .frame(height: 80)
                }

                HStack {
                    TextField("Extra rclone flags", text: $config.extraFlags)
                        .textFieldStyle(.roundedBorder)
                    Button {
                        NSWorkspace.shared.open(URL(string: "https://rclone.org/flags/")!)
                    } label: {
                        Image(systemName: "questionmark.circle")
                    }
                    .buttonStyle(.borderless)
                    .help("Open rclone flags documentation")
                }
            } header: {
                Button { showAdvanced.toggle() } label: {
                    Text("Advanced")
                }
                .buttonStyle(.plain)
            }

            if let onDelete {
                Section {
                    Button("Delete Sync", role: .destructive) {
                        onDelete()
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onChange(of: preparedConfig()) { _, new in onChange(new) }
        .task { await loadRemotes() }
        .alert("Delete existing backups?", isPresented: $showCleanupAlert) {
            Button("Delete", role: .destructive) { runCleanup() }
            Button("Keep", role: .cancel) {}
        } message: {
            Text("Do you also want to delete existing local and remote backups for this sync?")
        }
        .alert("Clean up backups?", isPresented: $showCleanupOnDemandAlert) {
            Button("Delete", role: .destructive) { runCleanup() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will delete all local and remote backups for this sync.")
        }
    }

    private func preparedConfig() -> SyncConfig {
        var c = config
        switch scheduleType {
        case 1: c.schedule = .interval(minutes: intervalMinutes)
        case 2: c.schedule = .onLocalChange
        default: c.schedule = .manual
        }
        c.excludePatterns = excludeText.split(separator: "\n").map(String.init)
        return c
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            config.localPath = url.path
        }
    }

    private func openRemote() {
        let remotePath = "\(config.remote):\(config.remotePath)"
        Task {
            let rclone = RcloneService(rclonePath: store.settings.rclonePath)
            do {
                if let url = try await rclone.link(remotePath: remotePath) {
                    NSWorkspace.shared.open(url)
                }
            } catch {
                remotesError = "Failed to open remote: \(error.localizedDescription)"
            }
        }
    }

    private func runCleanup() {
        cleaningUp = true
        Task {
            do {
                try await manager.cleanupBackups(config: config)
            } catch {
                await MainActor.run {
                    store.lastError = error.localizedDescription
                }
            }
            await MainActor.run {
                cleaningUp = false
                updateBackupSize()
            }
        }
    }

    private func updateBackupSize() {
        let dir = ConfigStore.backupsDir.appendingPathComponent(config.id.uuidString)
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: dir, includingPropertiesForKeys: [.fileSizeKey]) else {
            localBackupSize = nil
            return
        }
        var total: Int64 = 0
        for case let url as URL in enumerator {
            total += (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).flatMap { Int64($0) } ?? 0
        }
        localBackupSize = total > 0 ? ByteCountFormatter.string(fromByteCount: total, countStyle: .file) : nil
    }

    private func loadRemotes() async {
        let rclone = RcloneService(rclonePath: store.settings.rclonePath)
        do {
            remotes = try await rclone.listRemotes()
            remotesError = nil
        } catch {
            remotes = []
            remotesError = "Could not load remotes: \(error.localizedDescription)"
        }
        remotesLoaded = true
    }
}
