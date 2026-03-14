import SwiftUI
import AppKit

struct EditSyncView: View {
    @ObservedObject var store: ConfigStore
    @ObservedObject var manager: SyncManager
    @Environment(\.dismiss) private var dismiss

    @State private var config: SyncConfig
    @State private var remotes: [String] = []
    @State private var loadingRemotes = false
    @State private var scheduleType: Int // 0=manual, 1=interval, 2=onLocalChange
    @State private var intervalMinutes: Int
    @State private var excludeText: String
    @State private var showingLog = false

    let onSave: (SyncConfig) -> Void
    let isEditing: Bool

    init(store: ConfigStore, manager: SyncManager, config: SyncConfig? = nil, onSave: @escaping (SyncConfig) -> Void) {
        self.store = store
        self.manager = manager
        self.onSave = onSave
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
            Section("General") {
                TextField("Name", text: $config.name)

                HStack {
                    TextField("Local folder", text: $config.localPath)
                    Button("Browse") { pickFolder() }
                }

                Picker("Remote", selection: $config.remote) {
                    Text("Select...").tag("")
                    ForEach(remotes, id: \.self) { remote in
                        Text(remote).tag(remote)
                    }
                }

                TextField("Remote path", text: $config.remotePath)
                    .textFieldStyle(.roundedBorder)
            }

            Section("Sync Options") {
                Picker("Direction", selection: $config.direction) {
                    ForEach(Direction.allCases, id: \.self) { d in
                        Text(d.label).tag(d)
                    }
                }

                Picker("Schedule", selection: $scheduleType) {
                    Text("Manual").tag(0)
                    Text("Interval").tag(1)
                    if config.direction != .remoteToLocal {
                        Text("On local change").tag(2)
                    }
                }

                if scheduleType == 1 {
                    Stepper("Every \(intervalMinutes) minutes", value: $intervalMinutes, in: 1...1440)
                }

                Picker("Mode", selection: $config.mode) {
                    ForEach(SyncMode.allCases, id: \.self) { m in
                        Text(m.label).tag(m)
                    }
                }

                Toggle("Keep deleted files (backup)", isOn: $config.keepDeletedFiles)

                if config.keepDeletedFiles {
                    Button("Reveal Backups in Finder") {
                        manager.revealBackups(id: config.id)
                    }
                }
            }

            Section("Advanced") {
                TextField("Bandwidth limit", text: Binding(
                    get: { config.bandwidthLimit ?? "" },
                    set: { config.bandwidthLimit = $0.isEmpty ? nil : $0 }
                ))
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
            }

            Section {
                HStack {
                    Button("Dry Run") {
                        applySchedule()
                        config.excludePatterns = excludeText.split(separator: "\n").map(String.init)
                        onSave(config)
                        manager.syncNow(id: config.id, dryRun: true)
                        showingLog = true
                    }

                    Spacer()

                    Button("Cancel") { dismiss() }
                    Button("Save") {
                        applySchedule()
                        config.excludePatterns = excludeText.split(separator: "\n").map(String.init)
                        onSave(config)
                        dismiss()
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(config.name.isEmpty || config.localPath.isEmpty || config.remote.isEmpty)
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 500, minHeight: 500)
        .navigationTitle(isEditing ? "Edit Sync" : "New Sync")
        .task { await loadRemotes() }
        .sheet(isPresented: $showingLog) {
            LogView(configId: config.id, manager: manager)
        }
    }

    private func applySchedule() {
        switch scheduleType {
        case 1: config.schedule = .interval(minutes: intervalMinutes)
        case 2: config.schedule = .onLocalChange
        default: config.schedule = .manual
        }
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

    private func loadRemotes() async {
        loadingRemotes = true
        defer { loadingRemotes = false }
        let rclone = RcloneService(rclonePath: store.settings.rclonePath)
        do {
            remotes = try await rclone.listRemotes()
        } catch {
            remotes = []
        }
    }
}
