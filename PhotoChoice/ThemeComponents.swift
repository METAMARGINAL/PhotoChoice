import SwiftUI

// Общие элементы дизайн-системы: клавиша, строка подсказок, кнопки,
// чекбокс, подтверждение действия. Каждый рисуется по текущей теме.

// MARK: - Клавиша

struct KeyCap: View {
    enum Size { case small, regular, large }

    @Environment(\.theme) private var theme
    @Environment(\.keyOnAccent) private var onAccent
    @Environment(\.keyOnTray) private var onTray

    let text: String
    var size: Size = .regular
    /// Клавиша папки: у «Плёнки» — янтарная цифра, как номер на краю плёнки
    var target = false

    init(_ text: String, size: Size = .regular, target: Bool = false) {
        self.text = text
        self.size = size
        self.target = target
    }

    private var height: CGFloat {
        switch size {
        case .small: 18
        case .regular: theme.isNeutral ? 20 : 22
        case .large: theme.isGlass ? 32 : 26
        }
    }

    private var radius: CGFloat {
        theme.isGlass ? height / 2 : 5
    }

    private var keyBackground: Color {
        if onAccent { return Color.black.opacity(0.14) }
        if onTray { return Color.white.opacity(0.18) }
        return theme.c.keyFill
    }

    private var foreground: Color {
        if onAccent { return theme.c.onAccent }
        if onTray { return .white }
        if target && theme.isFilm { return theme.c.edge }
        return theme.c.keyText
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius)
        let raised = !onAccent && !onTray && !theme.isGlass
        Text(text)
            .font(size == .large ? .system(size: 13, weight: .semibold) : theme.keyFont)
            .foregroundStyle(foreground)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, size == .small ? 4 : 6)
            .frame(minWidth: height, minHeight: height, maxHeight: height)
            .background(keyBackground, in: shape)
            .overlay {
                // Как у настоящей клавиши: светлый блик сверху, у светлой темы — тень снизу
                if raised {
                    shape.strokeBorder(
                        LinearGradient(
                            colors: theme.isLight
                                ? [Color.clear, Color.black.opacity(0.12)]
                                : [Color.white.opacity(0.09), Color.clear],
                            startPoint: .top, endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
                }
            }
            .shadow(color: raised && theme.isFilm ? Color.black : Color.clear, radius: 0, y: 1)
    }
}

// MARK: - Строка подсказок

struct Hint {
    let keys: [String]
    let label: String
    /// Куда уходит кадр (папка или корзина): подпись — название папки, крупнее остальных
    var isTarget = false

    init(_ keys: String..., label: String, target: Bool = false) {
        self.keys = keys
        self.label = label
        self.isTarget = target
    }
}

struct HintGroup {
    let title: String
    let hints: [Hint]
}

extension HintGroup {
    /// «1 Отобранные · 2 Портфолио · ⌫ Корзина»: клавиши подписаны папками
    static func targets(_ session: PhotoSession) -> HintGroup {
        var hints: [Hint] = []
        if Feature.transfer.isOn {
            let folders = session.destinations
            for destination in folders.prefix(4) {
                hints.append(Hint(destination.shortcut, label: destination.name, target: true))
            }
            if folders.count > 4 {
                hints.append(Hint("5–\(folders.count)", label: "ещё \(folders.count - 4)", target: true))
            }
        }
        hints.append(Hint("⌫", label: "Корзина", target: true))
        return HintGroup(title: "Отбор", hints: hints)
    }
}

/// Подсказки клавиш, сгруппированные по смыслу, в одну строку
struct HintBar: View {
    @Environment(\.theme) private var theme

    let groups: [HintGroup]

