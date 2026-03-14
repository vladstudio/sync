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
        .onAppear { validatePath() }
    }

    private func validatePath() {
        let path = store.settings.rclonePath
        guard FileManager.default.isExecutableFile(atPath: path) else {
            pathStatus = .invalid
            return
        }
        Task {
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = ["version"]
            process.standardOutput = pipe
            process.standardError = pipe
            do {
                try process.run()
                process.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let output = String(data: data, encoding: .utf8),
                   let firstLine = output.split(separator: "\n").first {
                    await MainActor.run { pathStatus = .valid(String(firstLine)) }
                } else {
                    await MainActor.run { pathStatus = .valid("rclone found") }
                }
            } catch {
                await MainActor.run { pathStatus = .invalid }
            }
        }
    }
}
