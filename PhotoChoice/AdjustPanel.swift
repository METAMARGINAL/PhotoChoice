import AppKit
import SwiftUI

/// Панель «Коррекция» справа в просмотре (E): ползунки света и цвета, «До / после», сброс, копия.
/// Двойной клик по названию ползунка возвращает его в ноль
struct AdjustPanel: View {
    @Bindable var session: PhotoSession
    let url: URL

    @Environment(\.theme) private var theme

    var body: some View {
        let c = theme.c
        let adjustment = session.adjustment(for: url)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                group("Свет", AdjustParam.light, adjustment)
                group("Цвет", AdjustParam.color, adjustment)

                HStack(spacing: 8) {
                    Button {
                        session.showsOriginal.toggle()
                    } label: {
                        HStack(spacing: 6) {
                            Text("До / после")
                            KeyCap("\\", size: .small)
                        }
                    }
                    .buttonStyle(PCButtonStyle(isOn: session.showsOriginal))
                    .disabled(adjustment.isIdentity)
                    .help("Показать кадр без коррекции (\\)")

                    Button("Сбросить") {
                        session.resetAdjustment()
                    }
                    .buttonStyle(PCButtonStyle(kind: .ghost))
                    .disabled(adjustment.isIdentity)
                }
                .padding(.top, 18)

                Button {
                    session.saveAdjusted()
                } label: {
                    HStack(spacing: 10) {
                        Text("Сохранить копию…")
                        KeyCap("⌘S", size: .small)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(PCButtonStyle(kind: .primary))
                .disabled(adjustment.isIdentity)
                .padding(.top, 10)

                Text("Оригинал не меняется. Копия — JPEG в полном разрешении с EXIF исходника. Коррекция держится, пока открыта папка; Z отменяет последнее движение.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(c.text3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 12)
            }
            .padding(.horizontal, theme.isGlass ? 22 : 18)
            .padding(.vertical, theme.isGlass ? 22 : 16)
        }
        .scrollIndicators(.visible)
        .frame(width: theme.panelWidth)
        .background { panelBackground }
    }

    private var header: some View {
        let c = theme.c
        return HStack {
            Text("Коррекция")
                .font(.system(size: theme.isTable ? 18 : 15, weight: .semibold))
                .foregroundStyle(c.text1)
            Spacer()
            HStack(spacing: 4) {
                KeyCap("E", size: .small)
                Text("готово")
                    .font(.system(size: 12))
                    .foregroundStyle(c.text2)
            }
        }
    }

    private func group(_ title: String, _ params: [AdjustParam], _ adjustment: Adjustment) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .themeLabel(theme)
            ForEach(params) { param in
                row(param, adjustment[keyPath: param.keyPath])
            }
        }
        .padding(.top, 18)
    }

    private func row(_ param: AdjustParam, _ value: Double) -> some View {
        let c = theme.c
        return VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(param.title)
                    .font(.system(size: 12.5))
                    .foregroundStyle(c.text1)
                    .onTapGesture(count: 2) { set(param, 0, step: true) }
                    .help("Двойной клик — сбросить")
                Spacer()
                Text(param.format(value))
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(value == 0 ? c.text3 : c.text1)
            }
            Slider(
                value: Binding(
                    get: { session.adjustment(for: url)[keyPath: param.keyPath] },
                    set: { set(param, $0, step: false) }
                ),
                in: param.range,
                onEditingChanged: { began in
                    if began { session.beginAdjustStep(for: url) }
                }
            )
            .controlSize(.small)
            .focusable(false)
            if let ends = param.ends {
                HStack {
                    Text(ends.0)
                    Spacer()
                    Text(ends.1)
                }
                .font(.system(size: 10.5))
                .foregroundStyle(c.text3)
            }
        }
    }

    /// Значение по шагу ползунка; `step` — отдельный шаг отмены (двойной клик)
    private func set(_ param: AdjustParam, _ value: Double, step: Bool) {
        var adjustment = session.adjustment(for: url)
        let snapped = (value / param.step).rounded() * param.step
        guard adjustment[keyPath: param.keyPath] != snapped else { return }
        if step { session.beginAdjustStep(for: url) }
        adjustment[keyPath: param.keyPath] = snapped
        session.setAdjustment(adjustment, for: url)
    }

    @ViewBuilder
    private var panelBackground: some View {
        switch theme.direction {
        case .glass:
            Color.clear.themedPanel(theme, cornerRadius: 32)
        case .film:
            Color(hex: 0x131313)
        case .neutral, .table:
            theme.c.surface1
        }
    }
}
