import SwiftUI

struct ContentView: View {
    @Bindable var session: PhotoSession

    @AppStorage(Pref.themeDirection) private var direction: ThemeDirection = .neutral
    @AppStorage("appearanceMode") private var appearance: AppearanceMode = .system
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Оформление macOS; читаем у приложения, а не у окна — окну мы его задаём сами
    @State private var systemIsLight = SystemAppearance.isLight

    private var wantsLight: Bool {
        switch appearance {
        case .system: systemIsLight
        case .light: true
        case .dark: false
        }
    }

    private var showsGrid: Bool {
        session.viewMode == .grid && !session.allPhotos.isEmpty
    }

    var body: some View {
        // Светлыми бывают только стартовое окно и сетка; просмотр, рисование и сравнение — всегда тёмные
        let chrome = Theme.chrome(direction, wantsLight: wantsLight)
        let dark = Theme.make(direction, light: false)
        let screenTheme: Theme = !session.isViewing || showsGrid ? chrome : dark

        ZStack {
            if session.isViewing {
                if showsGrid {
                    GridView(session: session)
                        .themed(chrome)
                        .transition(.opacity)
                } else if session.viewMode == .compare && session.photos.count >= 2 {
                    CompareView(session: session)
                        .themed(dark)
                        .transition(.opacity)
                } else {
                    // Кадр вырастает из сетки: открытие редкое, движение уместно
                    ViewerView(session: session)
                        .themed(dark)
                        .transition(reduceMotion ? AnyTransition.opacity : AnyTransition.scale(scale: 0.92).combined(with: .opacity))
                }
            } else {
                SetupView(session: session)
                    .themed(chrome)
            }
        }
        .animation(reduceMotion ? Animation.linear(duration: 0.1) : Animation.easeOut(duration: 0.24), value: session.viewMode)
        .background(screenTheme.c.app)
        .background(WindowAppearance(isLight: screenTheme.isLight))
        .frame(minWidth: 760, minHeight: 560)
        .onReceive(SystemAppearance.changes) { _ in
            // Оформление меняется чуть позже уведомления
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                systemIsLight = SystemAppearance.isLight
            }
        }
    }
}

#Preview {
    ContentView(session: PhotoSession())
}
