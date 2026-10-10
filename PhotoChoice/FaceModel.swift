import CoreGraphics
import CoreML
import Foundation
import Vision

// Раздел «Люди»: модель распознавания лиц AuraFace-v1 (fal, Apache-2.0, ResNet-100 по схеме ArcFace).
// Лицо выравнивается по пяти точкам (глаза, нос, уголки рта) в квадрат 112×112 и превращается в вектор из 512 чисел;
// у одного человека векторы близки при любом свете, одежде и ракурсе — в отличие от отпечатка Vision.
// Векторы лиц — биометрические данные: они только в кэше анализа на этом Mac.
// Модели нет в приложении — «Люди» работают на отпечатках Vision, как раньше.

nonisolated final class FaceModel: @unchecked Sendable {
    /// Пакет в PhotoChoice/Models
    static let resourceName = "auraface_v1"
    /// Пишется в метрики кадра: кадры, разобранные без модели, при её появлении анализируются заново
    static let identifier = "auraface_v1"

    static var isBundled: Bool {
        Bundle.main.url(forResource: resourceName, withExtension: "mlmodelc") != nil
    }

    static var isEnabled: Bool {
        isBundled && PhotoAnalyzer.peopleEnabled
    }

    private static let loading = NSLock()
    nonisolated(unsafe) private static var loaded: FaceModel?
    nonisolated(unsafe) private static var failed = false

    /// Загружается первым кадром анализа и выгружается после него, как `QualityModel`
    static var active: FaceModel? {
        guard isEnabled else { return nil }
        loading.lock()
        defer { loading.unlock() }
        if loaded == nil && !failed {
            loaded = FaceModel()
            failed = loaded == nil
        }
        return loaded
    }

    static var failedToLoad: Bool {
        loading.lock()
        defer { loading.unlock() }
        return failed
    }

    static func unload() {
        loading.lock()
        loaded = nil
        loading.unlock()
    }

    /// Лицо уже 64 px в исходнике модель не узнает
    static let minimumSide: CGFloat = 64
    static let side = 112

    private let model: MLModel
    private let inputName: String
    private let outputName: String
    private let lock = NSLock()

    private init?() {
        guard let url = Bundle.main.url(forResource: Self.resourceName, withExtension: "mlmodelc") else { return nil }
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .all
        guard let model = try? MLModel(contentsOf: url, configuration: configuration),
              let input = model.modelDescription.inputDescriptionsByName.values.first(where: { $0.type == .multiArray }),
              let output = model.modelDescription.outputDescriptionsByName.values.first(where: { $0.type == .multiArray })
        else { return nil }
        self.model = model
        inputName = input.name
        outputName = output.name
    }

    /// Векторы лиц одним пакетом, порядок как у `faces`; nil — лицо не выровнялось
    func embeddings(_ faces: [CGImage?]) -> [[Float]?] {
        var providers: [MLFeatureProvider] = []
        var slots: [Int] = []
        for (i, face) in faces.enumerated() {
            guard let face, let array = Self.tensor(face),
                  let provider = try? MLDictionaryFeatureProvider(dictionary: [inputName: array]) else { continue }
            providers.append(provider)
            slots.append(i)
        }
        var result = [[Float]?](repeating: nil, count: faces.count)
        guard !providers.isEmpty else { return result }
        lock.lock()
        let batch = try? model.predictions(fromBatch: MLArrayBatchProvider(array: providers))
        lock.unlock()
        guard let batch, batch.count == providers.count else { return result }
        for (k, slot) in slots.enumerated() {
            if let array = batch.features(at: k).featureValue(for: outputName)?.multiArrayValue {
                result[slot] = ClipVector.normalized(ClipVector.floats(array))
            }
        }
        return result
    }

    /// RGB 112×112 → [1, 3, 112, 112], (p − 127.5) / 127.5
    private static func tensor(_ image: CGImage) -> MLMultiArray? {
        let n = side
        var pixels = [UInt8](repeating: 0, count: n * n * 4)
        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(data: buffer.baseAddress, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n * 4,
                                          space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: n, height: n))
            return true
        }
        guard drawn, let array = try? MLMultiArray(shape: [1, 3, NSNumber(value: n), NSNumber(value: n)], dataType: .float32) else { return nil }
        array.withUnsafeMutableBufferPointer(ofType: Float.self) { values, strides in
            for y in 0..<n {
                for x in 0..<n {
                    let p = (y * n + x) * 4
                    for c in 0..<3 {
                        values[c * strides[1] + y * strides[2] + x * strides[3]] = (Float(pixels[p + c]) - 127.5) / 127.5
                    }
                }
            }
        }
        return array
    }

    // MARK: Выравнивание

    /// Где должны оказаться глаза, нос и уголки рта в квадрате 112×112 (шаблон ArcFace, сверху слева)
    private static let template: [CGPoint] = [
        CGPoint(x: 38.2946, y: 51.6963), CGPoint(x: 73.5318, y: 51.5014),
        CGPoint(x: 56.0252, y: 71.7366),
        CGPoint(x: 41.5493, y: 92.3655), CGPoint(x: 70.7299, y: 92.2041)
    ]

    /// Лицо, повёрнутое и масштабированное по шаблону. `image` — кадр в полном разрешении, развёрнутый как на экране;
    /// точки Vision нормированы к нему же (кадр анализа — его уменьшенная копия)
    static func aligned(_ image: CGImage, face: VNFaceObservation) -> CGImage? {
        let w = CGFloat(image.width), h = CGFloat(image.height)
        guard let points = landmarks(face, width: w, height: h) else { return nil }

        // Работаем с кусочком вокруг лица: рисовать весь снимок в 112 px — долго и с артефактами
        let box = face.boundingBox
        let faceSide = max(box.width * w, box.height * h)
        guard faceSide >= minimumSide else { return nil }
        let cropSide = min(faceSide * 2, w, h)
        let cx = box.midX * w, cy = (1 - box.midY) * h
        let x0 = min(max(0, cx - cropSide / 2), w - cropSide)
        let y0 = min(max(0, cy - cropSide / 2), h - cropSide)
        let cropRect = CGRect(x: x0, y: y0, width: cropSide, height: cropSide).integral
        guard let crop = image.cropping(to: cropRect) else { return nil }

        // Всё в координатах «снизу слева», как у Core Graphics
        let cropHeight = CGFloat(crop.height)
        let source = points.map { CGPoint(x: $0.x - cropRect.minX, y: cropHeight - ($0.y - cropRect.minY)) }
        let target = template.map { CGPoint(x: $0.x, y: CGFloat(side) - $0.y) }
        guard let transform = similarity(from: source, to: target) else { return nil }

        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        context.interpolationQuality = .high
        context.concatenate(transform)
        context.draw(crop, in: CGRect(x: 0, y: 0, width: crop.width, height: crop.height))
        return context.makeImage()
    }

    /// Пять точек в пикселях кадра, сверху слева: левый и правый (на снимке) глаз, кончик носа, уголки рта
    private static func landmarks(_ face: VNFaceObservation, width: CGFloat, height: CGFloat) -> [CGPoint]? {
        guard let marks = face.landmarks else { return nil }
        let size = CGSize(width: width, height: height)
        // Vision отдаёт точки снизу слева
        func points(_ region: VNFaceLandmarkRegion2D?) -> [CGPoint] {
            (region?.pointsInImage(imageSize: size) ?? []).map { CGPoint(x: $0.x, y: height - $0.y) }
        }
        func center(_ list: [CGPoint]) -> CGPoint? {
            guard !list.isEmpty else { return nil }
            return CGPoint(x: list.map(\.x).reduce(0, +) / CGFloat(list.count),
                           y: list.map(\.y).reduce(0, +) / CGFloat(list.count))
        }
        let eyeA = center(points(marks.leftPupil)) ?? center(points(marks.leftEye))
        let eyeB = center(points(marks.rightPupil)) ?? center(points(marks.rightEye))
        // Кончик носа — нижняя точка спинки носа
        let nose = points(marks.noseCrest).max { $0.y < $1.y } ?? center(points(marks.nose))
        let lips = points(marks.outerLips)
        guard let eyeA, let eyeB, let nose,
              let mouthLeft = lips.min(by: { $0.x < $1.x }), let mouthRight = lips.max(by: { $0.x < $1.x }) else { return nil }
        let eyes = [eyeA, eyeB].sorted { $0.x < $1.x }
        return [eyes[0], eyes[1], nose, mouthLeft, mouthRight]
    }

    /// Поворот + масштаб + сдвиг, лучше всего переводящие `source` в `target` (наименьшие квадраты)
    private static func similarity(from source: [CGPoint], to target: [CGPoint]) -> CGAffineTransform? {
        let n = CGFloat(source.count)
        let sx = source.map(\.x).reduce(0, +) / n, sy = source.map(\.y).reduce(0, +) / n
        let tx = target.map(\.x).reduce(0, +) / n, ty = target.map(\.y).reduce(0, +) / n
        var norm: CGFloat = 0, a: CGFloat = 0, b: CGFloat = 0
        for (p, q) in zip(source, target) {
            let px = p.x - sx, py = p.y - sy, qx = q.x - tx, qy = q.y - ty
            norm += px * px + py * py
            a += px * qx + py * qy
            b += px * qy - py * qx
        }
        guard norm > 0 else { return nil }
        a /= norm
        b /= norm
        return CGAffineTransform(a: a, b: b, c: -b, d: a, tx: tx - (a * sx - b * sy), ty: ty - (b * sx + a * sy))
    }
}
