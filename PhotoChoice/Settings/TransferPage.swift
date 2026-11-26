import SwiftUI

/// «Перенос и имена»: куда кадры попадают при переносе и как они называются
struct TransferPage: View {
    let session: PhotoSession

    @Environment(\.theme) private var theme
    @AppStorage(Feature.transfer.key) private var transferOn = true
    @AppStorage(Pref.autoKeepFolder) private var autoKeepFolder = true
    @AppStorage(Pref.renameOnMove) private var renameOnMove = false
    @AppStorage("renameStyle") private var renameStyle: RenameStyle = .dateTimeOriginal
    @Bindable private var analysisStore = AnalysisStore.shared
    @State private var confirmRenameAll = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsHeader(
                title: "Перенос и имена",
                subtitle: "Куда кадры попадают при переносе и как они называются после него."
            )
            if !transferOn {
                FeatureOffBanner(text: "Перенос по папкам выключен: клавиши 1–9 ничего не делают, кадры остаются на месте.") {
                    transferOn = true
                }
            }

            Group {
                SettingsGroup("Папки назначения") {
                    ToggleRow(
                        "Папка «Отобранные» по умолчанию",
                        detail: "Если своих папок нет, клавиша 1 переносит в неё",
                        help: "Если не выбрано ни одной папки назначения, клавиша 1 переносит кадры в «Отобранные» внутри исходной папки. Сама папка появляется только при первом переносе. Выключите, если переносить не нужно: кадры можно будет удалять, копировать и сравнивать.",
                        isOn: $autoKeepFolder
                    )
                }

                SettingsGroup("Имена при переносе") {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 12) {
                            Button {
                                renameOnMove.toggle()
                            } label: {
                                PCCheckMark(isOn: renameOnMove)
                            }
                            .buttonStyle(.plain)
                            SettingsText(
                                title: "Переименовывать по дате съёмки",
                                detail: "Дата и время из EXIF, а если их нет, из даты изменения файла",
                                help: "Так кадры с разных карт и после сброса счётчика камеры не совпадают по именам и сами встают по порядку съёмки. Меняется только имя: содержимое и дата изменения файла остаются прежними. Пара RAW + JPEG получает общее имя. В исходной папке ничего не переименовывается, в корзину файлы уходят со старым именем, Z возвращает прежнее имя."
                            )
                        }
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(RenameStyle.allCases) { style in
                                RadioRow(title: style.title, example: style.example, isOn: renameStyle == style) {
                                    renameStyle = style
                                }
                            }
                        }
                        .settingsDimmed(!renameOnMove)
                    }
                    .settingsRow()
                }
            }
            .settingsDimmed(!transferOn)

            SettingsGroup("Разово") {
                renameAllRow
            }
        }
    }

    /// Все кадры открытой папки — в имена по времени съёмки, по шаблону выше
    private var renameAllRow: some View {
        let count = session.allPhotos.count
        let folder = session.sourceURL?.lastPathComponent ?? ""
        let ready = session.isViewing && count > 0 && !analysisStore.isRunning
        let detail: String = !session.isViewing ? "Откройте папку в просмотре — переименуются её кадры."
            : analysisStore.isRunning ? "Дождитесь окончания анализа."
            : "«\(folder)», \(count) \(PhotoSession.plural(count, "кадр", "кадра", "кадров")) получат имена по шаблону выше. Z вернёт прежние."
        return HStack(spacing: 12) {
            SettingsText(
                title: "Переименовать всю открытую папку",
                detail: detail,
                help: "Например, \(renameStyle.example). Пары RAW + JPEG и XMP — под общим именем, уже названные так кадры не трогаются. Отменить — Z в окне просмотра."
            )
            Button("Переименовать…") {
                confirmRenameAll = true
            }
            .buttonStyle(PCButtonStyle())
            .disabled(!ready)
        }
        .settingsRow()
        .alert("Переименовать \(count) \(PhotoSession.plural(count, "кадр", "кадра", "кадров"))?", isPresented: $confirmRenameAll) {
            Button("Переименовать") {
                session.renameAllByCaptureDate()
            }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Папка «\(folder)», шаблон: \(renameStyle.title.lowercased()). Отменить — Z в окне просмотра.")
        }
    }
}