    var body: some View {
        let c = theme.c
        switch theme.direction {
        case .film:
            content
                .padding(.horizontal, 28)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: theme.hintbarHeight)
                .clipped()
        case .neutral:
            content
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: theme.hintbarHeight)
                .clipped()
                .background(Color(hex: 0x222222))
        case .table:
            content
                .padding(.horizontal, 24)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: theme.hintbarHeight)
                .clipped()
                .background(theme.trayFill)
                .environment(\.keyOnTray, true)
        case .glass:
            content
                .padding(.horizontal, 9)
                .frame(height: theme.hintbarHeight)
                .pcGlass(in: .capsule)
                .padding(.bottom, 16)
                .foregroundStyle(c.text1)
        }
    }

    private var groupSpacing: CGFloat {
        switch theme.direction {
        case .film: 24
        case .glass: 6
        case .neutral: 18
        case .table: 20
        }
    }

    private var content: some View {
        HStack(spacing: groupSpacing) {
            ForEach(Array(groups.enumerated()), id: \.offset) { item in
                if item.offset > 0 {
                    separator
                }
                HStack(spacing: theme.isGlass ? 6 : groupSpacing) {
                    ForEach(Array(item.element.hints.enumerated()), id: \.offset) { hint in
                        hintView(hint.element)
                    }
                }
            }
        }
        .lineLimit(1)
        .fixedSize()
    }

    @ViewBuilder
    private var separator: some View {
        switch theme.direction {
        case .film:
            Rectangle().fill(theme.c.line).frame(width: 1, height: 18)
        case .glass:
            Rectangle().fill(Color.white.opacity(0.2)).frame(width: 1, height: 22).padding(.horizontal, 4)
        case .neutral:
            EmptyView()
        case .table:
            Rectangle().fill(Color.white.opacity(0.2)).frame(width: 1, height: 18)
        }
    }

    @ViewBuilder
    private func hintView(_ hint: Hint) -> some View {
        let keys = HStack(spacing: 3) {
            ForEach(hint.keys, id: \.self) { key in
                KeyCap(key, target: hint.isTarget)
            }
        }
        if theme.isGlass && hint.isTarget {
            // Папка — вложенная капсула с клавишей-кружком
            HStack(spacing: 8) {
                keys
                Text(hint.label)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.c.text1)
            }
            .padding(.leading, 5)
            .padding(.trailing, 14)
            .frame(height: 36)
            .background(Color.white.opacity(theme.isLight ? 0.5 : 0.1), in: Capsule())
        } else {
            HStack(spacing: theme.isNeutral ? 6 : 8) {
                keys
                Text(hint.label)
                    .font(.system(size: labelSize, weight: hint.isTarget ? .medium : .regular))
                    .foregroundStyle(labelColor(hint))
            }
            .padding(.horizontal, theme.isGlass ? 6 : 0)
        }
    }

    private var labelSize: CGFloat {
        theme.isNeutral ? 12 : (theme.isGlass ? 13 : 12.5)
    }

    private func labelColor(_ hint: Hint) -> Color {
        if theme.isTable { return hint.isTarget ? .white : Color(hex: 0xB9BBC1) }
        return hint.isTarget && !theme.isNeutral ? theme.c.text1 : theme.c.text2
    }
}

// MARK: - Кнопки

enum PCButtonKind {
    case primary, secondary, ghost
}

/// Кнопка в стиле темы: главная, вторичная и «призрачная»; состояния наведения, нажатия и выключения
struct PCButtonStyle: ButtonStyle {
    var kind: PCButtonKind = .secondary
    var big = false
    var isOn = false

    func makeBody(configuration: Configuration) -> some View {
        PCButtonBody(configuration: configuration, kind: kind, big: big, isOn: isOn)
    }
}

private struct PCButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let kind: PCButtonKind
    let big: Bool
    let isOn: Bool

    @Environment(\.theme) private var theme
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovered = false

    private var height: CGFloat {
        switch theme.direction {
        case .film: big ? 36 : 30
        case .glass: big ? 48 : 32
        case .neutral: big ? 34 : 28
        case .table: big ? 40 : 32
        }
    }

    var body: some View {
        let pressed = configuration.isPressed
        let shape = RoundedRectangle(cornerRadius: min(theme.rControl, height / 2))
        configuration.label
            .font(.system(size: big ? (theme.isGlass ? 16 : 14) : 13, weight: kind == .primary ? .semibold : .medium))
            .lineLimit(1)
            .foregroundStyle(foreground)
            .padding(.leading, big ? (theme.isGlass ? 24 : 16) : 12)
            .padding(.trailing, big ? 10 : 12)
            .frame(height: height)
            .background {
                if theme.isGlass && kind != .ghost && !isOn {
                    if kind == .primary {
                        shape.fill(theme.c.accentFill.opacity(0.85))
                    } else {
                        Color.clear.pcGlass(in: shape)
                    }
                } else {
                    shape.fill(background(pressed: pressed))
                }
            }
            .overlay {
                if let borderColor {
                    shape.strokeBorder(borderColor, lineWidth: 1)
                }
            }
            .shadow(color: shadowColor, radius: kind == .primary && theme.isTable ? 8 : 0.5, y: kind == .primary && theme.isTable ? 5 : 0.5)
            .brightness(kind == .primary ? (pressed ? -0.08 : (hovered ? 0.04 : 0)) : 0)
            .opacity(isEnabled ? 1 : 0.4)
            .contentShape(shape)
            .environment(\.keyOnAccent, kind == .primary)
            .onHover { hovered = $0 }
    }

    private var foreground: Color {
        let c = theme.c
        if isOn { return theme.isTable && theme.isLight ? .white : c.text1 }
        switch kind {
        case .primary: return c.onAccent
        case .secondary: return c.text1
        case .ghost: return hovered ? c.text1 : c.text2
        }
    }

    private func background(pressed: Bool) -> Color {
        let c = theme.c
        switch kind {
        case .primary:
            return c.accentFill
        case .ghost:
            return hovered ? c.surface3.opacity(theme.isLight ? 0.8 : 1) : .clear
        case .secondary:
            if isOn { return theme.isTable && theme.isLight ? c.text1 : c.surface3 }
            switch theme.direction {
            case .film, .neutral:
                return pressed ? c.surface1 : (hovered ? c.surface3 : c.surface2)
            case .table:
                if !theme.isLight { return pressed ? c.surface1 : (hovered ? c.surface3 : c.surface2) }
                return pressed ? c.surface3 : (hovered ? c.surface2 : c.surface1)
            case .glass:
                return isOn ? Color.white.opacity(0.22) : Color.white.opacity(0.1)
            }
        }
    }

    private var borderColor: Color? {
        if theme.isTable && theme.isLight && kind == .secondary && !isOn {
            return theme.c.line
        }
        return nil
    }

    private var shadowColor: Color {
        if theme.isTable && theme.isLight {
            return kind == .primary ? Color.black.opacity(0.3) : (kind == .secondary ? Color.black.opacity(0.08) : .clear)
        }
        return .clear
    }
}

