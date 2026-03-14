import SwiftUI

struct ManageSyncsView: View {
    @ObservedObject var store: ConfigStore
    @ObservedObject var manager: SyncManager
    @State private var editingConfig: SyncConfig?
    @State private var showingAdd = false
    @State private var logConfigId: UUID?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Syncs").font(.title2).bold()
                Spacer()
                Button("Add New Sync") { showingAdd = true }
            }
            .padding()

            if store.configs.isEmpty {
                Spacer()
                Text("No syncs configured. Click \"Add New Sync\" to get started.")
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                List {
                    ForEach(store.configs) { config in
                        let state = manager.state(for: config.id)
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(config.name).font(.headline)
                                Text("\(config.direction.label) · \(config.mode.label)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            if state.isRunning {
                                ProgressView().controlSize(.small)
                                Text("Syncing").foregroundStyle(.secondary).font(.caption)
                            } else if let success = config.lastSyncSuccess {
                                Image(systemName: success ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundStyle(success ? .green : .red)
                            }

                            Button("Log") {
                                logConfigId = config.id
                            }

                            Button("Sync") {
                                manager.syncNow(id: config.id)
                            }
                            .disabled(state.isRunning)

                            Button("Edit") {
                                editingConfig = config
                            }

                            Button("Delete") {
                                manager.stopAll()
                                store.deleteConfig(id: config.id)
                                manager.refreshSchedules()
                            }
                            .foregroundStyle(.red)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .sheet(isPresented: $showingAdd) {
            EditSyncView(store: store, manager: manager) { config in
                store.addConfig(config)
                manager.setupSchedule(for: config)
            }
        }
        .sheet(item: $editingConfig) { config in
            EditSyncView(store: store, manager: manager, config: config) { updated in
                store.updateConfig(updated)
                manager.refreshSchedules()
            }
        }
        .sheet(item: $logConfigId) { id in
            LogView(configId: id, manager: manager)
        }
        .onAppear {
            manager.startAll()
        }
    }
}

extension UUID: @retroactive Identifiable {
    public var id: UUID { self }
}
