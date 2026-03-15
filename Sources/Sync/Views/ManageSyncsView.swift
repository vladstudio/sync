import SwiftUI

struct ManageSyncsView: View {
    @ObservedObject var store: ConfigStore
    @ObservedObject var manager: SyncManager
    @State private var selection: UUID?
    @State private var addingNew = false
    @State private var deletingConfig: SyncConfig?

    var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {

            List(selection: $selection) {
                ForEach(store.configs) { config in
                    let state = manager.state(for: config.id)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(config.name)
                            Spacer()
                            if state.isRunning {
                                ProgressView().controlSize(.small)
                            } else if let success = config.lastSyncSuccess {
                                Image(systemName: success ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundStyle(success ? .green : .red)
                                    .font(.caption)
                            }
                        }
                        Text("\(config.direction.label) · \(config.schedule.label)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .tag(config.id)
                }
            }
            .navigationSplitViewColumnWidth(220)
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button(action: {
                        addingNew = true
                        selection = nil
                    }) {
                        Image(systemName: "plus")
                    }

                    Button(action: {
                        if let id = selection, let config = store.configs.first(where: { $0.id == id }) {
                            deletingConfig = config
                        }
                    }) {
                        Image(systemName: "minus")
                    }
                    .disabled(selection == nil || addingNew)
                }
            }
        } detail: {
            if addingNew {
                EditSyncView(store: store, manager: manager) { config in
                    store.addConfig(config)
                    manager.setupSchedule(for: config)
                    addingNew = false
                    selection = config.id
                } onCancel: {
                    addingNew = false
                }
            } else if let id = selection, let config = store.configs.first(where: { $0.id == id }) {
                EditSyncView(store: store, manager: manager, config: config) { updated in
                    store.updateConfig(updated)
                    manager.teardownSchedule(for: updated.id)
                    manager.setupSchedule(for: updated)
                }
                .id(id)
            } else {
                Text("Select a sync or click + to add one")
                    .foregroundStyle(.secondary)
                    .navigationTitle("Manage Syncs")
            }
        }
        .frame(minWidth: 700, minHeight: 450)
        .onAppear { NSApp.setActivationPolicy(.regular) }
        .onDisappear { NSApp.setActivationPolicy(.accessory) }
        .onChange(of: selection) { _, _ in
            addingNew = false
        }
        .alert("Delete Sync?", isPresented: Binding(
            get: { deletingConfig != nil },
            set: { if !$0 { deletingConfig = nil } }
        )) {
            Button("Cancel", role: .cancel) { deletingConfig = nil }
            Button("Delete", role: .destructive) {
                if let config = deletingConfig {
                    manager.cancelSync(id: config.id)
                    manager.teardownSchedule(for: config.id)
                    if selection == config.id { selection = nil }
                    store.deleteConfig(id: config.id)
                }
                deletingConfig = nil
            }
        } message: {
            if let config = deletingConfig {
                Text("Are you sure you want to delete \"\(config.name)\"?")
            }
        }
    }
}

extension UUID: @retroactive Identifiable {
    public var id: UUID { self }
}
