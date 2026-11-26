import SwiftUI

/// «Умный отбор»: анализ в фоне, брак, серии, люди, модель
struct SmartPage: View {
    @Environment(\.theme) private var theme
    @AppStorage(Pref.smartAnalysis) private var smartAnalysis = true
    @AppStorage(Pref.defectAutoZoom) private var defectAutoZoom = false
    @AppStorage(Pref.seriesGap) private var seriesGap: Double = 3
    @AppStorage(Pref.peopleEnabled) private var peopleEnabled = true
    @AppStorage("peopleDistance") private var peopleDistance: Double = PeopleGrouping.defaultDistance
    @AppStorage(Pref.qualityModelEnabled) private var qualityModelEnabled = true
    @Bindable private var analysisStore = AnalysisStore.shared
    @State private var cacheSize: Int64 = 0

    private var peopleNote: String {
        let common = "Лица, которые встречаются хотя бы на двух кадрах, собираются в «людей». «Строго» — больше людей и меньше путаницы, «Свободно» — меньше дробления. Описания лиц хранятся только в кэше анализа на этом Mac."
        guard FaceModel.isBundled else {
            return common + " Модель распознавания лиц не добавлена (AuraFace, см. README): сейчас лица сравниваются по общему описанию картинки и людей часто путают."
        }
        return common + " Лица сравнивает модель распознавания AuraFace. Кадры, разобранные без неё, при следующем открытии папки проанализируются заново."
    }

    private var qualityModelNote: String {
        guard QualityModel.isBundled else {
            return "Модель не добавлена в приложение (≈70 МБ, скачивается отдельно — см. README). Без неё брак ищется по метрикам."
        }
        let prompts = analysisStore.prompts == nil
            ? "Подсказки не посчитаны: «Калибровка брака» → «Модель MobileCLIP»."
            : "Подсказки посчитаны."
        return "Нейросеть оценивает резкость лиц, закрытые глаза, смаз и случайные кадры — на этом Mac, без сети. Пока оценки видны только в калибровке брака. Включение подействует при следующем открытии папки. " + prompts
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsHeader(
                title: "Умный отбор",
                subtitle: "Анализ идёт в фоне и не мешает отбору. Файлы не меняются, рядом с фото ничего не пишется."
            )
            if !smartAnalysis {
                FeatureOffBanner(text: "Умный отбор выключен: в сетке нет разделов «Брак», «Серии» и «Люди».") {
                    smartAnalysis = true
                }
            }

            SettingsGroup("Анализ") {
                ToggleRow(
                    "Анализировать фото при открытии папки",
                    detail: "Второй раз папка открывается мгновенно — результаты в кэше",
                    help: "Без анализа в сетке нет разделов «Брак», «Серии» и «Люди». Изменение применится при следующем запуске просмотра.",
                    isOn: $smartAnalysis
                )
            }

            Group {
                SettingsGroup("Брак") {
                    PickerRow(
                        title: "Строгость",
                        detail: "Меняется сразу, без повторного анализа",
                        help: "Мягко — только явный брак. Строго — больше кадров на проверку, но чаще ошибается. В «Брак» попадают: размытые кадры, закрытые глаза, пересвет, темнота (в том числе лица в тени), завал горизонта (только при «Строго»), случайные кадры.",
                        options: DefectStrictness.allCases.map { (title: $0.title, value: $0) },
                        selection: $analysisStore.strictness
                    )
                    ToggleRow(
                        "Открывать брак на проблемном месте",
                        detail: "Размытие и глаза — сразу в 100 % на глазах или объекте",
                        help: "Так проверяют фокус. Двойной клик — вписать кадр в экран.",
                        isOn: $defectAutoZoom
                    )
                }

                SettingsGroup("Серии") {
                    PickerRow(
                        title: "Интервал серии",
                        detail: "Кадры серии должны быть и похожими друг на друга",
                        help: "1 с — только серийная съёмка, 10 с — ещё и несколько дублей одной сцены. Меняется сразу.",
                        options: [(title: "1 с", value: 1.0), (title: "3 с", value: 3.0), (title: "10 с", value: 10.0)],
                        selection: $seriesGap
                    )
                    .onChange(of: seriesGap) { _, _ in
                        AnalysisStore.shared.seriesSettingsChanged()
                    }
                }

                SettingsGroup("Люди") {
                    ToggleRow("Искать людей", detail: "Раздел «Люди» в сетке", help: peopleNote, isOn: $peopleEnabled)
                    PickerRow(
                        title: "Похожесть лиц",
                        options: [(title: "Строго", value: 0.6), (title: "Обычно", value: 0.75), (title: "Свободно", value: 0.9)],
                        selection: $peopleDistance
                    )
                    .settingsDimmed(!peopleEnabled)
                    .onChange(of: peopleDistance) { _, _ in
                        AnalysisStore.shared.peopleSettingsChanged()
                    }
                }

                SettingsGroup("Модель") {
                    ToggleRow("Модель MobileCLIP", detail: "Оценки нейросети для брака", help: qualityModelNote, isOn: $qualityModelEnabled)
                        .disabled(!QualityModel.isBundled)
                    HStack(spacing: 12) {
                        SettingsText(
                            title: "Кэш анализа",
                            detail: analysisStore.lastRunSummary ?? "Только сырые метрики и векторы, на этом Mac"
                        )
                        Button("Очистить (\(ByteCountFormatter.string(fromByteCount: cacheSize, countStyle: .file)))") {
                            AnalysisStore.shared.clearCache()
                            cacheSize = AnalysisCache.size()
                        }
                        .buttonStyle(PCButtonStyle())
                        .disabled(cacheSize == 0)
                    }
                    .settingsRow()
                }
            }
            .settingsDimmed(!smartAnalysis)
        }
        .onAppear { cacheSize = AnalysisCache.size() }
    }
}
