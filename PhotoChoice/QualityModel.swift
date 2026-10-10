import Accelerate
import CoreGraphics
import CoreML
import Foundation

// Умный отбор, часть 3 (docs/SmartCulling-ML.md): модель MobileCLIP-S2 (Apple), только кодировщик картинок.
// Кадр и вырезки (лица, фрагмент в 100 %) превращаются в векторы из 512 чисел. Вероятности «размыто»,
// «глаза закрыты» и т. п. — близость вектора к описаниям-подсказкам (prompts.json).
// Векторы лежат в кэше анализа: подсказки и пороги меняются без повторного анализа.
// Модели нет в приложении — анализ работает как раньше, без неё.

nonisolated final class QualityModel: @unchecked Sendable {
    /// Пакет в PhotoChoice/Models; Xcode компилирует его в .mlmodelc
    static let resourceName = "mobileclip_s2_image"
    /// Пишется в метрики кадра: по нему кэш видит, что кадр уже прогнан через эту модель
    static let identifier = "mobileclip_s2"

    static var isBundled: Bool {
        Bundle.main.url(forResource: resourceName, withExtension: "mlmodelc") != nil
    }

    /// Настройка «Модель MobileCLIP», по умолчанию вкл.
    static var isEnabled: Bool {
        isBundled && (UserDefaults.standard.object(forKey: "qualityModelEnabled") as? Bool ?? true)
    }

    private static let loading = NSLock()
    nonisolated(unsafe) private static var loaded: QualityModel?
    nonisolated(unsafe) private static var failed = false

    /// Загружается первым кадром анализа (первый раз — несколько секунд) и выгружается после него;
    /// nil — модели нет или она не загрузилась
    static var active: QualityModel? {
        guard isEnabled else { return nil }
        loading.lock()
        defer { loading.unlock() }
        if loaded == nil && !failed {
            loaded = QualityModel()
            failed = loaded == nil
        }
        return loaded
    }

    /// Модель есть, но не загрузилась: кадры анализируются без неё
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

    private let model: MLModel
    private let inputName: String
    private let outputName: String
    private let constraint: MLImageConstraint
    /// Прогоны по одному: потоков анализа несколько, а модель одна
    private let lock = NSLock()

    private init?() {
        guard let url = Bundle.main.url(forResource: Self.resourceName, withExtension: "mlmodelc") else { return nil }
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .all
        guard let model = try? MLModel(contentsOf: url, configuration: configuration),
              let input = model.modelDescription.inputDescriptionsByName.values.first(where: { $0.type == .image }),
              let constraint = input.imageConstraint,
              let output = model.modelDescription.outputDescriptionsByName.values.first(where: { $0.type == .multiArray })
        else { return nil }
        self.model = model
        inputName = input.name
        outputName = output.name
        self.constraint = constraint
    }

    /// Векторы картинок одним пакетом, порядок как у `images`. Картинка обрезается до квадрата по центру
    func embeddings(_ images: [CGImage]) -> [[Float]?] {
        var providers: [MLFeatureProvider] = []
        var slots: [Int] = []
        for (i, image) in images.enumerated() {
            guard let square = Self.centerSquare(image),
                  let value = try? MLFeatureValue(cgImage: square, constraint: constraint, options: nil),
                  let provider = try? MLDictionaryFeatureProvider(dictionary: [inputName: value]) else { continue }
            providers.append(provider)
            slots.append(i)
        }
        var result = [[Float]?](repeating: nil, count: images.count)
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

    private static func centerSquare(_ image: CGImage) -> CGImage? {
        let side = min(image.width, image.height)
        guard side >= 16 else { return nil }
        if image.width == image.height { return image }
        return image.cropping(to: CGRect(x: (image.width - side) / 2, y: (image.height - side) / 2, width: side, height: side))
    }
}

// MARK: - Векторы

/// Нормировка и хранение в кэше половинной точностью: 512 чисел → 1 КБ
nonisolated enum ClipVector {
    static func floats(_ array: MLMultiArray) -> [Float] {
        let count = array.count
        if array.dataType == .float32 {
            return array.withUnsafeBufferPointer(ofType: Float.self) { Array($0.prefix(count)) }
        }
        return (0..<count).map { array[$0].floatValue }
    }

    static func normalized(_ vector: [Float]) -> [Float]? {
        guard !vector.isEmpty else { return nil }
        let norm = vDSP.sumOfSquares(vector).squareRoot()
        guard norm > 0, norm.isFinite else { return nil }
        return vDSP.divide(vector, norm)
    }

    static func pack(_ vector: [Float]) -> Data {
        var source = vector
        var half = [UInt16](repeating: 0, count: vector.count)
        source.withUnsafeMutableBufferPointer { src in
            half.withUnsafeMutableBufferPointer { dst in
                var a = vImage_Buffer(data: src.baseAddress, height: 1, width: vImagePixelCount(src.count), rowBytes: src.count * 4)
                var b = vImage_Buffer(data: dst.baseAddress, height: 1, width: vImagePixelCount(dst.count), rowBytes: dst.count * 2)
                _ = vImageConvert_PlanarFtoPlanar16F(&a, &b, vImage_Flags(kvImageNoFlags))
            }
        }
        return half.withUnsafeBytes { Data($0) }
    }

    static func unpack(_ data: Data?) -> [Float]? {
        guard let data, data.count >= 32, data.count % 2 == 0 else { return nil }
        let count = data.count / 2
        var half = [UInt16](repeating: 0, count: count)
        _ = half.withUnsafeMutableBytes { data.copyBytes(to: $0) }
        var result = [Float](repeating: 0, count: count)
        half.withUnsafeMutableBufferPointer { src in
            result.withUnsafeMutableBufferPointer { dst in
                var a = vImage_Buffer(data: src.baseAddress, height: 1, width: vImagePixelCount(count), rowBytes: count * 2)
                var b = vImage_Buffer(data: dst.baseAddress, height: 1, width: vImagePixelCount(count), rowBytes: count * 4)
                _ = vImageConvert_Planar16FtoPlanarF(&a, &b, vImage_Flags(kvImageNoFlags))
            }
        }
        return result
    }

    /// Между нормированными векторами: 0 — одинаковые, 2 — противоположные
    static func distance(_ a: [Float], _ b: [Float]) -> Double? {
        guard a.count == b.count, !a.isEmpty else { return nil }
        return Double(max(0, 2 - 2 * vDSP.dot(a, b))).squareRoot()
    }
}

// MARK: - Подсказки

/// Пары описаний «брак» / «норма» и их векторы. Вероятность брака — softmax близостей, как в CLIP-IQA.
/// Векторы считает текстовая часть модели один раз (кнопка в калибровке); в приложение она не входит (≈130 МБ)
nonisolated struct PromptBank: Sendable {
    nonisolated enum Kind: String, CaseIterable, Sendable {
        /// Вырезка лица в 100 %
        case faceBlur
        /// Фрагмент объекта в 100 %, когда лиц нет
        case objectBlur
        /// Весь кадр: шевелёнка
        case motion
        /// Вырезка лица: закрытые глаза
        case eyes
        /// Весь кадр: снято случайно
        case accidental
        /// Весь кадр: выбитые света
        case overexposed
    }

    /// Стартовый набор (docs/SmartCulling-ML.md §3.5). Несколько формулировок на сторону — векторы усредняются.
    /// Поменяли текст — подсказки нужно пересчитать
    static let texts: [Kind: (defect: [String], good: [String])] = [
        .faceBlur: (
            ["a blurry, out-of-focus photo of a face",
             "a face with motion blur",
             "a soft, misfocused portrait photo"],
            ["a sharp, in-focus close-up photo of a face with crisp eyelashes",
             "a crisp portrait photo, the eyes are in sharp focus",
             "a high quality sharp photo of a person's face"]
        ),
        .objectBlur: (
            ["a blurry, out-of-focus photo",
             "a soft photo without fine detail"],
            ["a sharp, in-focus photo",
             "a crisp, detailed photo with fine texture"]
        ),
        .motion: (
            ["a photo with camera shake motion blur",
             "a blurry photo taken with a shaking camera"],
            ["a sharp photo",
             "a steady, crisp photo"]
        ),
        .eyes: (
            ["a person with closed eyes, blinking",
             "a face with eyes shut mid-blink"],
            ["a person with open eyes",
             "a face with eyes wide open"]
        ),
        .accidental: (
            ["an accidental photo of the floor",
             "a dark blurry accidental shot",
             "a photo taken by accident inside a bag"],
            ["a deliberate photograph of people",
             "an intentional, well composed photo"]
        ),
        .overexposed: (
            ["an overexposed photo with blown out highlights",
             "a washed out photo, the faces are too bright"],
            ["a well exposed photo",
             "a photo with balanced exposure and natural skin tones"]
        )
    ]

    /// Температура softmax, как у CLIP
    static let logitScale: Float = 100

    nonisolated enum Source: Sendable {
        case bundle
        case user
    }

    /// prompts.json: вектор каждого описания по его тексту
    nonisolated struct File: Codable, Sendable {
        var version = 1
        var model: String
        var vectors: [String: [Float]]
    }

    private nonisolated struct Center: Sendable {
        let defect: [Float]
        let good: [Float]
    }

    let source: Source
    /// Описаний без вектора: тексты поменялись после расчёта
    let missing: Int
    private let centers: [Kind: Center]

    init(file: File, source: Source) {
        self.source = source
        var centers: [Kind: Center] = [:]
        var missing = 0
        for kind in Kind.allCases {
            guard let pair = Self.texts[kind] else { continue }
            let defect = pair.defect.compactMap { file.vectors[$0] }
            let good = pair.good.compactMap { file.vectors[$0] }
            missing += pair.defect.count + pair.good.count - defect.count - good.count
            if let d = Self.mean(defect), let g = Self.mean(good), d.count == g.count {
                centers[kind] = Center(defect: d, good: g)
            }
        }
        self.centers = centers
        self.missing = missing
    }

    var isComplete: Bool {
        missing == 0 && centers.count == Kind.allCases.count
    }

    /// Вероятность «брака» 0…1; nil — для этой пары нет векторов
    func probability(_ vector: [Float], _ kind: Kind) -> Double? {
        guard let center = centers[kind], center.defect.count == vector.count else { return nil }
        let z = Self.logitScale * (vDSP.dot(vector, center.defect) - vDSP.dot(vector, center.good))
        return 1 / (1 + exp(-Double(z)))
    }

    private static func mean(_ vectors: [[Float]]) -> [Float]? {
        guard let first = vectors.first, vectors.allSatisfy({ $0.count == first.count }) else { return nil }
        var sum = [Float](repeating: 0, count: first.count)
        for vector in vectors {
            sum = vDSP.add(sum, vector)
        }
        return ClipVector.normalized(sum)
    }

    // MARK: Файл

    /// Посчитанные на этом Mac главнее вложенных в приложение
    static var userFile: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("PhotoChoice/prompts.json")
    }

    static func load() -> PromptBank? {
        let candidates: [(URL?, Source)] = [
            (userFile, .user),
            (Bundle.main.url(forResource: "prompts", withExtension: "json"), .bundle)
        ]
        for (url, source) in candidates {
            guard let url, let data = try? Data(contentsOf: url),
                  let file = try? JSONDecoder().decode(File.self, from: data),
                  file.model == QualityModel.identifier else { continue }
            return PromptBank(file: file, source: source)
        }
        return nil
    }

    nonisolated enum PromptError: LocalizedError {
        case wrongFile(String)
        case tokenizer
        case model
        case save

        var errorDescription: String? {
            switch self {
            case .wrongFile(let name): "Выбрано «\(name)», а нужен mobileclip_s2_text.mlpackage — текстовая часть той же модели"
            case .tokenizer: "В приложении нет clip-merges.txt или он повреждён"
            case .model: "Не удалось прогнать текстовую модель"
            case .save: "Не удалось сохранить подсказки"
            }
        }
    }

    /// Текстовая часть в приложении (в сборке Debug; в Release её исключает EXCLUDED_SOURCE_FILE_NAMES)
    static var bundledTextModel: URL? {
        Bundle.main.url(forResource: "mobileclip_s2_text", withExtension: "mlmodelc")
    }

    /// Выбран сам пакет или папка, в которой он лежит
    private static func textPackage(_ url: URL) -> URL? {
        let name = url.lastPathComponent.lowercased()
        if url.pathExtension == "mlpackage" || url.pathExtension == "mlmodelc" {
            return name.contains("s2") && name.contains("text") ? url : nil
        }
        let inside = url.appendingPathComponent("mobileclip_s2_text.mlpackage")
        return FileManager.default.fileExists(atPath: inside.path) ? inside : nil
    }

    /// Векторы всех описаний текстовой частью модели (пакет выбирает пользователь) → Application Support.
    /// Первый раз Core ML компилирует пакет — до минуты
    static func compute(textModel selected: URL) async throws -> PromptBank {
        guard let package = textPackage(selected) else { throw PromptError.wrongFile(selected.lastPathComponent) }
        guard let tokenizer = CLIPTokenizer(), tokenizer.isValid else { throw PromptError.tokenizer }

        // Из приложения — уже собрана Xcode; выбранный пакет компилируем во временную папку
        var compiled: URL?
        defer { if let compiled { try? FileManager.default.removeItem(at: compiled) } }
        let model: MLModel
        if package.pathExtension == "mlmodelc" {
            model = try MLModel(contentsOf: package)
        } else {
            let url = try await MLModel.compileModel(at: package)
            compiled = url
            model = try MLModel(contentsOf: url)
        }
        guard let input = model.modelDescription.inputDescriptionsByName.values.first(where: { $0.type == .multiArray }),
              let output = model.modelDescription.outputDescriptionsByName.values.first(where: { $0.type == .multiArray }) else {
            throw PromptError.model
        }
        let shape = input.multiArrayConstraint?.shape ?? [1, NSNumber(value: CLIPTokenizer.contextLength)]
        let type = input.multiArrayConstraint?.dataType ?? .int32

        var vectors: [String: [Float]] = [:]
        let all = Set(texts.values.flatMap { $0.defect + $0.good })
        for text in all.sorted() {
            let array = try MLMultiArray(shape: shape, dataType: type)
            guard array.count == CLIPTokenizer.contextLength else { throw PromptError.model }
            for (i, token) in tokenizer.tokens(text).enumerated() {
                array[i] = NSNumber(value: token)
            }
            let features = try MLDictionaryFeatureProvider(dictionary: [input.name: array])
            guard let result = try await model.prediction(from: features).featureValue(for: output.name)?.multiArrayValue,
                  let vector = ClipVector.normalized(ClipVector.floats(result)) else { throw PromptError.model }
            vectors[text] = vector
        }

        let file = File(model: QualityModel.identifier, vectors: vectors)
        guard let url = userFile else { throw PromptError.save }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(file).write(to: url, options: .atomic)
        } catch {
            throw PromptError.save
        }
        return PromptBank(file: file, source: .user)
    }
}

