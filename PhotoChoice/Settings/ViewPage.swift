import SwiftUI

/// «Просмотр»: порядок кадров, пары RAW + JPEG, панели и сведения
struct ViewPage: View {
    @AppStorage(Pref.sortByCaptureDate) private var sortByCaptureDate = false
    @AppStorage(Pref.pairRawJpeg) private var pairRawJpeg = true
    @AppStorage(Pref.paletteEnabled) private var paletteEnabled = true
    @AppStorage(Pref.autoHideHUD) private var autoHideHUD = false
    @AppStorage(Feature.info.key) private var infoOn = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsHeader(title: "Просмотр", subtitle: "Как показываются кадры в сетке и на весь экран.")

            SettingsGroup("Кадры") {
                ToggleRow(
                    "Порядок по времени съёмки",
                    detail: "По EXIF, а не по имени файла; так же копируются и перетаскиваются",
                    help: "Снимки с разных камер встают в порядке съёмки. Если даты в EXIF нет — по дате изменения файла. Часы камер должны совпадать. Меняется сразу.",
                    isOn: $sortByCaptureDate
                )
                ToggleRow(
                    "Пары RAW + JPEG как один кадр",
                    detail: "Переносятся, удаляются и возвращаются вместе",
                    help: "Файлы с одинаковым именем в одной папке (DSC_0452.NEF и DSC_0452.JPG) показываются одной карточкой. Изменение применится при следующем запуске просмотра.",
                    isOn: $pairRawJpeg
                )
            }

            SettingsGroup("Интерфейс") {
                ToggleRow(
                    "Прятать панели в просмотре",
                    detail: "Через 2 секунды покоя; движение мыши возвращает",
                    help: "Клавиша H прячет и возвращает панели вручную в любой теме, и с этой настройкой, и без неё.",
                    isOn: $autoHideHUD
                ) {
                    KeyChips(keys: ["H"])
                }
                ToggleRow(
                    "Палитра в панели сведений",
                    detail: "Около десяти главных цветов кадра; клик копирует HEX",
                    isOn: $paletteEnabled
                )
                .settingsDimmed(!infoOn)
            }
        }
    }
}
