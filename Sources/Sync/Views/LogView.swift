import SwiftUI

struct LogView: View {
    let configId: UUID
    @ObservedObject var manager: SyncManager
    var onClose: (() -> Void)?

    var body: some View {
        let state = manager.state(for: configId)

        VStack(spacing: 0) {
            HStack {
                Text("Sync Log").font(.headline)
                Spacer()
                if state.isRunning {
                    ProgressView().controlSize(.small)
                    Button("Cancel") { manager.cancelSync(id: configId) }
                }
                Button("Close") { onClose?() }
            }
            .padding()

            ScrollViewReader { proxy in
                ScrollView {
                    Text(state.log.isEmpty ? "No output yet." : state.log)
                        .font(.system(size: 11, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding()
                    Color.clear.frame(height: 1).id("anchor")
                }
                .onChange(of: state.log) { _, _ in
                    proxy.scrollTo("anchor", anchor: .bottom)
                }
            }
            .background(Color(nsColor: .textBackgroundColor))
        }
        .background(.background)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