// MARK: - Оценки кадра

/// Оценки модели 0…1 (больше — хуже). Считаются из векторов кэша и подсказок, без повторного анализа
nonisolated struct ModelSignals: Sendable {
    /// Не в фокусе: вырезка самого крупного лица, без лиц — фрагмент объекта в 100 %
    var blur: Double?
    /// Смаз всего кадра
    var motion: Double?
    /// Закрытые глаза по лицам; ключ — номер лица в `PhotoMetrics.faces`
    var closed: [Int: Double] = [:]
    var accidental: Double?
    var overexposed: Double?

    var closedMax: Double? { closed.values.max() }

    init(_ m: PhotoMetrics, _ bank: PromptBank) {
        var faces: [(index: Int, vector: [Float], area: Double)] = []
        for (i, face) in m.faces.enumerated() {
            if let vector = ClipVector.unpack(face.clip) {
                faces.append((i, vector, Double(face.rect.width * face.rect.height)))
            }
        }
        if let largest = faces.max(by: { $0.area < $1.area }) {
            blur = bank.probability(largest.vector, .faceBlur)
        } else if let focus = ClipVector.unpack(m.clipFocus) {
            blur = bank.probability(focus, .objectBlur)
        }
        for face in faces {
            closed[face.index] = bank.probability(face.vector, .eyes)
        }
        if let frame = ClipVector.unpack(m.clipFrame) {
            motion = bank.probability(frame, .motion)
            accidental = bank.probability(frame, .accidental)
            overexposed = bank.probability(frame, .overexposed)
        }
    }
}
