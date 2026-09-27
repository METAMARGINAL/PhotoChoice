import AppKit
import Foundation
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Модель
// Пометки живут только в памяти приложения и никогда не пишутся в исходный файл.
// Координаты нормированы (0…1 от размера картинки), поэтому пометки не зависят от зума и экрана
// и при экспорте ложатся на полноразмерное изображение.

nonisolated enum DrawTool: String, CaseIterable, Sendable {
    case pen, marker, arrow, rectangle, ellipse, eraser

    var title: String {
        switch self {
        case .pen: "Карандаш (P)"
        case .marker: "Маркер (M)"
        case .arrow: "Стрелка (A)"
        case .rectangle: "Рамка (R)"
        case .ellipse: "Овал (O)"
        case .eraser: "Ластик (E)"
        }
    }

    var symbol: String {
        switch self {
        case .pen: "pencil.tip"
        case .marker: "highlighter"
        case .arrow: "arrow.up.right"
        case .rectangle: "rectangle"
        case .ellipse: "circle"
        case .eraser: "eraser"
        }
    }

    /// Фигура строится по двум точкам — начало и конец перетаскивания
    var isShape: Bool {
        self == .arrow || self == .rectangle || self == .ellipse
    }
}

nonisolated enum DrawColor: String, CaseIterable, Sendable {
    case red, yellow, green, blue, white, black

    var rgb: (r: CGFloat, g: CGFloat, b: CGFloat) {
        switch self {
        case .red: (1.0, 0.23, 0.19)
        case .yellow: (1.0, 0.84, 0.04)
        case .green: (0.2, 0.84, 0.29)
        case .blue: (0.04, 0.52, 1.0)
        case .white: (1, 1, 1)
        case .black: (0.05, 0.05, 0.05)
        }
    }

    var color: Color {
        Color(.sRGB, red: rgb.r, green: rgb.g, blue: rgb.b)
    }

    func cgColor(alpha: CGFloat) -> CGColor {
        CGColor(srgbRed: rgb.r, green: rgb.g, blue: rgb.b, alpha: alpha)
    }
}

nonisolated enum DrawSize: CaseIterable, Sendable {
    case small, medium, large

    /// Толщина на экране в точках при текущем зуме
    var points: CGFloat {
        switch self {
        case .small: 2.5
        case .medium: 5
        case .large: 10
        }
    }
}

nonisolated struct Stroke: Identifiable, Sendable {
    let id = UUID()
    var tool: DrawTool
    var color: DrawColor
    /// Толщина в долях от короткой стороны картинки
    var width: CGFloat
    /// Точки в долях от размера картинки (0…1)
    var points: [CGPoint]
}

// MARK: - Отрисовка (общая для экрана и экспорта)

enum StrokeRenderer {
    nonisolated static func lineWidth(_ stroke: Stroke, _ size: CGSize) -> CGFloat {
        let base = stroke.width * min(size.width, size.height)
        return stroke.tool == .marker ? base * 3.5 : base
    }

    nonisolated static func opacity(_ stroke: Stroke) -> CGFloat {
        stroke.tool == .marker ? 0.4 : 1
    }

    nonisolated static func path(_ stroke: Stroke, _ size: CGSize) -> Path {
        let points = stroke.points.map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) }
        var path = Path()
        guard let first = points.first, let last = points.last else { return path }

        switch stroke.tool {
        case .pen, .marker, .eraser:
            path.move(to: first)
            if points.count == 1 {
                path.addLine(to: first) // точка от одиночного клика
            } else {
                // Сглаживаем линию квадратичными кривыми через середины отрезков
                for i in 1..<points.count {
                    let previous = points[i - 1]
                    let mid = CGPoint(x: (previous.x + points[i].x) / 2, y: (previous.y + points[i].y) / 2)
                    path.addQuadCurve(to: mid, control: previous)
                }
                path.addLine(to: last)
            }
        case .rectangle:
            path.addRect(rect(first, last))
        case .ellipse:
            path.addEllipse(in: rect(first, last))
        case .arrow:
            path.move(to: first)
            path.addLine(to: last)
            let angle = atan2(last.y - first.y, last.x - first.x)
            let head = lineWidth(stroke, size) * 4 + min(size.width, size.height) * 0.012
            let spread = CGFloat.pi / 7
            path.move(to: CGPoint(x: last.x - head * cos(angle - spread), y: last.y - head * sin(angle - spread)))
            path.addLine(to: last)
            path.addLine(to: CGPoint(x: last.x - head * cos(angle + spread), y: last.y - head * sin(angle + spread)))
        }
        return path
    }

    /// На экране (SwiftUI Canvas)
    nonisolated static func draw(_ stroke: Stroke, in context: inout GraphicsContext, size: CGSize) {
        context.stroke(
            path(stroke, size),
            with: .color(stroke.color.color.opacity(opacity(stroke))),
            style: StrokeStyle(lineWidth: lineWidth(stroke, size), lineCap: .round, lineJoin: .round)
        )
    }

    /// При экспорте (Core Graphics, начало координат сверху слева)
    nonisolated static func draw(_ stroke: Stroke, in context: CGContext, size: CGSize) {
        context.saveGState()
        context.addPath(path(stroke, size).cgPath)
        context.setStrokeColor(stroke.color.cgColor(alpha: opacity(stroke)))
        context.setLineWidth(lineWidth(stroke, size))
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.strokePath()
        context.restoreGState()
    }

    private nonisolated static func rect(_ a: CGPoint, _ b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }
}

// MARK: - Экспорт копии с пометками

nonisolated struct RenderedImage: @unchecked Sendable {
    let image: CGImage
}

enum AnnotationExporter {
    /// Рисует пометки поверх снимка. `maxPixelSize == nil` — в полном разрешении
    nonisolated static func render(_ url: URL, strokes: [Stroke], maxPixelSize: Int? = nil) -> RenderedImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let width = (props?[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue ?? 0
        let height = (props?[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue ?? 0
        let fullSide = max(width, height, 1)
        let side = min(maxPixelSize ?? fullSide, fullSide)

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: side
        ]
        guard let base = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: base.width,
                height: base.height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return nil }

        let size = CGSize(width: base.width, height: base.height)
        context.interpolationQuality = .high
        context.draw(base, in: CGRect(origin: .zero, size: size))
        // Пометки заданы с началом координат сверху — переворачиваем систему
        context.translateBy(x: 0, y: size.height)
        context.scaleBy(x: 1, y: -1)
        for stroke in strokes {
            StrokeRenderer.draw(stroke, in: context, size: size)
        }
        return context.makeImage().map(RenderedImage.init)
    }

    /// Сохраняет копию: PNG, если выбрано расширение .png, иначе JPEG
    nonisolated static func write(_ url: URL, strokes: [Stroke], to target: URL) -> Bool {
        guard let rendered = render(url, strokes: strokes) else { return false }
        let isPNG = target.pathExtension.lowercased() == "png"
        let type = (isPNG ? UTType.png : UTType.jpeg).identifier as CFString
        guard let destination = CGImageDestinationCreateWithURL(target as CFURL, type, 1, nil) else { return false }
        let options: [CFString: Any] = isPNG ? [:] : [kCGImageDestinationLossyCompressionQuality: 0.92]
        CGImageDestinationAddImage(destination, rendered.image, options as CFDictionary)
        return CGImageDestinationFinalize(destination)
    }
}
