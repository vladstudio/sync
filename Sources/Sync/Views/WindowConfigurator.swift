import SwiftUI

struct WindowConfigurator: NSViewRepresentable {
    let configure: (NSWindow) -> Void

    func makeNSView(context: Context) -> TrackingView {
        TrackingView(configure: configure)
    }

    func updateNSView(_ nsView: TrackingView, context: Context) {
        nsView.configure = configure
        nsView.applyConfiguration()
    }
}

final class TrackingView: NSView {
    var configure: (NSWindow) -> Void

    init(configure: @escaping (NSWindow) -> Void) {
        self.configure = configure
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyConfiguration()
    }

    func applyConfiguration() {
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.window else { return }
            self.configure(window)
        }
    }
}
