import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: ConfigStore
    @State private var pathStatus: PathStatus = .unknown

    private enum PathStatus {
        case unknown, valid(String), invalid
    }

    var body: some View {
        Form {
            HStack {
                TextField("rclone path", text: $store.settings.rclonePath)
                Button("Browse") {
                    let panel = NSOpenPanel()
                    panel.canChooseFiles = true
                    panel.canChooseDirectories = false
                    panel.allowsMultipleSelection = false
                    if panel.runModal() == .OK, let url = panel.url {
                        store.settings.rclonePath = url.path
                    }
                }
            }

            switch pathStatus {
            case .unknown:
                EmptyView()
            case .valid(let version):
                Label(version, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.caption)
            case .invalid:
                Label("Not found at this path", systemImage: "xmark.circle.fill")
                    .foregroundStyle(.red)
                    .font(.caption)
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .frame(width: 450)
        .onChange(of: store.settings.rclonePath) { _, _ in
            store.saveSettings()
            validatePath()
        }
        .onAppear {
            WindowTracker.opened()
            validatePath()
        }
        .onDisappear { WindowTracker.closed() }
    }

    private func validatePath() {
        let rclone = RcloneService(rclonePath: store.settings.rclonePath)
        Task {
            do {
                let version = try await rclone.version()
                pathStatus = .valid(version)
            } catch {
                pathStatus = .invalid
            }
        }
    }
}
