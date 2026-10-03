import SwiftUI

struct ContentView: View {
    @Bindable var session: PhotoSession

    @AppStorage("themeDirection") private var direction: ThemeDirection = .studio
    @AppStorage("appearanceMode") private var appearance: AppearanceMode = .system
    /// Оформление macOS; читаем у приложения, а не у окна — окну мы его задаём сами
    @State private var systemIsLight = SystemAppearance.isLight

    private var wantsLight: Bool {
        switch appearance {
        case .system: systemIsLight
        case .light: true
        case .dark: false
        }
    }

    var body: some View {
        // Светлыми бывают только стартовое окно и сетка; просмотр, рисование и сравнение — всегда тёмные
        let chrome = Theme.make(direction, light: wantsLight)
        let dark = Theme.make(direction, light: false)
        let screenTheme: Theme = {
            guard session.isViewing else { return chrome }
            if session.viewMode == .grid && !session.photos.isEmpty { return chrome }
            return dark
        }()

        Group {
            if session.isViewing {
                if session.viewMode == .grid && !session.photos.isEmpty {
                    GridView(session: session)
                } else if session.viewMode == .compare && session.photos.count >= 2 {
                    CompareView(session: session)
                } else {
                    ViewerView(session: session)
                }
            } else {
                SetupView(session: session)
            }
        }
        .themed(screenTheme)
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
