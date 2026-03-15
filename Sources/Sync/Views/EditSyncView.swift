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
    var onShowLog: (() -> Void)?
    @State private var scheduleResetNotice = false
    @State private var showAdvanced = false

    let onSave: (SyncConfig) -> Void
    var onCancel: (() -> Void)?
    let isEditing: Bool

    init(store: ConfigStore, manager: SyncManager, config: SyncConfig? = nil, onSave: @escaping (SyncConfig) -> Void, onCancel: (() -> Void)? = nil, onShowLog: (() -> Void)? = nil) {
        self.store = store
        self.manager = manager
        self.onSave = onSave
        self.onCancel = onCancel
        self.onShowLog = onShowLog
        self.isEditing = config != nil

        let c = config ?? SyncConfig()
        _config = State(initialValue: c)
        _excludeText = State(initialValue: c.excludePatterns.joined(separator: "\n"))

        switch c.schedule {
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
                        Label(remote.name, systemImage: RemoteIcon.sfSymbol(for: remote.type))
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
                    Stepper("Every \(intervalMinutes) minutes", value: $intervalMinutes, in: 1...1440)
                }

                Picker("Mode", selection: $config.mode) {
                    ForEach(SyncMode.allCases, id: \.self) { m in
                        Text(m.label).tag(m)
                    }
                }

                Toggle("Back up deleted files", isOn: $config.keepDeletedFiles)

                if config.keepDeletedFiles {
                    Button("Reveal Backups in Finder") {
                        manager.revealBackups(id: config.id)
                    }
                }
            }

            Section(isExpanded: $showAdvanced) {
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

                TextField("Extra flags", text: $config.extraFlags)
                    .textFieldStyle(.roundedBorder)
            } header: {
                Text("Advanced")
            }

        }
        .formStyle(.grouped)
        .navigationTitle(isEditing ? config.name.isEmpty ? "Untitled" : config.name : "Create Sync")
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                Button("Dry Run") {
                    manager.dryRun(config: preparedConfig())
                    onShowLog?()
                }

                if isEditing {
                    Button("Sync Now") {
                        manager.syncNow(id: config.id)
                    }
                    .disabled(manager.state(for: config.id).isRunning)

                    Button("Log") {
                        onShowLog?()
                    }
                }

                if let onCancel {
                    Button("Cancel") { onCancel() }
                }

                if !isEditing {
                    Button("Save") {
                        onSave(preparedConfig())
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(config.name.isEmpty || config.localPath.isEmpty || config.remote.isEmpty)
                }
            }
        }
        .onChange(of: config) { _, _ in autoSave() }
        .onChange(of: scheduleType) { _, _ in autoSave() }
        .onChange(of: intervalMinutes) { _, _ in autoSave() }
        .onChange(of: excludeText) { _, _ in autoSave() }
        .task { await loadRemotes() }
    }

    private func autoSave() {
        guard isEditing else { return }
        onSave(preparedConfig())
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