/// Кнопка-значок: панели, строки папок; может быть «включена»
struct PCIconButtonStyle: ButtonStyle {
    var isOn = false
    var danger = false

    func makeBody(configuration: Configuration) -> some View {
        PCIconButtonBody(configuration: configuration, isOn: isOn, danger: danger)
    }
}

private struct PCIconButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let isOn: Bool
    let danger: Bool

    @Environment(\.theme) private var theme
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovered = false

    var body: some View {
        let c = theme.c
        let side: CGFloat = theme.isGlass ? 34 : (theme.isTable ? 32 : 28)
        let shape = RoundedRectangle(cornerRadius: min(theme.rControl, side / 2))
        let pressed = configuration.isPressed
        let lightTable = theme.isTable && theme.isLight
        configuration.label
            .font(.system(size: 14))
            .frame(width: side, height: side)
            .foregroundStyle(isOn ? (lightTable ? Color.white : c.text1) : (hovered ? (danger ? c.danger : c.text1) : c.text2))
            .background(
                isOn ? (lightTable ? c.text1 : (theme.isGlass ? Color.white.opacity(0.22) : c.surface3))
                    : (pressed ? c.surface1 : (hovered ? c.surface3.opacity(theme.isLight ? 0.8 : 1) : Color.clear)),
                in: shape
            )
            .opacity(isEnabled ? 1 : 0.35)
            .contentShape(shape)
            .onHover { hovered = $0 }
    }
}

// MARK: - Чекбокс

struct PCCheckbox: View {
    @Environment(\.theme) private var theme

    @Binding var isOn: Bool
    let title: String
    var detail: String?

