import SwiftUI

// Общие элементы дизайн-системы: клавиша, строка подсказок, кнопки,
// чекбокс, подтверждение действия. Каждый рисуется по текущей теме.

// MARK: - Клавиша

struct KeyCap: View {
    enum Size { case small, regular, large }

    @Environment(\.theme) private var theme
    @Environment(\.keyOnAccent) private var onAccent

    let text: String
    var size: Size = .regular

    init(_ text: String, size: Size = .regular) {
        self.text = text
        self.size = size
    }

    private var height: CGFloat {
        switch size {
        case .small: 18
        case .regular: theme.isGlass ? 22 : 20
        case .large: 24
        }
    }

    private var radius: CGFloat {
        switch theme.direction {
        case .studio: 3
        case .glass: size == .large ? 7 : 6
        case .quiet: 0
        case .contact: 2
        }
    }

    var body: some View {
        let c = theme.c
        if theme.isQuiet && !onAccent {
            // «Тишина»: голый символ без плашки
            Text(text)
                .font(theme.keyFont)
                .foregroundStyle(c.text1)
                .fixedSize()
        } else {
            let shape = RoundedRectangle(cornerRadius: radius)
            Text(text)
                .font(size == .large ? theme.keyFont.weight(.semibold) : theme.keyFont)
                .foregroundStyle(onAccent ? c.onAccent : c.keyText)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 5)
                .frame(minWidth: height, minHeight: height, maxHeight: height)
                .background(onAccent ? Color.black.opacity(0.14) : c.keyFill, in: shape)
                .overlay {
                    // «Студия»: плоский верх и нижний край темнее — как у настоящей клавиши
                    if theme.isStudio && !onAccent {
                        VStack {
                            Spacer()
                            Rectangle()
                                .fill(Color.black.opacity(theme.isLight ? 0.12 : 0.35))
                                .frame(height: 2)
                        }
                        .clipShape(shape)
                    }
                }
                .overlay(shape.stroke(onAccent ? Color.black.opacity(0.2) : c.keyLine, lineWidth: 1))
        }
    }
}

// MARK: - Строка подсказок

struct Hint {
    let keys: [String]
    let label: String

    init(_ keys: String..., label: String) {
        self.keys = keys
        self.label = label
    }
}

struct HintGroup {
    let title: String
    let hints: [Hint]
}

/// Подсказки клавиш, сгруппированные по смыслу, в одну строку
struct HintBar: View {
    @Environment(\.theme) private var theme

    let groups: [HintGroup]

    var body: some View {
        let c = theme.c
        switch theme.direction {
        case .studio, .contact:
            content
                .frame(maxWidth: .infinity)
                .frame(height: theme.hintbarHeight)
                .background(c.surface1)
                .overlay(alignment: .top) {
                    Rectangle().fill(c.line).frame(height: 1)
                }
        case .glass:
            content
                .padding(.horizontal, 18)
                .frame(height: theme.hintbarHeight)
                .glassEffect(.regular, in: .capsule)
                .padding(.bottom, 16)
        case .quiet:
            content
                .frame(maxWidth: .infinity)
                .frame(height: theme.hintbarHeight)
        }
    }

    private var groupSpacing: CGFloat {
        switch theme.direction {
        case .studio: 20
        case .glass: 18
        case .quiet: 18
        case .contact: 24
        }
    }

