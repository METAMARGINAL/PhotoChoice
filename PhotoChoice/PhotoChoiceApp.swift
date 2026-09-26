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
