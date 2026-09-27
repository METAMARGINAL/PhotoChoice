import SwiftUI

@main
struct PhotoChoiceApp: App {
    @State private var session = PhotoSession()

    var body: some Scene {
        WindowGroup {
            ContentView(session: session)
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

                Button(session.showInfo ? "Скрыть сведения (I)" : "Сведения о снимке (I)") {
                    session.showInfo.toggle()
                }
                .disabled(!session.isViewing)

                Divider()

                Button(session.isDrawing ? "Закончить рисование (D)" : "Рисовать (D)") {
                    session.toggleDrawing()
                }
                .disabled(!session.isViewing || session.viewMode != .single)

                Button("Сохранить копию с пометками…") {
                    session.saveAnnotated()
                }
                .keyboardShortcut("s", modifiers: [.command])
                .disabled(!session.isViewing || session.viewMode != .single)

                Button("Копировать с пометками") {
                    session.copyAnnotated()
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(!session.isViewing || session.viewMode != .single)

                Divider()

                Button("Выйти из просмотра") {
                    session.stopReview()
                }
                .disabled(!session.isViewing)

                Divider()

                Button("В первую папку") {
                    session.moveCurrentToPrimary()
                }
                .keyboardShortcut("1", modifiers: [])
                .disabled(!session.isViewing)

                Button("В корзину") {
                    session.trashCurrent()
                }
                .keyboardShortcut(.delete, modifiers: [])
                .disabled(!session.isViewing)

                Button("Отменить перенос") {
                    session.undo()
                }
                .keyboardShortcut("z", modifiers: [.command])
                .disabled(!session.isViewing)
            }
        }
    }
}
