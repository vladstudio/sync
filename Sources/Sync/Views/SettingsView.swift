import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: ConfigStore

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
        }
        .formStyle(.grouped)
        .padding()
        .onChange(of: store.settings.rclonePath) { _, _ in
            store.saveSettings()
        }
    }
}
