import SwiftUI

/// Страницы окна настроек (docs/Settings.md, §3)
enum SettingsPage: String, CaseIterable, Identifiable {
    case features, transfer, marks, smart, view, appearance

    var id: String { rawValue }

    var title: String {
        switch self {
        case .features: "Функции"
        case .transfer: "Перенос и имена"
        case .marks: "Оценки"
        case .smart: "Умный отбор"
        case .view: "Просмотр"
        case .appearance: "Оформление"
        }
    }

    var symbol: String {
        switch self {
        case .features: "slider.horizontal.3"
        case .transfer: "folder"
        case .marks: "star"
        case .smart: "sparkles"
        case .view: "eye"
        case .appearance: "paintpalette"
        }
    }
}

/// Окно настроек: слева страницы, справа содержимое
struct SettingsShell: View {
    let session: PhotoSession

    @Environment(\.theme) private var theme
    @State private var page: SettingsPage = .features
    @AppStorage(Feature.transfer.key) private var transferOn = true
    @AppStorage(Feature.stars.key) private var starsOn = false
    @AppStorage(Feature.colors.key) private var colorsOn = false
    @AppStorage(Feature.flags.key) private var flagsOn = false
    @AppStorage(Pref.smartAnalysis) private var smartAnalysis = true

    var body: some View {
        let c = theme.c
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(SettingsPage.allCases) { item in
                    sidebarRow(item)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 12)
            .frame(width: 200)
            .frame(maxHeight: .infinity)
            .background(theme.isLight ? c.surface3 : c.surface1)

            ScrollView {
                content
                    .padding(.horizontal, 28)
                    .padding(.top, 24)
                    .padding(.bottom, 28)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.automatic)
        }
        .frame(width: 760, height: 560)
        .background(c.app)
        .navigationTitle(page.title)
    }

    @ViewBuilder
    private var content: some View {
        switch page {
        case .features: FeaturesPage { page = $0 }
        case .transfer: TransferPage(session: session)
        case .marks: MarksPage(session: session)
        case .smart: SmartPage()
        case .view: ViewPage()
        case .appearance: AppearancePage()
        }
    }

    /// Выключенная функция — «выкл» справа от названия страницы
    private func isOff(_ item: SettingsPage) -> Bool {
        switch item {
        case .transfer: !transferOn
        case .marks: !(starsOn || colorsOn || flagsOn)
        case .smart: !smartAnalysis
        case .features, .view, .appearance: false
        }
    }

    private func sidebarRow(_ item: SettingsPage) -> some View {
        let c = theme.c
        let isOn = page == item
        let lightTable = theme.isTable && theme.isLight
        return Button {
            page = item
        } label: {
            HStack(spacing: 10) {
                Image(systemName: item.symbol)
                    .font(.system(size: 13))
                    .frame(width: 18)
                Text(item.title)
                    .font(.system(size: 13.5, weight: isOn ? .semibold : .regular))
                Spacer(minLength: 4)
                if isOff(item) {
                    Text("выкл")
                        .font(.system(size: 11.5))
                        .foregroundStyle(isOn && lightTable ? Color.white.opacity(0.7) : c.text3)
                }
            }
            .foregroundStyle(isOn ? (lightTable ? Color.white : c.text1) : c.text2)
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(isOn ? (lightTable ? c.text1 : c.surface2) : Color.clear, in: RoundedRectangle(cornerRadius: 7))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
    }
}