    var body: some View {
        let c = theme.c
        Button {
            isOn.toggle()
        } label: {
            HStack(spacing: 8) {
                PCCheckMark(isOn: isOn)
                Text(title)
                    .font(theme.bodyFont)
                    .foregroundStyle(c.text1)
                if let detail {
                    Text(detail)
                        .font(theme.bodyFont)
                        .foregroundStyle(c.text3)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Квадратик чекбокса: пустой — с обводкой, включённый — залит
struct PCCheckMark: View {
    @Environment(\.theme) private var theme
    let isOn: Bool

    var body: some View {
        let c = theme.c
        let shape = RoundedRectangle(cornerRadius: theme.isGlass ? 5 : 4)
        ZStack {
            if isOn {
                shape.fill(c.accentFill)
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(c.onAccent)
            } else {
                shape.strokeBorder(c.lineStrong, lineWidth: 1.5)
            }
        }
        .frame(width: 16, height: 16)
    }
}

// MARK: - Красный карандаш «Плёнки»

/// Обводка от руки вокруг кадра, как карандашом по контрольному листу. Координаты — из макета 200 × 150
nonisolated struct PencilLoop: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 200, sy = rect.height / 150
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * sx, y: rect.minY + y * sy) }
        var path = Path()
        path.move(to: p(26, 12))
        path.addCurve(to: p(178, 10), control1: p(62, 4), control2: p(132, 4))
        path.addCurve(to: p(196, 56), control1: p(193, 12), control2: p(197, 26))
        path.addCurve(to: p(187, 136), control1: p(197, 92), control2: p(195, 120))
        path.addCurve(to: p(148, 146), control1: p(182, 146), control2: p(170, 147))
        path.addCurve(to: p(28, 144), control1: p(100, 149), control2: p(60, 148))
        path.addCurve(to: p(6, 108), control1: p(12, 142), control2: p(7, 133))
        path.addCurve(to: p(10, 26), control1: p(5, 76), control2: p(6, 44))
        path.addCurve(to: p(44, 7), control1: p(12, 15), control2: p(22, 10))
        path.addCurve(to: p(112, 6), control1: p(70, 4), control2: p(92, 4))
        return path
    }
}

/// Кружок карандашом вокруг клавиши в подтверждении. Координаты — из макета 34 × 34
nonisolated struct PencilCircle: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 34, sy = rect.height / 34
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * sx, y: rect.minY + y * sy) }
        var path = Path()
        path.move(to: p(17, 3))
        path.addCurve(to: p(31, 18), control1: p(26, 2), control2: p(32, 9))
        path.addCurve(to: p(14, 31), control1: p(30, 27), control2: p(22, 32))
        path.addCurve(to: p(3, 14), control1: p(6, 30), control2: p(2, 22))
        path.addCurve(to: p(19, 4), control1: p(4, 7), control2: p(10, 3))
        return path
    }
}

// MARK: - Подтверждение действия

struct ToastView: View {
    @Environment(\.theme) private var theme

    let toast: Toast

    var body: some View {
        switch theme.direction {
        case .film: film
        case .glass: glass
        case .neutral: neutral
        case .table: table
        }
    }

    private var symbol: String {
        switch toast.kind {
        case .move: "folder.fill"
        case .trash: "trash.fill"
        case .undo: "arrow.uturn.backward"
        case .done: "checkmark"
        case .error: "exclamationmark"
        case .info: "info"
        }
    }

    /// «→» перед названием папки или корзины
    private var arrow: String? {
        toast.kind == .move || toast.kind == .trash ? "→" : nil
    }

    private func line(_ arrowColor: Color, _ textColor: Color) -> some View {
        HStack(spacing: 8) {
            if let arrow {
                Text(arrow).foregroundStyle(arrowColor).fontWeight(.medium)
            } else if toast.kind == .error {
                Image(systemName: "exclamationmark.triangle").foregroundStyle(theme.c.danger)
            }
            Text(toast.text).foregroundStyle(textColor)
        }
        .font(theme.toastFont)
    }

    /// «Плёнка»: тёмная плашка, клавиша обведена карандашом
    private var film: some View {
        let c = theme.c
        return HStack(spacing: 14) {
            if let key = toast.key {
                KeyCap(key, size: .large)
                    .overlay {
                        PencilCircle()
                            .stroke(theme.pen, style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
                            .frame(width: 42, height: 42)
                    }
                    .frame(width: 38, height: 38)
            }
            line(c.text3, c.text1)
        }
        .padding(.leading, 12)
        .padding(.trailing, 20)
        .padding(.vertical, 9)
        .background(c.toastFill, in: RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.55), radius: 16, y: 12)
    }

    /// «Стекло»: капсула, круглый значок на цветной заливке и слово
    private var glass: some View {
        let c = theme.c
        let fill: Color = switch toast.kind {
        case .trash, .error: c.danger
        case .done: c.success
        case .undo, .info: Color.white.opacity(0.22)
        case .move: c.accentFill
        }
        return HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.white)
                .frame(width: 40, height: 40)
                .background(fill, in: Circle())
            Text(toast.text)
                .font(theme.toastFont)
                .foregroundStyle(c.text1)
        }
        .padding(.leading, 10)
        .padding(.trailing, 26)
        .frame(height: 58)
        .pcGlass(in: .capsule)
    }

    /// «Нейтраль»: плотная плашка — клавиша, стрелка, папка
    private var neutral: some View {
        let c = theme.c
        return HStack(spacing: 12) {
            if let key = toast.key {
                KeyCap(key, size: .large)
            }
            line(c.text3, c.text1)
        }
        .padding(.leading, 10)
        .padding(.trailing, 18)
        .frame(height: 46)
        .background(c.toastFill, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.white.opacity(0.07), lineWidth: 1))
        .shadow(color: .black.opacity(0.45), radius: 14, y: 10)
    }

    /// «Световой стол»: белая бирка с тёмными чернилами — и на столе, и в тёмном просмотре
    private var table: some View {
        let ink = Color(hex: 0x1A1B1E)
        return HStack(spacing: 12) {
            if let key = toast.key {
                KeyCap(key, size: .large)
                    .environment(\.theme, Theme.make(.table, light: true))
            }
            line(Color(hex: 0x686B72), ink)
        }
        .padding(.leading, 12)
        .padding(.trailing, 22)
        .frame(height: 50)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.35), radius: 15, y: 10)
    }
}

