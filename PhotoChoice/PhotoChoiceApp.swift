import AppKit
import SwiftUI

@main
struct PhotoChoiceApp: App {
    @State private var session: PhotoSession
    @AppStorage(Feature.transfer.key) private var transferOn = true
    @AppStorage(Feature.compare.key) private var compareOn = true
    @AppStorage(Feature.drawing.key) private var drawingOn = true
    @AppStorage(Feature.adjust.key) private var adjustOn = true
    @AppStorage(Feature.info.key) private var infoOn = true

    init() {
        // Умолчания и миграция — до первого чтения настроек
        Pref.register()
        _session = State(initialValue: PhotoSession())
    }

    var body: some Scene {
        WindowGroup {
            ContentView(session: session)
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                    // Вернулись из другой программы — подхватить сохранённые там правки
                    session.reloadEditedExternally()
                }
        }
        .defaultSize(width: 980, height: 680)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Отбор") {
                Button("Начать просмотр") {
                    session.startReview()
                }
                .keyboardShortcut("r", modifiers: [.command])
                .disabled(session.sourceURL == nil || session.isViewing)

                Button(session.viewMode == .grid ? "Открыть фото (F)" : "Показать сетку (F)") {
                    session.toggleViewMode()
                }
                .disabled(!session.isViewing)

                if infoOn {
                    Button(session.showInfo ? "Скрыть сведения (I)" : "Сведения о снимке (I)") {
                        session.showInfo.toggle()
                    }
                    .disabled(!session.isViewing)
                }

                if compareOn || drawingOn || adjustOn {
                    Divider()
                }

                if compareOn {
                    Button(session.viewMode == .compare ? "Закончить сравнение (C)" : "Сравнить кадры (C)") {
                        session.toggleCompare()
                    }
                    .disabled(!session.isViewing || session.photos.count < 2)
                }

                if drawingOn {
                    Button(session.isDrawing ? "Закончить рисование (D)" : "Рисовать (D)") {
                        session.toggleDrawing()
                    }
                    .disabled(!session.isViewing || session.viewMode != .single)

                    Button("Копировать с пометками") {
                        session.copyAnnotated()
                    }
                    .keyboardShortcut("c", modifiers: [.command, .shift])
                    .disabled(!session.isViewing || session.viewMode != .single)
                }

                if adjustOn {
                    Button(session.isAdjusting ? "Закончить коррекцию (E)" : "Коррекция (E)") {
                        session.toggleAdjusting()
                    }
                    .disabled(!session.isViewing || session.viewMode != .single)
                }

                if drawingOn || adjustOn {
                    // В коррекции — копия с ней, иначе — с пометками
                    Button(session.isAdjusting ? "Сохранить копию с коррекцией…" : "Сохранить копию…") {
                        session.saveCopy()
                    }
                    .keyboardShortcut("s", modifiers: [.command])
                    .disabled(!session.isViewing || session.viewMode != .single)
                }

                Divider()

                Button("Все фото") {
                    session.showSection(.all)
                }
                .keyboardShortcut("1", modifiers: [.command])
                .disabled(!session.isViewing)

                Button("Брак") {
                    session.showSection(.defects)
                }
                .keyboardShortcut("2", modifiers: [.command])
                .disabled(!session.isViewing || !session.sectionsAvailable)

                Button("Серии") {
                    session.showSection(.series)
                }
                .keyboardShortcut("3", modifiers: [.command])
                .disabled(!session.isViewing || !session.sectionsAvailable)

                Button("Люди") {
                    session.showSection(.people)
                }
                .keyboardShortcut("4", modifiers: [.command])
                .disabled(!session.isViewing || !session.sectionsAvailable || !PhotoAnalyzer.peopleEnabled)

                Button(session.showCalibration ? "Скрыть калибровку брака" : "Калибровка брака") {
                    if session.viewMode == .single { session.toggleViewMode() }
                    session.showCalibration.toggle()
                }
                .keyboardShortcut("k", modifiers: [.command, .option])
                .disabled(!session.isViewing || !session.sectionsAvailable || session.viewMode == .compare)

                Divider()

                Button("Выйти из просмотра") {
                    session.stopReview()
                }
                .disabled(!session.isViewing)

                Divider()

                if transferOn {
                    Button("В первую папку") {
                        session.moveCurrentToPrimary()
                    }
                    .keyboardShortcut("1", modifiers: [])
                    .disabled(!session.isViewing || session.isEditingText)
                }

                Button("В корзину") {
                    session.trashCurrent()
                }
                .keyboardShortcut(.delete, modifiers: [])
                .disabled(!session.isViewing || session.isEditingText)

                Button("Отменить") {
                    session.undo()
                }
                .keyboardShortcut("z", modifiers: [.command])
                .disabled(!session.isViewing || session.isEditingText)
            }
        }

        Settings {
            SettingsRoot(session: session)
        }
    }
}