    private var content: some View {
        HStack(spacing: groupSpacing) {
            ForEach(Array(groups.enumerated()), id: \.offset) { item in
                if item.offset > 0 {
                    separator
                }
                HStack(spacing: theme.isGlass ? 14 : (theme.isQuiet ? 18 : 12)) {
                    if theme.isStudio || theme.isContact {
                        Text(item.element.title.uppercased())
                            .themeLabel(theme)
                    }
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
        case .studio, .contact:
            Rectangle().fill(theme.c.line).frame(width: 1, height: 16)
        case .glass, .quiet:
            EmptyView()
        }
    }

    private func hintView(_ hint: Hint) -> some View {
        HStack(spacing: 4) {
            HStack(spacing: theme.isQuiet ? 3 : 2) {
                ForEach(hint.keys, id: \.self) { key in
                    KeyCap(key)
                }
            }
            Text(hint.label)
                .font(.system(size: theme.isQuiet ? 11 : 12))
                .foregroundStyle(theme.isQuiet ? theme.c.text3 : theme.c.text2)
                .padding(.leading, 2)
        }
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
        theme.isGlass ? (big ? 40 : 28) : (big ? 34 : 26)
    }

    var body: some View {
        let pressed = configuration.isPressed
        let shape = RoundedRectangle(cornerRadius: min(theme.rControl, height / 2))
        configuration.label
            .font(.system(size: big ? (theme.isGlass ? 15 : 14) : 13, weight: kind == .primary ? .semibold : .medium))
            .lineLimit(1)
            .foregroundStyle(foreground)
            .padding(.horizontal, big ? (theme.isGlass ? 22 : 18) : (theme.isGlass ? 14 : 12))
            .frame(height: height)
            .background(background(pressed: pressed), in: shape)
            .overlay(shape.stroke(border, lineWidth: 1))
            .brightness(kind == .primary ? (pressed ? -0.1 : (hovered ? 0.05 : 0)) : 0)
            .opacity(isEnabled ? 1 : 0.4)
            .contentShape(shape)
            .environment(\.keyOnAccent, kind == .primary)
            .onHover { hovered = $0 }
    }

    private var foreground: Color {
        let c = theme.c
        if isOn { return c.accent }
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
            return hovered ? c.surface3 : .clear
        case .secondary:
            if isOn { return c.selectionFill }
            switch theme.direction {
            case .glass:
                if theme.isLight {
                    return Color.black.opacity(pressed ? 0.14 : (hovered ? 0.09 : 0.05))
                }
                return Color.white.opacity(pressed ? 0.06 : (hovered ? 0.18 : 0.10))
            case .quiet:
                return pressed ? c.surface2 : .clear
            case .studio, .contact:
                if pressed { return theme.isLight ? c.surface3 : c.surface1 }
                return hovered ? c.surface3 : c.surface2
            }
        }
    }

    private var border: Color {
        let c = theme.c
        if isOn { return c.accent }
        switch kind {
        case .primary: return c.accentFill
        case .ghost: return .clear
        case .secondary:
            if theme.isGlass { return c.line }
            if theme.isQuiet { return hovered ? c.text1 : c.lineStrong }
            return c.lineStrong
        }
    }
}

/// Кнопка-значок: панели, строки папок; может быть «включена» (акцент)
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
        let side: CGFloat = theme.isGlass ? 30 : 26
        let shape = RoundedRectangle(cornerRadius: min(theme.rControl, side / 2))
        let pressed = configuration.isPressed
        configuration.label
            .font(.system(size: 14))
            .frame(width: side, height: side)
            .foregroundStyle(isOn ? c.accent : (hovered ? (danger ? c.danger : c.text1) : c.text2))
            .background(
                isOn ? c.selectionFill : (pressed ? c.surface1 : (hovered ? c.surface3 : Color.clear)),
                in: shape
            )
            .overlay(shape.stroke(isOn ? c.accent : Color.clear, lineWidth: 1))
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
        let shape = RoundedRectangle(cornerRadius: theme.isGlass ? 5 : theme.rSm)
        Button {
            isOn.toggle()
        } label: {
            HStack(spacing: 8) {
                ZStack {
                    shape.fill(isOn && !theme.isQuiet ? c.accentFill : Color.clear)
                    shape.stroke(isOn ? (theme.isQuiet ? c.text1 : c.accentFill) : c.lineStrong, lineWidth: 1)
                    if isOn {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(theme.isQuiet ? c.text1 : c.onAccent)
                    }
                }
                .frame(width: 16, height: 16)
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

// MARK: - Подтверждение действия

struct ToastView: View {
    @Environment(\.theme) private var theme

    let toast: Toast

    var body: some View {
        switch theme.direction {
        case .studio: studio
        case .glass: glass
        case .quiet: quiet
        case .contact: contact
        }
    }

    private var resultColor: Color {
        let c = theme.c
        switch toast.kind {
        case .move: return c.success
        case .trash, .error: return c.danger
        case .done: return c.success
        case .undo, .info: return c.text1
        }
    }

    private var symbol: String {
        switch toast.kind {
        case .move: "folder"
        case .trash: "trash"
        case .undo: "arrow.uturn.backward"
        case .done: "checkmark"
        case .error: "exclamationmark"
        case .info: "info"
        }
    }

    /// «Студия»: плашка, слева нажатая клавиша, справа результат
    private var studio: some View {
        let c = theme.c
        return HStack(spacing: 10) {
            if let key = toast.key {
                KeyCap(key)
            }
            HStack(spacing: 5) {
                if toast.kind == .move {
                    Text("→").foregroundStyle(c.success)
                } else if toast.kind == .done {
                    Image(systemName: "checkmark").foregroundStyle(c.success)
                } else if toast.kind == .error {
                    Image(systemName: "exclamationmark.triangle").foregroundStyle(c.danger)
                }
                Text(toast.text).foregroundStyle(c.text1)
            }
            .font(theme.toastFont)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(c.toastFill, in: RoundedRectangle(cornerRadius: theme.rLg))
        .overlay(RoundedRectangle(cornerRadius: theme.rLg).stroke(c.line, lineWidth: 1))
        .shadow(color: .black.opacity(theme.isLight ? 0.2 : 0.55), radius: 12, y: 8)
    }

    /// «Стекло»: капсула, круглый значок на цветной заливке и слово
    private var glass: some View {
        let c = theme.c
        let fill: Color = switch toast.kind {
        case .trash, .error: c.danger
        case .done: c.success
        case .undo, .info: c.surface3
        case .move: c.accentFill
        }
        return HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(toast.kind == .move ? c.onAccent : (toast.kind == .undo || toast.kind == .info ? c.text1 : Color.black))
                .frame(width: 30, height: 30)
                .background(fill, in: Circle())
            Text(toast.text)
                .font(theme.toastFont)
                .foregroundStyle(c.text1)
        }
        .padding(.leading, 18)
        .padding(.trailing, 26)
        .padding(.vertical, 14)
        .glassEffect(.regular, in: .capsule)
    }

    /// «Тишина»: одно слово поверх фото, без подложки
    private var quiet: some View {
        Text(toast.text)
            .font(theme.toastFont)
            .foregroundStyle(theme.c.text1)
            .shadow(color: .black.opacity(0.75), radius: 7, y: 1)
            .shadow(color: .black.opacity(0.6), radius: 1)
    }

    /// «Контакт»: штамп — рамка цвета результата, моно прописными, поворот −3°
    private var contact: some View {
        let c = theme.c
        let color: Color = switch toast.kind {
        case .trash, .error: c.danger
        case .done: c.success
        default: c.accent
        }
        return HStack(spacing: 10) {
            if let key = toast.key {
                Text(key)
                    .font(theme.keyFont)
                    .padding(.horizontal, 5)
                    .frame(minWidth: 20, minHeight: 20)
                    .overlay(RoundedRectangle(cornerRadius: 2).stroke(color, lineWidth: 1))
            }
            Text(toast.text.uppercased())
                .font(theme.toastFont)
                .tracking(1.7)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(c.toastFill, in: RoundedRectangle(cornerRadius: 2))
        .overlay(RoundedRectangle(cornerRadius: 2).stroke(color, lineWidth: 2))
        .shadow(color: .black.opacity(0.6), radius: 9, y: 6)
        .rotationEffect(.degrees(-3))
    }
}

/// Показывает подтверждение из сессии поверх экрана
struct ToastOverlay: View {
    let toast: Toast?

    var body: some View {
        ZStack {
            if let toast {
                ToastView(toast: toast)
                    .id(toast.id)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.12), value: toast)
        .allowsHitTesting(false)
    }
}

// MARK: - Панели

extension View {
    /// Фон плавающей панели: у «Стекла» — Liquid Glass, у остальных — плотная заливка
    @ViewBuilder
    func themedPanel(_ theme: Theme, cornerRadius: CGFloat? = nil) -> some View {
        let radius = cornerRadius ?? theme.rLg
        if theme.isGlass {
            glassEffect(.regular, in: .rect(cornerRadius: radius))
        } else {
            background(theme.c.overlay, in: RoundedRectangle(cornerRadius: radius))
                .overlay(RoundedRectangle(cornerRadius: radius).stroke(theme.c.line, lineWidth: 1))
        }
    }
}
