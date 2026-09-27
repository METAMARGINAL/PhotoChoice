import SwiftUI

/// Слой пометок поверх фото. Лежит внутри тех же scaleEffect/offset, что и картинка,
/// поэтому двигается и масштабируется вместе с ней
struct AnnotationLayer: View {
    @Bindable var session: PhotoSession
    let url: URL
    let zoom: CGFloat

    /// Штрих, который рисуется прямо сейчас (в сессию попадает по отпусканию)
    @State private var current: Stroke?

    var body: some View {
        GeometryReader { geo in
            let strokes = session.strokes(for: url)
            let live = current
            Canvas { context, size in
                for stroke in strokes {
                    StrokeRenderer.draw(stroke, in: &context, size: size)
                }
                if let live {
                    StrokeRenderer.draw(live, in: &context, size: size)
                }
            }
            .contentShape(Rectangle())
            .gesture(drawGesture(size: geo.size))
            .allowsHitTesting(session.isDrawing)
        }
        .onChange(of: url) { _, _ in current = nil }
    }

    private func drawGesture(size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                guard size.width > 0, size.height > 0 else { return }
                if session.drawTool == .eraser {
                    erase(at: value.location, size: size)
                    return
                }
                let point = CGPoint(x: value.location.x / size.width, y: value.location.y / size.height)
                if current == nil {
                    // Толщина задаётся в точках экрана, храним в долях картинки
                    let width = session.drawSize.points / (min(size.width, size.height) * max(zoom, 0.01))
                    current = Stroke(
                        tool: session.drawTool,
                        color: session.drawColor,
                        width: width,
                        points: session.drawTool.isShape ? [point, point] : [point]
                    )
                } else if session.drawTool.isShape {
                    current?.points[1] = point
                } else if let last = current?.points.last {
                    // Пропускаем точки ближе ~1 пикселя экрана
                    let dx = (point.x - last.x) * size.width * zoom
                    let dy = (point.y - last.y) * size.height * zoom
                    if dx * dx + dy * dy >= 1 {
                        current?.points.append(point)
                    }
                }
            }
            .onEnded { _ in
                defer { current = nil }
                guard let stroke = current else { return }
                // Фигура из одного клика не нужна
                if stroke.tool.isShape, let a = stroke.points.first, let b = stroke.points.last,
                   abs(a.x - b.x) * size.width * zoom < 3, abs(a.y - b.y) * size.height * zoom < 3 {
                    return
                }
                session.addStroke(stroke, to: url)
            }
    }

    private func erase(at location: CGPoint, size: CGSize) {
        // Попадание считаем по обводке штриха с запасом ~8 pt на экране
        for stroke in session.strokes(for: url).reversed() {
            let hitWidth = max(StrokeRenderer.lineWidth(stroke, size), 16 / max(zoom, 0.01))
            let area = StrokeRenderer.path(stroke, size)
                .strokedPath(StrokeStyle(lineWidth: hitWidth, lineCap: .round, lineJoin: .round))
            if area.contains(location) {
                session.removeStroke(stroke.id, from: url)
                return
            }
        }
    }
}

/// Панель инструментов рисования
struct DrawToolbar: View {
    @Bindable var session: PhotoSession

    var body: some View {
        HStack(spacing: 14) {
            HStack(spacing: 4) {
                ForEach(DrawTool.allCases, id: \.self) { tool in
                    iconButton(tool.symbol, help: tool.title, selected: session.drawTool == tool) {
                        session.drawTool = tool
                    }
                }
            }

            separator

            HStack(spacing: 8) {
                ForEach(DrawColor.allCases, id: \.self) { color in
                    Button {
                        session.drawColor = color
                        if session.drawTool == .eraser { session.drawTool = .pen }
                    } label: {
                        Circle()
                            .fill(color.color)
                            .frame(width: 18, height: 18)
                            .overlay(Circle().stroke(.white.opacity(0.35), lineWidth: 1))
                            .padding(3)
                            .overlay(
                                Circle().stroke(.white, lineWidth: session.drawColor == color ? 2 : 0)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            separator

            HStack(spacing: 4) {
                ForEach(DrawSize.allCases, id: \.self) { size in
                    Button {
                        session.drawSize = size
                    } label: {
                        Circle()
                            .fill(.white)
                            .frame(width: size.points + 3, height: size.points + 3)
                            .frame(width: 28, height: 28)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(.white.opacity(session.drawSize == size ? 0.2 : 0))
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Толщина")
                }
            }

            separator

            HStack(spacing: 4) {
                iconButton("arrow.uturn.backward", help: "Отменить штрих (Z)") { session.undoDrawing() }
                iconButton("trash", help: "Стереть все пометки") { session.clearDrawing() }
                iconButton("doc.on.doc", help: "Копировать с пометками (⌘C)") { session.copyAnnotated() }
                iconButton("square.and.arrow.down", help: "Сохранить копию с пометками (⌘S)") { session.saveAnnotated() }
            }

            Button("Готово") { session.isDrawing = false }
                .buttonStyle(.plain)
                .font(.callout.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.accentColor, in: Capsule())
                .foregroundStyle(.white)
                .help("Выйти из рисования (D или Esc)")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.black.opacity(0.7), in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.12)))
        .foregroundStyle(.white)
    }

    private var separator: some View {
        Rectangle()
            .fill(.white.opacity(0.2))
            .frame(width: 1, height: 22)
    }

    private func iconButton(_ symbol: String, help: String, selected: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .frame(width: 30, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(.white.opacity(selected ? 0.22 : 0))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