/// Показывает подтверждение из сессии внизу экрана, над подсказками. Появляется за 120 мс, гаснет за 200 мс, без сдвига
struct ToastOverlay: View {
    @Environment(\.theme) private var theme
    let toast: Toast?

    var body: some View {
        ZStack {
            if let toast {
                ToastView(toast: toast)
                    .id(toast.id)
                    .transition(AnyTransition.asymmetric(
                        insertion: AnyTransition.opacity.animation(.easeOut(duration: 0.12)),
                        removal: AnyTransition.opacity.animation(.easeOut(duration: 0.2))
                    ))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .padding(.bottom, theme.hintbarReserve + 28)
        .allowsHitTesting(false)
    }
}

// MARK: - Сегменты

struct PCSegmentItem: Identifiable {
    let id: Int
    let title: String
    /// Число справа от названия (например, сколько кадров в разделе)
    var detail: String?
    /// Вместо числа — маленький индикатор (идёт анализ)
    var busy = false
    var help: String?
}

/// Сегментный переключатель в стиле темы: «Все фото 812 · Брак 37 · Серии 12»
struct PCSegmented: View {
    @Environment(\.theme) private var theme

    let items: [PCSegmentItem]
    let selected: Int
    let onSelect: (Int) -> Void

    var body: some View {
        let c = theme.c
        let outer = RoundedRectangle(cornerRadius: theme.isGlass ? 18 : 9)
        let inner = RoundedRectangle(cornerRadius: theme.isGlass ? 15 : 6)
        let lightTable = theme.isTable && theme.isLight
        HStack(spacing: 2) {
            ForEach(items) { item in
                let isOn = item.id == selected
                Button {
                    onSelect(item.id)
                } label: {
                    HStack(spacing: 5) {
                        Text(item.title)
                            .font(.system(size: 12.5, weight: isOn ? .semibold : .medium))
                            .foregroundStyle(isOn ? (lightTable ? Color.white : c.text1) : c.text2)
                        if item.busy {
                            ProgressView()
                                .controlSize(.mini)
                        } else if let detail = item.detail {
                            Text(detail)
                                .font(.system(size: 11.5).monospacedDigit())
                                .foregroundStyle(isOn ? (lightTable ? Color.white.opacity(0.75) : c.text2) : c.text3)
                        }
                    }
                    .padding(.horizontal, 12)
                    .frame(height: theme.isGlass ? 30 : 26)
                    .background(isOn ? segmentFill : Color.clear, in: inner)
                    .contentShape(inner)
                }
                .buttonStyle(.plain)
                .focusable(false)
                .help(item.help ?? item.title)
            }
        }
        .padding(3)
        .background {
            if !theme.isGlass {
                outer.fill(theme.isLight ? c.surface3 : c.surface1)
            }
        }
        .fixedSize()
    }

    private var segmentFill: Color {
        let c = theme.c
        switch theme.direction {
        case .glass: return Color.white.opacity(theme.isLight ? 0.7 : 0.22)
        case .table: return theme.isLight ? c.text1 : c.surface3
        case .film, .neutral: return c.surface3
        }
    }
}

// MARK: - Панели

extension View {
    /// Liquid Glass на macOS 26, на старых системах — матовая подложка
    @ViewBuilder
    func pcGlass<S: Shape>(in shape: S) -> some View {
        if #available(macOS 26, *) {
            glassEffect(.regular, in: shape)
        } else {
            background(.regularMaterial, in: shape)
        }
    }

    /// Фон плавающей панели: у «Стекла» — Liquid Glass, у остальных — плотная заливка
    @ViewBuilder
    func themedPanel(_ theme: Theme, cornerRadius: CGFloat? = nil) -> some View {
        let radius = cornerRadius ?? theme.rLg
        if theme.isGlass {
            pcGlass(in: .rect(cornerRadius: radius))
        } else {
            background(theme.c.overlay, in: RoundedRectangle(cornerRadius: radius))
                .overlay(RoundedRectangle(cornerRadius: radius).stroke(theme.c.line, lineWidth: 1))
        }
    }
}
