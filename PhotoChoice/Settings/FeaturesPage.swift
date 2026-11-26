import SwiftUI

/// «Функции»: что вообще включено. Режим только расставляет галочки
struct FeaturesPage: View {
    let open: (SettingsPage) -> Void

    @AppStorage(Feature.transfer.key) private var transferOn = true
    @AppStorage(Feature.stars.key) private var starsOn = false
    @AppStorage(Feature.colors.key) private var colorsOn = false
    @AppStorage(Feature.flags.key) private var flagsOn = false
    @AppStorage(Feature.compare.key) private var compareOn = true
    @AppStorage(Feature.drawing.key) private var drawingOn = true
    @AppStorage(Feature.adjust.key) private var adjustOn = true
    @AppStorage(Feature.info.key) private var infoOn = true
    @AppStorage(Pref.smartAnalysis) private var smartAnalysis = true

    private var mode: WorkMode {
        WorkMode.current(transfer: transferOn, stars: starsOn, colors: colorsOn, flags: flagsOn)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsHeader(
                title: "Функции",
                subtitle: "Включайте только то, чем пользуетесь. Выключенное не видно нигде: ни в клавишах, ни в подсказках, ни в меню."
            )
            PCSegmented(
                items: WorkMode.allCases.enumerated().map { PCSegmentItem(id: $0.offset, title: $0.element.title, help: modeHelp($0.element)) },
                selected: WorkMode.allCases.firstIndex(of: mode) ?? 3
            ) { id in
                let picked = WorkMode.allCases[id]
                guard let preset = picked.preset else { return }
                transferOn = preset.transfer
                starsOn = preset.marks
                colorsOn = preset.marks
                flagsOn = preset.marks
            }
            .padding(.top, 16)

            SettingsGroup("Отбор") {
                row(.transfer, $transferOn, page: .transfer)
                row(.stars, $starsOn, page: .marks)
                row(.colors, $colorsOn, page: .marks)
                row(.flags, $flagsOn, page: .marks, isNew: true)
            }

            SettingsGroup("Работа с кадром") {
                ToggleRow("Умный отбор", detail: "Брак, серии и люди ищутся в фоне, на этом Mac", isOn: $smartAnalysis) {
                    KeyChips(keys: ["⌘2–4"])
                    goButton(.smart)
                }
                row(.compare, $compareOn, page: nil)
                row(.drawing, $drawingOn, page: nil)
                row(.adjust, $adjustOn, page: nil, isNew: true)
                row(.info, $infoOn, page: .view)
            }
        }
    }

    private func modeHelp(_ mode: WorkMode) -> String {
        switch mode {
        case .folders: "Смотрите кадр и отправляете в папку или в корзину"
        case .marks: "Кадры не двигаются: ставите звёзды, цвета и флаги, потом фильтруете сетку"
        case .everything: "И перенос по папкам, и оценки"
        case .custom: "Галочки ниже расставлены по-своему"
        }
    }

    private func row(_ feature: Feature, _ isOn: Binding<Bool>, page: SettingsPage?, isNew: Bool = false) -> some View {
        ToggleRow(feature.title, detail: feature.detail, isNew: isNew, isOn: isOn) {
            KeyChips(keys: feature.keys)
            goButton(page)
        }
    }

    /// «›» — к странице с настройками функции
    @ViewBuilder
    private func goButton(_ page: SettingsPage?) -> some View {
        if let page {
            Button {
                open(page)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 20, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Настроить: \(page.title)")
        } else {
            Color.clear.frame(width: 20, height: 28)
        }
    }
}
