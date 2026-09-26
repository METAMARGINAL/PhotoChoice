import SwiftUI

struct SetupView: View {
    @Bindable var session: PhotoSession

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            header
            sourceCard
            destinationsCard
            if let error = session.errorMessage {
                Text(error)
                    .foregroundStyle(.red)
            }
            HStack {
                Toggle("Включая вложенные папки", isOn: $session.includeSubfolders)
                    .toggleStyle(.checkbox)
                Spacer()
                Button("Начать полноэкранный просмотр") {
                    session.startReview()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(session.sourceURL == nil)
            }
        }
        .padding(32)
        .frame(maxWidth: 720)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PhotoChoice")
                .font(.largeTitle.bold())
            Text("Выберите папку с фото, задайте куда складывать отобранные кадры, затем листайте в полный экран. Свайп вправо или клавиша 1 — в папку, свайп влево или Delete — в корзину.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var sourceCard: some View {
        GroupBox("Исходная папка") {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.sourceURL?.path ?? "Не выбрана")
                        .font(.body.monospaced())
                        .lineLimit(2)
                    if let source = session.sourceURL {
                        Text("Будут показаны jpg, heic, png, tiff и RAW")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(source.lastPathComponent)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                Spacer()
                Button("Выбрать…") {
                    session.chooseSource()
                }
            }
            .padding(.vertical, 6)
        }
    }

    private var destinationsCard: some View {
        GroupBox("Папки назначения") {
            VStack(alignment: .leading, spacing: 10) {
                if session.destinations.isEmpty {
                    Text("Если ничего не добавить, при старте создастся папка «Отобранные» внутри исходной.")
                        .foregroundStyle(.secondary)
                }
                ForEach(session.destinations) { destination in
                    HStack {
                        Text(destination.shortcut)
                            .font(.headline.monospaced())
                            .frame(width: 28, height: 28)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                        VStack(alignment: .leading) {
                            Text(destination.name)
                            Text(destination.url.path)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Button(role: .destructive) {
                            session.removeDestination(destination)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                    }
                }
                Button("Добавить папку…") {
                    session.addDestination()
                }
                Text("Клавиши 1–9 соответствуют порядку папок. Корзина — Delete или свайп влево.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 6)
        }
    }
}
