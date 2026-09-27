import AppKit
import SwiftUI

/// Событие прокрутки: трекпад (два пальца) или колесо мыши
struct ScrollInfo {
    var dx: CGFloat
    var dy: CGFloat
    var modifiers: NSEvent.ModifierFlags
    /// Положение курсора относительно центра вида, ось Y вниз
    var anchor: CGPoint
    var phase: NSEvent.Phase
    var momentumPhase: NSEvent.Phase
    /// true — трекпад/Magic Mouse, false — обычное колесо
    var isPrecise: Bool
    /// Включена «естественная» прокрутка
    var isNatural: Bool
}

struct KeyCatcher: NSViewRepresentable {
    var onKeyDown: (NSEvent) -> Bool
    /// Точка (CGPoint) — положение курсора относительно центра вида, ось Y вниз
    var onMagnify: ((CGFloat, NSEvent.Phase, CGPoint) -> Void)?
    var onSmartMagnify: ((CGPoint) -> Void)?
    /// Возвращает true, если прокрутка обработана; false — событие уходит дальше (например, в панель сведений)
    var onScroll: ((ScrollInfo) -> Bool)?
    /// ⌘C (Правка → Копировать), когда фокус у этого вида
    var onCopy: (() -> Void)?

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
        view.onCopy = onCopy
    }

    final class CatcherView: NSView, NSMenuItemValidation {
        var onKeyDown: ((NSEvent) -> Bool)?
        var onMagnify: ((CGFloat, NSEvent.Phase, CGPoint) -> Void)?
        var onSmartMagnify: ((CGPoint) -> Void)?
        var onScroll: ((ScrollInfo) -> Bool)?
        var onCopy: (() -> Void)?

        @objc func copy(_ sender: Any?) {
            onCopy?()
        }

        func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
            if menuItem.action == #selector(copy(_:)) {
                return onCopy != nil
            }
            return true
        }

        private var monitor: Any?

        override var acceptsFirstResponder: Bool { true }
        override var isFlipped: Bool { true }

        private func centerOffset(_ event: NSEvent) -> CGPoint {
            let point = convert(event.locationInWindow, from: nil)
            return CGPoint(x: point.x - bounds.midX, y: point.y - bounds.midY)
        }

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
                onMagnify(event.magnification, event.phase, centerOffset(event))
                return nil
            case .smartMagnify:
                guard let onSmartMagnify else { return event }
                onSmartMagnify(centerOffset(event))
                return nil
            case .scrollWheel:
                guard let onScroll else { return event }
                let factor: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 10
                let handled = onScroll(ScrollInfo(
                    dx: event.scrollingDeltaX * factor,
                    dy: event.scrollingDeltaY * factor,
                    modifiers: event.modifierFlags,
                    anchor: centerOffset(event),
                    phase: event.phase,
                    momentumPhase: event.momentumPhase,
                    isPrecise: event.hasPreciseScrollingDeltas,
                    isNatural: event.isDirectionInvertedFromDevice
                ))
                return handled ? nil : event
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
