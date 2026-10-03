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

/// Панель инструментов рисования: инструменты, цвета, толщины, действия
struct DrawToolbar: View {
    @Bindable var session: PhotoSession

    @Environment(\.theme) private var theme

    var body: some View {
        let c = theme.c
        switch theme.direction {
        case .studio:
            content
                .padding(4)
                .frame(maxWidth: .infinity)
                .background(c.surface1)
                .overlay(alignment: .top) {
                    Rectangle().fill(c.line).frame(height: 1)
                }
        case .glass:
            content
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .glassEffect(.regular, in: .capsule)
                .padding(.bottom, 16)
        case .quiet:
            content
                .padding(.bottom, 8)
        case .contact:
            content
                .padding(6)
                .background(c.overlay, in: RoundedRectangle(cornerRadius: 4))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(c.line, lineWidth: 1))
                .shadow(color: .black.opacity(0.6), radius: 9, y: 6)
                .padding(.bottom, 14)
        }
    }

    private var content: some View {
        HStack(spacing: 6) {
            ForEach(DrawTool.allCases, id: \.self) { tool in
                toolButton(tool)
            }

            separator

            ForEach(DrawColor.allCases, id: \.self) { color in
                colorDot(color)
            }

            separator

            ForEach(DrawSize.allCases, id: \.self) { size in
                widthButton(size)
            }

            separator

            actionButton("arrow.uturn.backward", "Отменить штрих") { session.undoDrawing() }
            actionButton("trash", "Стереть всё", danger: true) { session.clearDrawing() }
            actionButton("doc.on.doc", "Копировать", key: "⌘C") { session.copyAnnotated() }
            actionButton("square.and.arrow.down", "Сохранить копию", key: "⌘S") { session.saveAnnotated() }
            actionButton("xmark", "Выйти", key: "D", muted: true) {
                withAnimation(.easeOut(duration: 0.2)) { session.isDrawing = false }
            }
        }
        .fixedSize()
    }

    private var itemShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: theme.isGlass ? 17 : theme.rMd)
    }

    private var separator: some View {
        Rectangle()
            .fill(theme.c.line)
            .frame(width: 1, height: 22)
            .padding(.horizontal, 4)
    }

    private func shortcut(_ tool: DrawTool) -> String {
        switch tool {
        case .pen: "P"
        case .marker: "M"
        case .arrow: "A"
        case .rectangle: "R"
        case .ellipse: "O"
        case .eraser: "E"
        }
    }

    private func toolButton(_ tool: DrawTool) -> some View {
        let c = theme.c
        let isOn = session.drawTool == tool
        return Button {
            session.drawTool = tool
        } label: {
            Image(systemName: tool.symbol)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(isOn ? (theme.isQuiet ? c.text1 : c.accent) : c.text2)
                .frame(width: 34, height: 34)
                .background(isOn && !theme.isQuiet ? c.selectionFill : Color.clear, in: itemShape)
                .overlay {
                    if isOn && !theme.isQuiet {
                        itemShape.strokeBorder(c.accent, lineWidth: 1.5)
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    if !theme.isQuiet {
                        Text(shortcut(tool))
                            .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                            .foregroundStyle(isOn ? c.accent : c.text3)
                            .padding(.trailing, 3)
                            .padding(.bottom, 2)
                    }
                }
                .overlay(alignment: .bottom) {
                    if isOn && theme.isQuiet {
                        Rectangle().fill(c.text1).frame(height: 1.5).padding(.horizontal, 10)
                    }
                }
                .contentShape(itemShape)
        }
        .buttonStyle(.plain)
        .help(tool.title)
    }

    private func colorDot(_ color: DrawColor) -> some View {
        let c = theme.c
        let isOn = session.drawColor == color
        return Button {
            session.drawColor = color
            if session.drawTool == .eraser { session.drawTool = .pen }
        } label: {
            Circle()
                .fill(color.color)
                .frame(width: 20, height: 20)
                .overlay(Circle().stroke(Color.white.opacity(0.25), lineWidth: 1))
                .overlay {
                    if isOn {
                        Circle()
                            .stroke(c.text1, lineWidth: 2)
                            .padding(-4)
                    }
                }
                .padding(.horizontal, 3)
                .frame(height: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func widthButton(_ size: DrawSize) -> some View {
        let c = theme.c
        let isOn = session.drawSize == size
        let barHeight: CGFloat = switch size {
        case .small: 2
        case .medium: 4
        case .large: 7
        }
        return Button {
            session.drawSize = size
        } label: {
            RoundedRectangle(cornerRadius: 4)
                .fill(isOn ? (theme.isQuiet ? c.text1 : c.accent) : c.text2)
                .frame(width: 16, height: barHeight)
                .frame(width: 26, height: 34)
                .background(isOn && !theme.isQuiet ? c.selectionFill : Color.clear, in: itemShape)
                .contentShape(itemShape)
        }
        .buttonStyle(.plain)
        .help("Толщина")
    }

    private func actionButton(
        _ symbol: String,
        _ title: String,
        key: String? = nil,
        danger: Bool = false,
        muted: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        let c = theme.c
        return Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .foregroundStyle(danger ? c.danger : (muted || theme.isQuiet ? c.text2 : c.text1))
                Text(title)
                    .foregroundStyle(muted || theme.isQuiet ? c.text2 : c.text1)
                if let key {
                    KeyCap(key, size: .small)
                }
            }
            .font(.system(size: 12))
            .padding(.horizontal, 10)
            .frame(height: 34)
            .contentShape(itemShape)
        }
        .buttonStyle(DrawActionStyle(shape: itemShape))
    }
}

/// Наведение на действие в панели рисования
private struct DrawActionStyle: ButtonStyle {
    let shape: RoundedRectangle

    func makeBody(configuration: Configuration) -> some View {
        DrawActionBody(configuration: configuration, shape: shape)
    }
}

private struct DrawActionBody: View {
    let configuration: ButtonStyleConfiguration
    let shape: RoundedRectangle

    @Environment(\.theme) private var theme
    @State private var hovered = false

    var body: some View {
        configuration.label
            .background(
                configuration.isPressed ? theme.c.surface2 : (hovered ? theme.c.surface3 : Color.clear),
                in: shape
            )
            .onHover { hovered = $0 }
    }
}
