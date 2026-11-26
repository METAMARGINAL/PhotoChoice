import SwiftUI

/// «Оценки»: звёзды, цветовые метки и флаги, запись в XMP
struct MarksPage: View {
    let session: PhotoSession

    @Environment(\.theme) private var theme
    @AppStorage(Feature.stars.key) private var starsOn = false
    @AppStorage(Feature.colors.key) private var colorsOn = false
    @AppStorage(Feature.flags.key) private var flagsOn = false

    private var anyOn: Bool { starsOn || colorsOn || flagsOn }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsHeader(
                title: "Оценки",
                subtitle: "Звёзды, цвета и флаги хранятся в приложении и едут вместе с кадром. Снимки не меняются."
            )
            if !anyOn {
                FeatureOffBanner(text: "Оценки выключены. Данные, если они были, остаются на диске: включите — и всё на месте.") {
                    starsOn = true
                    colorsOn = true
                }
            }

            SettingsGroup("Что ставить") {
                ToggleRow(
                    "Звёзды",
                    detail: "От одной до пяти; ⌥0 снимает",
                    help: "В сетке — выделенным кадрам, без выделения — текущему. Ставятся и кликом: под миниатюрой при наведении, в просмотре и в сравнении — рядом с именем файла. Фильтр по звёздам — кнопка над сеткой: «★★» — ровно две звезды, отметьте несколько, чтобы взять диапазон.",
                    isOn: $starsOn
                ) {
                    starsDemo
                    KeyChips(keys: ["⌥0–5"])
                }
                ToggleRow(
                    "Цветовые метки",
                    detail: "Восемь цветов. В XMP уходят под именами Lightroom и Bridge",
                    help: "⌃1–⌃8 — цвет, ⌃0 снимает. Если ⌃1–⌃8 не срабатывают, они заняты переключением рабочих столов: Системные настройки → Клавиатура → Сочетания клавиш → Mission Control.",
                    isOn: $colorsOn
                ) {
                    colorsDemo
                    KeyChips(keys: ["⌃0–8"])
                }
                ToggleRow(
                    "Флаги",
                    detail: "Оставить или отклонить кадр без звёзд",
                    help: "⌥P — оставить, ⌥X — отклонить, ⌥U — снять флаг. Отклонённый кадр в сетке приглушён. В фильтре: «Оставлено», «Отклонено», «Без флага». В XMP «отклонить» пишется как xmp:Rating = −1 (так отмечают Bridge и Lightroom) — вместо звёзд в самом файле XMP; у «оставить» стандартного поля нет.",
                    isNew: true,
                    isOn: $flagsOn
                ) {
                    flagsDemo
                    KeyChips(keys: ["⌥P", "⌥X", "⌥U"])
                }
            }

            SettingsGroup("Рядом с фото") {
                HStack(spacing: 12) {
                    SettingsText(
                        title: "Запись в XMP",
                        detail: "Только по команде «Записать в XMP». Пишется то, что включено выше",
                        help: "Рядом с фото появляется DSCF0001.xmp — его читают Lightroom, Bridge и Capture One. Существующий XMP не перезаписывается целиком: меняются только звёзды и цвет. Команда есть в панели фильтра над сеткой и в меню по правому клику."
                    )
                    Button("Записать…") {
                        session.exportMarks()
                    }
                    .buttonStyle(PCButtonStyle())
                    .disabled(!session.isViewing || !anyOn)
                    .help(session.isViewing ? "Записать оценки всех кадров открытой папки" : "Откройте папку в просмотре")
                }
                .settingsRow()
                .settingsDimmed(!anyOn)
            }
        }
    }

    private var starsDemo: some View {
        HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { n in
                Image(systemName: n <= 3 ? "star.fill" : "star")
                    .font(.system(size: 12))
                    .foregroundStyle(n <= 3 ? theme.c.text1 : theme.c.text3)
            }
        }
        .opacity(starsOn ? 1 : 0.45)
    }

    private var colorsDemo: some View {
        HStack(spacing: 3) {
            ForEach(ColorClass.allCases) { color in
                Circle().fill(color.color).frame(width: 10, height: 10)
            }
        }
        .opacity(colorsOn ? 1 : 0.45)
    }

    private var flagsDemo: some View {
        HStack(spacing: 6) {
            Image(systemName: PhotoFlag.pick.symbol)
            Image(systemName: PhotoFlag.reject.symbol)
                .foregroundStyle(theme.c.danger)
        }
        .font(.system(size: 12))
        .foregroundStyle(theme.c.text1)
        .opacity(flagsOn ? 1 : 0.45)
    }
}
