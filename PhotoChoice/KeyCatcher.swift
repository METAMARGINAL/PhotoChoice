import AppKit
import SwiftUI

struct KeyCatcher: NSViewRepresentable {
    var onKeyDown: (NSEvent) -> Bool
    var onMagnify: ((CGFloat, NSEvent.Phase) -> Void)?
    var onSmartMagnify: (() -> Void)?
    var onScroll: ((CGFloat, CGFloat) -> Void)?

    func makeNSView(context: Context) -> CatcherView {
        let view = CatcherView()
        apply(to: view)
        return view
    }

    func updateNSView(_ nsView: CatcherView, context: Context) {
        apply(to: nsView)
        if let window = nsView.window, window.firstResponder !== nsView {
            DispatchQueue.main.async {
                window.makeFirstResponder(nsView)
            }
        }
    }

    private func apply(to view: CatcherView) {
        view.onKeyDown = onKeyDown
        view.onMagnify = onMagnify
        view.onSmartMagnify = onSmartMagnify
        view.onScroll = onScroll
    }

    final class CatcherView: NSView {
        var onKeyDown: ((NSEvent) -> Bool)?
        var onMagnify: ((CGFloat, NSEvent.Phase) -> Void)?
        var onSmartMagnify: (() -> Void)?
        var onScroll: ((CGFloat, CGFloat) -> Void)?

        private var monitor: Any?

        override var acceptsFirstResponder: Bool { true }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            removeMonitor()
            guard let window else { return }
            window.makeFirstResponder(self)

            monitor = NSEvent.addLocalMonitorForEvents(
                matching: [.scrollWheel, .magnify, .smartMagnify]
            ) { [weak self] event in
                guard let self, event.window === self.window else { return event }
                return self.handle(event)
            }
        }

        deinit {
            removeMonitor()
        }

        override func keyDown(with event: NSEvent) {
            if onKeyDown?(event) != true {
                super.keyDown(with: event)
            }
        }

        private func handle(_ event: NSEvent) -> NSEvent? {
            switch event.type {
            // Без обработчика событие идёт дальше (например, скролл сетки)
            case .magnify:
                guard let onMagnify else { return event }
                onMagnify(event.magnification, event.phase)
                return nil
            case .smartMagnify:
                guard let onSmartMagnify else { return event }
                onSmartMagnify()
                return nil
            case .scrollWheel:
                guard let onScroll else { return event }
                let factor: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 10
                onScroll(event.scrollingDeltaX * factor, event.scrollingDeltaY * factor)
                return nil
            default:
                return event
            }
        }

        private func removeMonitor() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
            monitor = nil
        }
    }
}
