import SwiftUI

/// «Оформление»: тема и светлый или тёмный режим
struct AppearancePage: View {
    @Environment(\.theme) private var theme
    @AppStorage(Pref.themeDirection) private var direction: ThemeDirection = .neutral
    @AppStorage("appearanceMode") private var appearance: AppearanceMode = .system

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsHeader(
                title: "Оформление",
                subtitle: "У каждой темы одна идея. Просмотр, рисование и сравнение всегда тёмные: белое поле искажает яркость снимка."
            )

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(ThemeDirection.allCases) { option in
                    ThemeTile(direction: option, isSelected: option == direction, light: theme.isLight) {
                        withAnimation(.easeOut(duration: 0.2)) { direction = option }
                    }
                }
            }
            .padding(.top, 20)

            SettingsGroup("Режим") {
                PickerRow(
                    title: "Светлая или тёмная",
                    detail: direction.hasLight
                        ? "Светлыми становятся стартовое окно и сетка"
                        : (direction.alwaysLight ? "«\(direction.title)» всегда светлый" : "У темы «\(direction.title)» только тёмный вариант"),
                    options: AppearanceMode.allCases.map { (title: $0.title, value: $0) },
                    selection: $appearance
                )
                .settingsDimmed(!direction.hasLight)
            }
        }
    }
}
