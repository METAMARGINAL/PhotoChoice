import SwiftUI

// Детали окна настроек: заголовок страницы, группа строк, строка с чекбоксом,
// кнопка «?» с длинным пояснением, плашка выключенной функции.

/// Заголовок страницы и одна строка о ней
struct SettingsHeader: View {
    @Environment(\.theme) private var theme
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 20, weight: .semibold))
                .tracking(-0.4)
                .foregroundStyle(theme.c.text1)
            Text(subtitle)
                .font(.system(size: 13))
                .foregroundStyle(theme.c.text2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 520, alignment: .leading)
        }
    }
}

/// Подпись группы и строки под ней
struct SettingsGroup<Content: View>: View {
    @Environment(\.theme) private var theme
    let title: String
    let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(theme.c.text3)
            VStack(alignment: .leading, spacing: 2) {
                content
            }
        }
        .padding(.top, 20)
    }
}

/// Плашка строки: фон группы, скругление, отступы
struct SettingsRowBackground: ViewModifier {
    @Environment(\.theme) private var theme

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .background(theme.c.surface1, in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                if theme.isLight {
                    RoundedRectangle(cornerRadius: 8).strokeBorder(theme.c.line, lineWidth: 1)
                }
            }
    }
}

extension View {
    func settingsRow() -> some View {
        modifier(SettingsRowBackground())
    }
}

/// Название, однострочное пояснение и, по желанию, «?» с подробностями
struct SettingsText: View {
    @Environment(\.theme) private var theme
    let title: String
    var detail: String?
    var helpText: String?
    var isNew = false

    init(title: String, detail: String? = nil, help: String? = nil, isNew: Bool = false) {
        self.title = title
        self.detail = detail
        self.helpText = help
        self.isNew = isNew
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(theme.c.text1)
                if isNew {
                    NewBadge()
                }
                if let helpText {
                    HelpButton(text: helpText)
                }
            }
            if let detail {
                Text(detail)
                    .font(.system(size: 12.5))
                    .foregroundStyle(theme.c.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Строка с чекбоксом: клик по всей строке переключает
struct ToggleRow<Trailing: View>: View {
    let title: String
    var detail: String?
    var helpText: String?
    var isNew = false
    @Binding var isOn: Bool
    let trailing: Trailing

    init(_ title: String, detail: String? = nil, help: String? = nil, isNew: Bool = false,
         isOn: Binding<Bool>, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.detail = detail
        self.helpText = help
        self.isNew = isNew
        self._isOn = isOn
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 12) {
            Button {
                isOn.toggle()
            } label: {
                PCCheckMark(isOn: isOn)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            SettingsText(title: title, detail: detail, help: helpText, isNew: isNew)
                .contentShape(Rectangle())
                .onTapGesture { isOn.toggle() }
            trailing
        }
        .settingsRow()
    }
}

extension ToggleRow where Trailing == EmptyView {
    init(_ title: String, detail: String? = nil, help: String? = nil, isNew: Bool = false, isOn: Binding<Bool>) {
        self.init(title, detail: detail, help: help, isNew: isNew, isOn: isOn) { EmptyView() }
    }
}

/// Клавиши справа в строке функции
struct KeyChips: View {
    let keys: [String]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(keys, id: \.self) { key in
                KeyCap(key)
            }
        }
        .frame(minWidth: 104, alignment: .trailing)
    }
}

/// «новое»
struct NewBadge: View {
    @Environment(\.theme) private var theme

    var body: some View {
        Text("новое")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(theme.c.onAccent)
            .padding(.horizontal, 6)
            .frame(height: 18)
            .background(theme.c.accentFill, in: RoundedRectangle(cornerRadius: 4))
    }
}

/// «?»: длинное пояснение во всплывающем окне, чтобы страница оставалась короткой
struct HelpButton: View {
    @Environment(\.theme) private var theme
    let text: String
    @State private var shown = false

    var body: some View {
        Button {
            shown.toggle()
        } label: {
            Text("?")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(theme.c.text3)
                .frame(width: 18, height: 18)
                .overlay(Circle().strokeBorder(theme.c.lineStrong, lineWidth: 1.5))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help("Подробнее")
        .popover(isPresented: $shown, arrowEdge: .bottom) {
            Text(text)
                .font(.system(size: 12.5))
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 340, alignment: .leading)
                .padding(14)
        }
    }
}

/// Страница выключенной функции: плашка с кнопкой «Включить», поля ниже серые
struct FeatureOffBanner: View {
    @Environment(\.theme) private var theme
    let text: String
    let enable: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "power")
                .foregroundStyle(theme.c.text3)
            Text(text)
                .font(.system(size: 12.5))
                .foregroundStyle(theme.c.text2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button("Включить", action: enable)
                .buttonStyle(PCButtonStyle(kind: .primary))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(theme.c.surface2, in: RoundedRectangle(cornerRadius: 8))
        .padding(.top, 16)
    }
}

extension View {
    /// Поля выключенной функции: видны, но недоступны
    func settingsDimmed(_ dimmed: Bool) -> some View {
        disabled(dimmed).opacity(dimmed ? 0.45 : 1)
    }
}

/// Вариант с кружком: шаблон имени, строгость и т. п.
struct RadioRow: View {
    @Environment(\.theme) private var theme
    let title: String
    var example: String?
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 10) {
                ZStack {
                    Circle().strokeBorder(isOn ? theme.c.accentFill : theme.c.lineStrong, lineWidth: isOn ? 5 : 1.5)
                }
                .frame(width: 16, height: 16)
                .padding(.top, 1)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13))
                        .foregroundStyle(theme.c.text1)
                    if let example {
                        Text(example)
                            .font(.system(size: 11.5, design: .monospaced))
                            .foregroundStyle(theme.c.text3)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 6)
            .padding(.leading, 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Подпись и сегменты в одной строке группы
struct PickerRow<Value: Hashable>: View {
    @Environment(\.theme) private var theme
    let title: String
    var detail: String?
    var helpText: String?
    let options: [(title: String, value: Value)]
    @Binding var selection: Value

    init(title: String, detail: String? = nil, help: String? = nil,
         options: [(title: String, value: Value)], selection: Binding<Value>) {
        self.title = title
        self.detail = detail
        self.helpText = help
        self.options = options
        self._selection = selection
    }

    var body: some View {
        HStack(spacing: 12) {
            SettingsText(title: title, detail: detail, help: helpText)
            PCSegmented(
                items: options.enumerated().map { PCSegmentItem(id: $0.offset, title: $0.element.title) },
                selected: options.firstIndex(where: { $0.value == selection }) ?? -1
            ) { id in
                selection = options[id].value
            }
        }
        .settingsRow()
    }
}
