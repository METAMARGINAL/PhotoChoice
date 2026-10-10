import Accelerate
import UniformTypeIdentifiers
import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import Observation
import Vision

// Умный отбор, этап 1 (docs/SmartCulling.md §5): анализ кадров и кэш.
// В кэш пишем только сырые метрики — вердикты «брак» и серии считаются из них на лету,
// поэтому смена строгости не требует повторного анализа. Файлы только читаются.

// MARK: - Метрики

nonisolated struct FaceMetrics: Codable, Sendable {
    /// Прямоугольник лица в долях кадра, начало сверху слева
    var rect: CGRect
    var yaw: Double?
    var roll: Double?
    /// Открытость глаза: высота / ширина контура (≈0.3 открыт, <0.15 закрыт)
    var leftEye: Double?
    var rightEye: Double?
    /// Качество лица Vision (0…1)
    var quality: Double?
    /// Средняя яркость лица 0…1 (лица в тени, контровой свет)
    var luma: Double? = nil
    /// Отпечаток Vision по вырезанному лицу (сырые Float) — для раздела «Люди».
    /// Хранится только в кэше на этом Mac; nil — лицо мелкое или поиск людей выключен
    var print: Data? = nil
    /// Вектор MobileCLIP вырезки лица из полного разрешения; nil — лицо мелкое или модели нет
    var clip: Data? = nil
    /// Вектор модели распознавания лиц (FaceModel) для «Людей»; только в кэше на этом Mac
    var identity: Data? = nil
    /// Доля почти белых пикселей внутри лица: пересвет на коже, а не в окне за спиной
    var white: Double? = nil
}

nonisolated struct PhotoMetrics: Codable, Sendable {
    var captureDate: Date?
    /// Выдержка из EXIF, секунды
    var exposureTime: Double?
    /// Размер изображения, по которому считали (px)
    var analyzedWidth: Int
    var analyzedHeight: Int
    /// Главный объект (заметная область или лица), в долях кадра, начало сверху слева
    var subjectRect: CGRect?
    /// Дисперсия лапласиана внутри объекта
    var sharpness: Double
    /// Дисперсия лапласиана по всему кадру (уменьшенному до 800 px)
    var sharpnessGlobal: Double
    /// Доля мелких деталей в объекте: лапласиан при родном масштабе / при половинном.
    /// Смаз и промах фокуса съедают самые мелкие детали — отношение падает (≈0.35 смаз, ≈0.5 резко).
    /// Не зависит от контраста сцены, поэтому работает и в папке, где брак — почти всё
    var detailRatio: Double? = nil
    /// То же по всему кадру
    var detailRatioGlobal: Double? = nil
    /// Средняя яркость главного объекта 0…1
    var subjectLuma: Double? = nil
    /// Доля почти белых пикселей (все каналы ≥ 250) — настоящий пересвет; `clipHigh` считает и насыщенные цвета
    var clipWhite: Double? = nil
    /// Резкость в 100 %: фрагмент до 512×512 в полном разрешении вокруг глаз крупного лица или центра объекта.
    /// Так фокус проверяет фотограф: лёгкий промах, невидимый в уменьшенной копии, здесь виден
    var fullSharpness: Double? = nil
    /// Доля мелких деталей того же фрагмента (лапласиан родной / половинный масштаб)
    var fullDetailRatio: Double? = nil
    var faces: [FaceMetrics]
    /// Доли кадра: выбит хотя бы один канал / почти чёрное
    var clipHigh: Double
    var clipLow: Double
    /// Средняя яркость 0…1
    var meanLuma: Double
    /// Наклон горизонта в градусах, nil — горизонт не найден
    var horizonAngle: Double?
    var aesthetics: Double?
    var isUtility: Bool?
    /// Отпечаток кадра для поиска серий: сырые Float
    var featurePrint: Data?
    var featurePrintCount: Int?
    /// Модель, которой посчитаны векторы ниже (QualityModel.identifier); nil — кадр анализировали без неё
    var clipModel: String? = nil
    /// Векторы MobileCLIP (половинная точность): весь кадр и фрагмент в 100 % у точки фокуса
    var clipFrame: Data? = nil
    var clipFocus: Data? = nil
    /// Модель распознавания лиц, которой посчитаны `FaceMetrics.identity`
    var faceModel: String? = nil
    /// Доля почти белых пикселей внутри главного объекта
    var subjectWhite: Double? = nil
}

/// Запись кэша: метрики + то, по чему проверяем, что файл не менялся
nonisolated struct AnalysisRecord: Codable, Sendable {
    var fileSize: Int
    var modified: Date
    var version: Int
    var metrics: PhotoMetrics
}

// MARK: - Анализатор

nonisolated enum PhotoAnalyzer {
    /// Поднимать при смене алгоритма — старые записи кэша перестанут подходить
    static let version = 9

    /// Размер изображения для анализа по длинной стороне. 1280 — JPEG декодируется
    /// с уменьшением в 4 раза (дёшево), а деталей для оценки резкости хватает
    static let analysisSize = 1280

    private static let queue: OperationQueue = {
        let queue = OperationQueue()
        // Половина ядер, от 2 до 3: анализ не отнимает весь процессор у листания.
        // Каждый поток декодирует снимок в полном разрешении (≈100 МБ) — больше 3 потоков дают пик за 1 ГБ
        queue.maxConcurrentOperationCount = max(2, min(3, ProcessInfo.processInfo.activeProcessorCount / 2))
        queue.qualityOfService = .utility
        queue.name = "PhotoChoice.analysis"
        return queue
    }()

    /// Ставит кадр в очередь; completion вызывается в фоне (nil — не удалось прочитать)
    static func enqueue(_ url: URL, completion: @escaping @Sendable (AnalysisRecord?) -> Void) {
        queue.addOperation {
            // Vision и ImageIO оставляют autorelease-объекты с буферами — отпускаем их после каждого кадра
            completion(autoreleasepool { analyze(url) })
        }
    }

    static func cancelAll() {
        queue.cancelAllOperations()
    }

    /// Нейросети держат сотни МБ — выгружаем, когда кадры, уже взятые в работу, досчитаны
    static func releaseModels() {
        queue.addBarrierBlock {
            QualityModel.unload()
            FaceModel.unload()
        }
    }

    /// Свойства файла для проверки кэша
    static func fileStamp(_ url: URL) -> (size: Int, modified: Date)? {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
              let size = values.fileSize,
              let modified = values.contentModificationDate else { return nil }
        return (size, modified)
    }

    // MARK: Полный анализ одного кадра

    static func analyze(_ url: URL) -> AnalysisRecord? {
        guard let stamp = fileStamp(url),
              let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let image = analysisImage(source) else { return nil }

        let width = image.width
        let height = image.height
        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
        let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]

        // Все запросы Vision — за одно декодирование
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        let saliency = VNGenerateAttentionBasedSaliencyImageRequest()
        let landmarks = VNDetectFaceLandmarksRequest()
        let horizon = VNDetectHorizonRequest()
        let aesthetics = VNCalculateImageAestheticsScoresRequest()
        let featurePrint = VNGenerateImageFeaturePrintRequest()
        // По одному: сбой одного запроса не должен обнулять остальные
        for request in [saliency, landmarks, horizon, featurePrint, aesthetics] as [VNRequest] {
            try? handler.perform([request])
        }

        // Лица и их качество
        let faceObservations = landmarks.results ?? []
        var qualities: [Double?] = Array(repeating: nil, count: faceObservations.count)
        if !faceObservations.isEmpty {
            let quality = VNDetectFaceCaptureQualityRequest()
            quality.inputFaceObservations = faceObservations
            try? handler.perform([quality])
            for (i, face) in (quality.results ?? []).enumerated() where i < qualities.count {
                qualities[i] = face.faceCaptureQuality.map { Double($0) }
            }
        }
        var faces = faceObservations.enumerated().map { item -> FaceMetrics in
            faceMetrics(item.element, quality: qualities[item.offset], width: width, height: height)
        }
        for i in faces.indices {
            let box = pixelRect(faces[i].rect, width: width, height: height)
            faces[i].luma = regionLuma(image, rect: box)
            faces[i].white = regionWhite(image, rect: box)
        }
        // Отпечатки лиц Vision для «Людей» — только если нет модели распознавания: до 6 самых крупных лиц кадра
        let faceModel = FaceModel.active
        if peopleEnabled && faceModel == nil {
            let largest = faces.indices.sorted {
                faces[$0].rect.width * faces[$0].rect.height > faces[$1].rect.width * faces[$1].rect.height
            }.prefix(6)
            for i in largest {
                faces[i].print = facePrint(image, rect: faces[i].rect)
            }
        }

        // Главный объект: крупные лица, иначе самая заметная область
        let subject = subjectRect(faces: faces, saliency: saliency.results?.first)

        // Резкость: внутри объекта при родном масштабе и по всему кадру
        let subjectPixels = subject.map { pixelRect($0, width: width, height: height) }
            ?? CGRect(x: 0, y: 0, width: width, height: height)
        let subjectDetail = subjectSharpness(image, rect: subjectPixels)
        let global = globalStats(image)
        let subjectLuma = regionLuma(image, rect: subjectPixels)
        let subjectWhite = subject == nil ? nil : regionWhite(image, rect: subjectPixels)

        // Пересвет и провалы — та же функция, что для гистограммы в панели сведений
        let small = downscaled(image, maxSide: 512)
        let clipping = small.flatMap { PhotoDetailsLoader.histogram(from: $0) }
        let clipWhite = small.flatMap { whiteShare($0) }

        // Полное разрешение декодируется один раз: резкость в 100 % у глаз самого крупного лица
        // (иначе в центре объекта) и вырезки для модели
        let fullImage = fullResolution(source)
        var full: (variance: Double, ratio: Double?, crop: CGImage)?
        if let fullImage, let focus = focusPoint(faces: faces, subject: subject) {
            full = fullResolutionDetail(fullImage, focus: focus)
        }
        if let faceModel {
            addIdentities(&faces, observations: faceObservations, model: faceModel, image: fullImage ?? image)
        }

        var horizonAngle: Double?
        if let observation = horizon.results?.first {
            horizonAngle = Double(observation.angle) * 180 / .pi
        }

        var aestheticsScore: Double?
        var isUtility: Bool?
        if let observation = aesthetics.results?.first {
            aestheticsScore = Double(observation.overallScore)
            isUtility = observation.isUtility
        }

        var printData: Data?
        var printCount: Int?
        if let observation = featurePrint.results?.first, observation.elementType == .float {
            printData = observation.data
            printCount = observation.elementCount
        }

        var metrics = PhotoMetrics(
            captureDate: captureDate(exif),
            exposureTime: (exif[kCGImagePropertyExifExposureTime] as? NSNumber)?.doubleValue,
            analyzedWidth: width,
            analyzedHeight: height,
            subjectRect: subject,
            sharpness: subjectDetail.variance,
            sharpnessGlobal: global.sharpness,
            detailRatio: subjectDetail.ratio,
            detailRatioGlobal: global.ratio,
            subjectLuma: subjectLuma,
            clipWhite: clipWhite,
            fullSharpness: full?.variance,
            fullDetailRatio: full?.ratio,
            faces: faces,
            clipHigh: clipping?.highlightsClipped ?? 0,
            clipLow: clipping?.shadowsClipped ?? 0,
            meanLuma: global.meanLuma,
            horizonAngle: horizonAngle,
            aesthetics: aestheticsScore,
            isUtility: isUtility,
            featurePrint: printData,
            featurePrintCount: printCount
        )
        if let model = QualityModel.active {
            addClipVectors(&metrics, model: model, image: image, full: fullImage, focusCrop: full?.crop)
        }
        if faceModel != nil {
            metrics.faceModel = FaceModel.identifier
        }
        metrics.subjectWhite = subjectWhite
        return AnalysisRecord(fileSize: stamp.size, modified: stamp.modified, version: version, metrics: metrics)
    }

    // MARK: Изображение для анализа

    /// 1600 px по длинной стороне. Для RAW — встроенное превью, если оно достаточно большое;
    /// у JPEG встроенная миниатюра крошечная, тогда уменьшаем сам снимок
    private static func analysisImage(_ source: CGImageSource) -> CGImage? {
        let embedded: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: analysisSize,
            kCGImageSourceShouldCacheImmediately: true
        ]
        if let image = CGImageSourceCreateThumbnailAtIndex(source, 0, embedded as CFDictionary),
           max(image.width, image.height) >= 1000 {
            return image
        }
        let full: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: analysisSize,
            kCGImageSourceShouldCacheImmediately: true
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, full as CFDictionary)
    }

    private static func downscaled(_ image: CGImage, maxSide: Int) -> CGImage? {
        let scale = min(1, Double(maxSide) / Double(max(image.width, image.height)))
        let w = max(1, Int(Double(image.width) * scale))
        let h = max(1, Int(Double(image.height) * scale))
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return context.makeImage()
    }

    // MARK: Лица

    private static func faceMetrics(_ face: VNFaceObservation, quality: Double?, width: Int, height: Int) -> FaceMetrics {
        let box = face.boundingBox
        // Vision считает от левого нижнего угла — переводим в «сверху слева»
        let rect = CGRect(x: box.minX, y: 1 - box.maxY, width: box.width, height: box.height)
        let size = CGSize(width: width, height: height)
        return FaceMetrics(
            rect: rect,
            yaw: face.yaw.map { $0.doubleValue * 180 / .pi },
            roll: face.roll.map { $0.doubleValue * 180 / .pi },
            leftEye: face.landmarks?.leftEye.flatMap { eyeOpenness($0, imageSize: size) },
            rightEye: face.landmarks?.rightEye.flatMap { eyeOpenness($0, imageSize: size) },
            quality: quality
        )
    }

    /// Высота контура глаза к его ширине, в пикселях кадра
    private static func eyeOpenness(_ region: VNFaceLandmarkRegion2D, imageSize: CGSize) -> Double? {
        let points = region.pointsInImage(imageSize: imageSize)
        guard points.count >= 4 else { return nil }
        let xs = points.map(\.x)
        let ys = points.map(\.y)
        guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max(),
              maxX - minX > 0 else { return nil }
        return Double((maxY - minY) / (maxX - minX))
    }

    /// Крупные лица (≥ 1.5 % кадра) — их объединение; иначе самая заметная область
    private static func subjectRect(faces: [FaceMetrics], saliency: VNSaliencyImageObservation?) -> CGRect? {
        let bigFaces = faces.filter { $0.rect.width * $0.rect.height >= 0.015 }
        if let first = bigFaces.first {
            return bigFaces.dropFirst().reduce(first.rect) { $0.union($1.rect) }
        }
        let objects = saliency?.salientObjects ?? []
        guard let best = objects.max(by: { $0.confidence < $1.confidence }) else { return nil }
        let box = best.boundingBox
        return CGRect(x: box.minX, y: 1 - box.maxY, width: box.width, height: box.height)
    }

    // MARK: Резкость и яркость

    /// Резкость внутри объекта при родном масштабе изображения анализа. Большой объект — берём его центр
    /// не больше 600 × 600, чтобы масштаб был одинаковым у всех кадров
    private static func subjectSharpness(_ image: CGImage, rect: CGRect) -> (variance: Double, ratio: Double?) {
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        var crop = rect.intersection(bounds).integral
        guard crop.width >= 16, crop.height >= 16 else { return (0, nil) }
        let side: CGFloat = 600
        if crop.width > side {
            crop.origin.x += (crop.width - side) / 2
            crop.size.width = side
        }
        if crop.height > side {
            crop.origin.y += (crop.height - side) / 2
            crop.size.height = side
        }
        guard let cropped = image.cropping(to: crop.integral),
              let gray = grayPixels(cropped, width: cropped.width, height: cropped.height) else { return (0, nil) }
        let variance = laplacianVariance(gray, width: cropped.width, height: cropped.height)
        return (variance, detailRatio(cropped, fullVariance: variance))
    }

    /// Лапласиан при родном масштабе / при половинном. Однотонный объект (стена, небо) — nil: судить не по чему
    private static func detailRatio(_ image: CGImage, fullVariance: Double) -> Double? {
        let w = image.width / 2
        let h = image.height / 2
        guard w >= 16, h >= 16, let half = grayPixels(image, width: w, height: h) else { return nil }
        let halfVariance = laplacianVariance(half, width: w, height: h)
        guard halfVariance >= 25 else { return nil }
        return fullVariance / halfVariance
    }

    // MARK: Лица для «Людей»

    /// Искать людей (настройка `peopleEnabled`, по умолчанию вкл.). Выключено — отпечатки лиц не считаются
    static var peopleEnabled: Bool {
        UserDefaults.standard.object(forKey: "peopleEnabled") as? Bool ?? true
    }

    /// Отпечаток лица: квадрат вокруг лица с полями 25 %, не меньше 40 px; меньше — узнать не по чему
    private static func facePrint(_ image: CGImage, rect: CGRect) -> Data? {
        let face = pixelRect(rect, width: image.width, height: image.height)
        let side = max(face.width, face.height) * 1.5
        guard max(face.width, face.height) >= 40 else { return nil }
        var crop = CGRect(x: face.midX - side / 2, y: face.midY - side / 2, width: side, height: side)
        crop = crop.intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height)).integral
        guard crop.width >= 40, crop.height >= 40, let cropped = image.cropping(to: crop) else { return nil }
        let request = VNGenerateImageFeaturePrintRequest()
        try? VNImageRequestHandler(cgImage: cropped, options: [:]).perform([request])
        guard let observation = request.results?.first, observation.elementType == .float else { return nil }
        return observation.data
    }

    // MARK: Резкость в 100 %

    /// Куда смотреть в 100 %: глаза самого крупного лица (≈40 % высоты лица от верха), иначе центр объекта.
    /// Координаты в долях кадра, начало сверху слева, в развёрнутом (как на экране) кадре
    static func focusPoint(faces: [FaceMetrics], subject: CGRect?) -> CGPoint? {
        let big = faces.filter { $0.rect.width * $0.rect.height >= 0.004 }
        if let face = big.max(by: { $0.rect.width * $0.rect.height < $1.rect.width * $1.rect.height }) {
            return CGPoint(x: face.rect.midX, y: face.rect.minY + face.rect.height * 0.4)
        }
        guard let subject else { return nil }
        return CGPoint(x: subject.midX, y: subject.midY)
    }

    private static func isRaw(_ source: CGImageSource) -> Bool {
        guard let type = CGImageSourceGetType(source) as String?, let utType = UTType(type) else { return false }
        return utType.conforms(to: .rawImage)
    }

    /// Снимок в полном разрешении, развёрнутый как на экране. Пиксели декодируются сразу — вырезки
    /// не декодируют файл заново. У RAW — встроенное полноразмерное превью (проявлять RAW слишком долго);
    /// если оно маленькое — nil
    private static func fullResolution(_ source: CGImageSource) -> CGImage? {
        let raw = isRaw(source)
        var options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true
        ]
        // Больше 16384 px IOSurface не создаётся; обычные снимки меньше 12000 и не уменьшаются
        options[kCGImageSourceThumbnailMaxPixelSize] = 12000
        if raw {
            options[kCGImageSourceCreateThumbnailFromImageIfAbsent] = true
        } else {
            options[kCGImageSourceCreateThumbnailFromImageAlways] = true
        }
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
              image.width >= 64, image.height >= 64 else { return nil }
        // Превью Fuji RAF меньше 2400 px — без порога ниже у RAW не было ни резкости в 100 %, ни вырезок для модели
        if raw, max(image.width, image.height) < 1440 { return nil }
        return image
    }

    /// Фрагмент 512×512 в полном разрешении: резкость, доля мелких деталей и сам фрагмент (для модели)
    private static func fullResolutionDetail(_ image: CGImage, focus: CGPoint) -> (variance: Double, ratio: Double?, crop: CGImage)? {
        let side = CGFloat(min(512, image.width, image.height))
        let x = min(max(0, focus.x * CGFloat(image.width) - side / 2), CGFloat(image.width) - side)
        let y = min(max(0, focus.y * CGFloat(image.height) - side / 2), CGFloat(image.height) - side)
        guard let cropped = image.cropping(to: CGRect(x: x, y: y, width: side, height: side).integral),
              let gray = grayPixels(cropped, width: cropped.width, height: cropped.height) else { return nil }
        let variance = laplacianVariance(gray, width: cropped.width, height: cropped.height)
        return (variance, detailRatio(cropped, fullVariance: variance), cropped)
    }

    // MARK: Векторы модели

    /// Кадр, фрагмент у точки фокуса и до трёх крупных лиц — одним пакетом
    private static func addClipVectors(_ metrics: inout PhotoMetrics, model: QualityModel, image: CGImage,
                                       full: CGImage?, focusCrop: CGImage?) {
        var images = [image]
        var focusSlot: Int?
        if let focusCrop {
            focusSlot = images.count
            images.append(focusCrop)
        }
        var faceSlots: [(face: Int, slot: Int)] = []
        if let full {
            for i in clipFaces(metrics.faces, fullWidth: full.width) {
                guard let crop = faceCrop(full, rect: metrics.faces[i].rect) else { continue }
                faceSlots.append((i, images.count))
                images.append(crop)
            }
        }
        let vectors = model.embeddings(images)
        metrics.clipModel = QualityModel.identifier
        metrics.clipFrame = vectors[0].map(ClipVector.pack)
        metrics.clipFocus = focusSlot.flatMap { vectors[$0] }.map(ClipVector.pack)
        for item in faceSlots {
            metrics.faces[item.face].clip = vectors[item.slot].map(ClipVector.pack)
        }
    }

    /// «Люди»: до восьми самых крупных лиц, выровненных по глазам, носу и рту, — в векторы модели распознавания
    private static func addIdentities(_ faces: inout [FaceMetrics], observations: [VNFaceObservation],
                                      model: FaceModel, image: CGImage) {
        let list = faces
        let area = { (i: Int) in list[i].rect.width * list[i].rect.height }
        let chosen = list.indices
            .filter { $0 < observations.count && list[$0].rect.width * CGFloat(image.width) >= FaceModel.minimumSide }
            .sorted { area($0) > area($1) }
            .prefix(8)
            .map { $0 }
        let vectors = model.embeddings(chosen.map { FaceModel.aligned(image, face: observations[$0]) })
        for (k, i) in chosen.enumerated() {
            faces[i].identity = vectors[k].map(ClipVector.pack)
        }
    }

    /// До трёх самых крупных лиц шире 120 px в исходнике: у мелких модель глаз не разглядит
    private static func clipFaces(_ faces: [FaceMetrics], fullWidth: Int) -> [Int] {
        let area = { (i: Int) in faces[i].rect.width * faces[i].rect.height }
        return faces.indices
            .filter { faces[$0].rect.width * CGFloat(fullWidth) >= 120 }
            .sorted { area($0) > area($1) }
            .prefix(3)
            .map { $0 }
    }

    /// Квадрат вокруг лица с полями: модель видит лицо целиком, а глаза — крупно
    private static func faceCrop(_ image: CGImage, rect: CGRect) -> CGImage? {
        let face = pixelRect(rect, width: image.width, height: image.height)
        let side = min(max(face.width, face.height) * 1.4, CGFloat(min(image.width, image.height)))
        guard side >= 64 else { return nil }
        let x = min(max(0, face.midX - side / 2), CGFloat(image.width) - side)
        let y = min(max(0, face.midY - side / 2), CGFloat(image.height) - side)
        return image.cropping(to: CGRect(x: x, y: y, width: side, height: side).integral)
    }

    /// Доля почти белых пикселей в области (по копии не больше 256 px — этого хватает)
    private static func regionWhite(_ image: CGImage, rect: CGRect) -> Double? {
        let crop = rect.intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height)).integral
        guard crop.width >= 4, crop.height >= 4, let cropped = image.cropping(to: crop) else { return nil }
        return whiteShare(downscaled(cropped, maxSide: 256) ?? cropped)
    }

    /// Доля пикселей, у которых все три канала ≥ 250
    private static func whiteShare(_ image: CGImage) -> Double? {
        let w = image.width
        let h = image.height
        guard w > 0, h > 0, let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        let ok: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                          bytesPerRow: w * 4, space: space,
                                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard ok else { return nil }
        var white = 0
        pixels.withUnsafeBufferPointer { p in
            var i = 0
            while i < p.count {
                if p[i] >= 250 && p[i + 1] >= 250 && p[i + 2] >= 250 { white += 1 }
                i += 4
            }
        }
        return Double(white) / Double(w * h)
    }

    /// Нормированный прямоугольник → пиксели изображения
    private static func pixelRect(_ rect: CGRect, width: Int, height: Int) -> CGRect {
        CGRect(x: rect.minX * CGFloat(width), y: rect.minY * CGFloat(height),
               width: rect.width * CGFloat(width), height: rect.height * CGFloat(height))
    }

    /// Средняя яркость области 0…1 (по уменьшенной копии — это быстро)
    private static func regionLuma(_ image: CGImage, rect: CGRect) -> Double? {
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let crop = rect.intersection(bounds).integral
        guard crop.width >= 4, crop.height >= 4, let cropped = image.cropping(to: crop) else { return nil }
        let scale = min(1, 96 / Double(max(cropped.width, cropped.height)))
        let w = max(1, Int(Double(cropped.width) * scale))
        let h = max(1, Int(Double(cropped.height) * scale))
        guard let gray = grayPixels(cropped, width: w, height: h) else { return nil }
        return Double(gray.reduce(0) { $0 + Int($1) }) / Double(gray.count) / 255
    }

    private static func globalStats(_ image: CGImage) -> (sharpness: Double, meanLuma: Double, ratio: Double?) {
        let scale = min(1, 800 / Double(max(image.width, image.height)))
        let w = max(3, Int(Double(image.width) * scale))
        let h = max(3, Int(Double(image.height) * scale))
        guard let gray = grayPixels(image, width: w, height: h) else { return (0, 0.5, nil) }
        let result = laplacianStats(gray, width: w, height: h)
        // Доля мелких деталей — при полном размере изображения анализа
        var ratio: Double?
        if let full = grayPixels(image, width: image.width, height: image.height) {
            ratio = detailRatio(image, fullVariance: laplacianVariance(full, width: image.width, height: image.height))
        }
        return (result.variance, result.meanLuma, ratio)
    }

    private static func grayPixels(_ image: CGImage, width: Int, height: Int) -> [UInt8]? {
        var pixels = [UInt8](repeating: 0, count: width * height)
        let ok: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return ok ? pixels : nil
    }

    /// Дисперсия лапласиана: чем больше мелкого контраста, тем резче
    private static func laplacianVariance(_ pixels: [UInt8], width: Int, height: Int) -> Double {
        laplacianStats(pixels, width: width, height: height).variance
    }

    /// Свёртка лапласианом и статистика через Accelerate — быстро даже в отладочной сборке
    private static func laplacianStats(_ pixels: [UInt8], width: Int, height: Int) -> (variance: Double, meanLuma: Double) {
        let count = width * height
        guard width > 2, height > 2, pixels.count == count else { return (0, 0.5) }
        var source = [Float](repeating: 0, count: count)
        vDSP.convertElements(of: pixels, to: &source)
        let meanLuma = Double(vDSP.mean(source)) / 255

        var result = [Float](repeating: 0, count: count)
        let kernel: [Float] = [0, 1, 0,
                               1, -4, 1,
                               0, 1, 0]
        let rowBytes = width * MemoryLayout<Float>.stride
        let status: vImage_Error = source.withUnsafeMutableBufferPointer { src in
            result.withUnsafeMutableBufferPointer { dst in
                var srcBuffer = vImage_Buffer(data: src.baseAddress, height: vImagePixelCount(height),
                                              width: vImagePixelCount(width), rowBytes: rowBytes)
                var dstBuffer = vImage_Buffer(data: dst.baseAddress, height: vImagePixelCount(height),
                                              width: vImagePixelCount(width), rowBytes: rowBytes)
                return vImageConvolve_PlanarF(&srcBuffer, &dstBuffer, nil, 0, 0, kernel, 3, 3, 0,
                                              vImage_Flags(kvImageEdgeExtend))
            }
        }
        guard status == kvImageNoError else { return (0, meanLuma) }
        let mean = vDSP.mean(result)
        let meanSquare = vDSP.meanSquare(result)
        return (Double(meanSquare - mean * mean), meanLuma)
    }

    // MARK: Дата съёмки

    private static func captureDate(_ exif: [CFString: Any]) -> Date? {
        guard let raw = exif[kCGImagePropertyExifDateTimeOriginal] as? String else { return nil }
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = .current
        parser.dateFormat = "yyyy:MM:dd HH:mm:ss"
        guard var date = parser.date(from: raw.trimmingCharacters(in: .whitespaces)) else { return nil }
        if let subsec = (exif[kCGImagePropertyExifSubsecTimeOriginal] as? String)?.trimmingCharacters(in: .whitespaces),
           !subsec.isEmpty, let fraction = Double("0." + subsec) {
            date += fraction
        }
        return date
    }
}

// MARK: - Хранилище результатов

/// Результаты анализа текущей папки. Один на приложение — его читают сетка, панель сведений и разделы
@Observable
final class AnalysisStore {
    static let shared = AnalysisStore()

    private(set) var records: [URL: AnalysisRecord] = [:]
    private(set) var done = 0
    private(set) var total = 0

    var isRunning: Bool { total > 0 && done < total }

    func metrics(for url: URL) -> PhotoMetrics? {
        records[url]?.metrics
    }

    // MARK: Брак (этап 2)

    /// Кандидаты в брак (уверенность ≥ 0.3) по всем проанализированным кадрам
    private(set) var candidates: [URL: [Defect]] = [:]
    private(set) var folderStats = FolderStats(medianSharpness: nil)

    /// Строгость из настроек; меняется — раздел «Брак» пересобирается сразу, без повторного анализа
    var strictness: DefectStrictness = DefectStrictness(
        rawValue: UserDefaults.standard.string(forKey: "defectStrictness") ?? ""
    ) ?? .normal {
        didSet {
            UserDefaults.standard.set(strictness.rawValue, forKey: "defectStrictness")
            onDefectsChanged?()
        }
    }

    /// Пороги причин (панель «Калибровка брака»); меняются — пересчёт сразу, без повторного анализа
    var tuning: DefectTuning = AnalysisStore.loadTuning() {
        didSet {
            guard tuning != oldValue else { return }
            if let data = try? JSONEncoder().encode(tuning) {
                UserDefaults.standard.set(data, forKey: "defectTuning")
            }
            reevaluate()
        }
    }

    private static func loadTuning() -> DefectTuning {
        guard let data = UserDefaults.standard.data(forKey: "defectTuning"),
              let tuning = try? JSONDecoder().decode(DefectTuning.self, from: data) else { return .standard }
        return tuning
    }

    // MARK: Разметка для калибровки

    /// Ручная разметка: true — брак, false — норма. Хранится по пути файла
    private(set) var labels: [URL: Bool] = AnalysisStore.loadLabels()

    private static func loadLabels() -> [URL: Bool] {
        let stored = UserDefaults.standard.dictionary(forKey: "defectLabels") as? [String: Bool] ?? [:]
        var result: [URL: Bool] = [:]
        for (path, value) in stored {
            result[URL(fileURLWithPath: path)] = value
        }
        return result
    }

    private func saveLabels() {
        var stored: [String: Bool] = [:]
        for (url, value) in labels {
            stored[url.path] = value
        }
        UserDefaults.standard.set(stored, forKey: "defectLabels")
    }

    func label(_ url: URL) -> Bool? {
        labels[url.standardizedFileURL] ?? labels[url]
    }

    /// nil — снять разметку
    func setLabel(_ urls: [URL], _ value: Bool?) {
        for url in urls {
            labels[url.standardizedFileURL] = value
        }
        saveLabels()
    }

    /// Сессия подписывается, чтобы обновлять раздел «Брак» по мере анализа
    @ObservationIgnored var onDefectsChanged: (() -> Void)?

    /// Пометки кадра при текущей строгости, самые уверенные первыми.
    /// Если включена обученная модель — решает она, а правила только поясняют причину
    func defects(for url: URL) -> [Defect] {
        let threshold = strictness.threshold
        if modelActive {
            guard let p = probabilities[url], p >= threshold else { return [] }
            let learned = Defect(reason: .learned, confidence: p, detail: learnedDetails[url] ?? "")
            return [learned] + (candidates[url] ?? []).filter { $0.confidence >= 0.4 }
        }
        return (candidates[url] ?? []).filter { $0.confidence >= threshold }
    }

    func isDefect(_ url: URL) -> Bool {
        let threshold = strictness.threshold
        if modelActive {
            return (probabilities[url] ?? 0) >= threshold
        }
        return candidates[url]?.contains { $0.confidence >= threshold } ?? false
    }

    // MARK: Серии

    /// Серии (≥ 2 кадров) в порядке съёмки и положение кадров среди соседей
    private(set) var series: [[URL]] = []
    private(set) var contexts: [URL: PhotoContext] = [:]
    /// Для калибровки серий: интервал до предыдущего по времени кадра и расстояние отпечатков с ним
    private(set) var neighbors: [URL: (gap: Double, distance: Double?, clip: Double?)] = [:]

    /// Интервал между кадрами серии, секунды (настройка `seriesGap`, по умолчанию 3)
    var seriesGap: Double {
        let value = UserDefaults.standard.double(forKey: "seriesGap")
        return value > 0 ? value : 3
    }

    // MARK: Модель MobileCLIP

    /// Подсказки (векторы описаний); nil — не посчитаны
    private(set) var prompts: PromptBank? = PromptBank.load()
    /// Оценки модели по кадрам. В брак входит только `blur` (второе мнение для «Размыто»), остальные — в сведениях и калибровке
    private(set) var signals: [URL: ModelSignals] = [:]
    private(set) var isComputingPrompts = false

    private func rebuildSignals() {
        guard let prompts else {
            signals = [:]
            return
        }
        var result: [URL: ModelSignals] = [:]
        for (url, record) in records where record.metrics.clipModel != nil {
            result[url] = ModelSignals(record.metrics, prompts)
        }
        signals = result
    }

    /// Итог последнего расчёта подсказок — для панели калибровки
    private(set) var promptMessage: String?
    /// Текстовая часть модели есть в приложении или уже выбиралась (место запомнено закладкой) — окно выбора не нужно
    private(set) var hasTextModel = PromptBank.bundledTextModel != nil
        || UserDefaults.standard.data(forKey: "textModelBookmark") != nil

    /// Посчитать подсказки текстовой частью модели и запомнить, где она лежит
    func computePrompts(textModel: URL) async {
        isComputingPrompts = true
        promptMessage = nil
        defer { isComputingPrompts = false }
        do {
            let bank = try await Task.detached(priority: .userInitiated) {
                try await PromptBank.compute(textModel: textModel)
            }.value
            if textModel != PromptBank.bundledTextModel, let data = FolderAccess.bookmark(for: textModel) {
                UserDefaults.standard.set(data, forKey: "textModelBookmark")
                hasTextModel = true
            }
            prompts = bank
            rebuildSignals()
            onDefectsChanged?()
            promptMessage = "Подсказки посчитаны и сохранены на этом Mac"
        } catch {
            promptMessage = error.localizedDescription
        }
    }

    /// Пересчёт: текстовая часть из приложения, иначе запомненный файл
    func recomputePrompts() async {
        guard let url = textModelURL() else {
            UserDefaults.standard.removeObject(forKey: "textModelBookmark")
            hasTextModel = false
            promptMessage = "Файл текстовой модели не найден — выберите его заново"
            return
        }
        await computePrompts(textModel: url)
    }

    /// Подсказок нет или тексты в коде поменялись, а файл модели уже выбирали — пересчитать без вопросов
    private func refreshPromptsIfNeeded() async {
        guard QualityModel.isEnabled, prompts?.isComplete != true, hasTextModel, !isComputingPrompts,
              let url = textModelURL() else { return }
        await computePrompts(textModel: url)
    }

    private func textModelURL() -> URL? {
        PromptBank.bundledTextModel
            ?? UserDefaults.standard.data(forKey: "textModelBookmark").flatMap { FolderAccess.resolveBookmark($0) }
    }

    private func rebuildSeries() {
        let items = records.map { (url: $0.key, metrics: $0.value.metrics) }
        let found = SeriesGrouping.build(items, gap: seriesGap)
        series = found
        neighbors = SeriesGrouping.previousNeighbor(items)
        contexts = SeriesGrouping.contexts(series: found, metrics: records.mapValues(\.metrics))
    }

    // MARK: Обученная модель

    /// Модель по ручной разметке (общая для всех папок)
    private(set) var model: DefectModel? = AnalysisStore.loadModel()
    /// Вероятность «брак» по модели и пояснение
    private(set) var probabilities: [URL: Double] = [:]
    private(set) var learnedDetails: [URL: String] = [:]
    private(set) var isTraining = false

    /// Решает модель, а не правила (если она обучена)
    var useModel: Bool = UserDefaults.standard.object(forKey: "defectUseModel") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(useModel, forKey: "defectUseModel")
            reevaluate()
        }
    }

    var modelActive: Bool { useModel && model != nil }

    private static func loadModel() -> DefectModel? {
        guard let data = UserDefaults.standard.data(forKey: "defectModel") else { return nil }
        return try? JSONDecoder().decode(DefectModel.self, from: data)
    }

    /// Обучить по разметке кадров папки. Возвращает текст для пользователя
    func trainModel(photos: [URL]) async -> String {
        var samples: [(x: [Double?], bad: Bool)] = []
        var population: [[Double?]] = []
        for url in photos {
            guard let m = metrics(for: url) else { continue }
            let x = DefectFeatures.vector(m, contexts[url])
            population.append(x)
            if let label = label(url) {
                samples.append((x, label))
            }
        }
        let bad = samples.filter { $0.bad }.count
        let good = samples.count - bad
        let minimum = DefectModel.minimumPerClass
        guard bad >= minimum, good >= minimum else {
            return "Нужно хотя бы по \(minimum) кадров каждого вида: сейчас брак \(bad), норма \(good)"
        }
        isTraining = true
        let labeled = samples
        let everyone = population
        let trained = await Task.detached(priority: .userInitiated) {
            DefectModel.train(samples: labeled, population: everyone)
        }.value
        isTraining = false
        guard let trained else { return "Не удалось обучить модель" }
        model = trained
        if let data = try? JSONEncoder().encode(trained) {
            UserDefaults.standard.set(data, forKey: "defectModel")
        }
        useModel = true
        reevaluate()
        if let accuracy = trained.heldOutAccuracy {
            return "Обучено на \(bad + good) кадрах. На отложенных кадрах угадывает \(Int((accuracy * 100).rounded())) %"
        }
        return "Обучено на \(bad + good) кадрах. Для проверки точности нужно от 15 размеченных"
    }

    func forgetModel() {
        model = nil
        UserDefaults.standard.removeObject(forKey: "defectModel")
        reevaluate()
    }

    // Готовые кадры копятся здесь и попадают в `records` раз в секунду: каждое изменение `records` и `done`
    // перерисовывает сетку, а кадров приходит по 10–20 в секунду
    @ObservationIgnored private var arrived: [URL: AnalysisRecord] = [:]
    @ObservationIgnored private var arrivedCount = 0
    @ObservationIgnored private var flushScheduled = false

    private func scheduleFlush() {
        guard !flushScheduled else { return }
        flushScheduled = true
        Task {
            try? await Task.sleep(for: .seconds(1))
            flushScheduled = false
            flush()
        }
    }

    private func flush() {
        guard arrivedCount > 0 else { return }
        takeArrived()
        done += arrivedCount
        arrivedCount = 0
        recomputeDefects()
        // Анализ новых кадров закончился — сообщаем, сколько это заняло
        if done >= total, runPending > 0, let runStarted {
            let seconds = Date().timeIntervalSince(runStarted)
            let summary = "Анализ: \(runPending) \(PhotoSession.plural(runPending, "кадр", "кадра", "кадров")) за \(Self.duration(seconds))"
            lastRunSummary = summary
            self.runStarted = nil
            onFinished?(summary)
        }
        if done >= total {
            PhotoAnalyzer.releaseModels()
        }
    }

    private func takeArrived() {
        guard !arrived.isEmpty else { return }
        records.merge(arrived) { $1 }
        arrived = [:]
        unsaved = true
        scheduleSave()
    }

    /// Новые записи анализа: пересобрать серии и пересчитать пометки
    private func recomputeDefects() {
        rebuildSeries()
        rebuildSignals()
        reevaluate()
        // Людей — когда анализ закончен: группировка тяжелее и при каждом новом кадре не нужна
        if !isRunning {
            rebuildPeople()
        }
    }

    // MARK: Люди

    /// Люди папки, больше всего кадров — первыми
    private(set) var people: [PersonCluster] = []
    private(set) var isGroupingPeople = false
    @ObservationIgnored private var peopleRun = 0

    /// Порог похожести лиц (настройка `peopleDistance`)
    var peopleDistance: Double {
        let value = UserDefaults.standard.double(forKey: "peopleDistance")
        return value > 0 ? value : PeopleGrouping.defaultDistance
    }

    /// Группировка в фоне; результат устаревшего запуска отбрасывается
    private func rebuildPeople() {
        guard PhotoAnalyzer.peopleEnabled else {
            people = []
            return
        }
        peopleRun += 1
        let run = peopleRun
        let items = records.map { (url: $0.key, metrics: $0.value.metrics) }
        let distance = peopleDistance
        isGroupingPeople = true
        Task {
            let found = await Task.detached(priority: .utility) {
                PeopleGrouping.cluster(items, maxDistance: distance)
            }.value
            guard run == peopleRun else { return }
            people = found
            isGroupingPeople = false
            onDefectsChanged?()
        }
    }

    /// Настройки «Людей» изменились — перегруппировать без повторного анализа
    func peopleSettingsChanged() {
        rebuildPeople()
    }

    /// Пометки из готовых метрик и серий (быстро: вызывается при каждом движении ползунка)
    private func reevaluate() {
        let all = records
        let stats = FolderStats.make(all.values.map(\.metrics))
        var result: [URL: [Defect]] = [:]
        var chances: [URL: Double] = [:]
        var reasons: [URL: String] = [:]
        let activeModel = useModel ? self.model : nil
        for (url, record) in all {
            let context = contexts[url]
            let found = DefectRules.evaluate(record.metrics, context: context, stats: stats, tuning: tuning,
                                             signals: signals[url])
            if !found.isEmpty { result[url] = found }
            if let activeModel {
                let x = DefectFeatures.vector(record.metrics, context)
                let p = activeModel.probability(x)
                chances[url] = p
                if p >= 0.4 { reasons[url] = activeModel.explanation(x) }
            }
        }
        folderStats = stats
        candidates = result
        probabilities = chances
        learnedDetails = reasons
        onDefectsChanged?()
    }

    private var source: URL?
    /// Записи кэша папки, которых нет среди кадров (файл убран из папки, другой режим пар RAW+JPEG):
    /// при записи кэша сохраняются как были, без повторного чтения файла
    @ObservationIgnored private var keptRecords: [String: AnalysisRecord] = [:]
    /// Номер запуска: результаты старых запусков после отмены отбрасываются
    private var generation = 0
    private var saveScheduled = false
    private var unsaved = false

    // MARK: Запуск и остановка

    /// Подтягивает кэш папки и ставит в очередь кадры без готовых метрик (в порядке `photos`)
    func start(photos: [URL], source: URL) {
        cancel()
        Task { await refreshPromptsIfNeeded() }
        generation += 1
        let run = generation
        self.source = source
        records = [:]
        keptRecords = [:]
        candidates = [:]
        probabilities = [:]
        learnedDetails = [:]
        series = []
        contexts = [:]
        signals = [:]
        people = []
        peopleRun += 1
        done = 0
        total = photos.count

        Task {
            let prepared = await Task.detached(priority: .utility) {
                AnalysisCache.prepare(photos: photos, source: source)
            }.value
            guard run == generation else { return }
            records = prepared.cached
            keptRecords = prepared.kept
            done = prepared.cached.count
            recomputeDefects()
            runStarted = Date()
            runPending = prepared.pending.count
            for url in prepared.pending {
                PhotoAnalyzer.enqueue(url) { record in
                    Task { @MainActor in
                        self.finish(url, record, run: run)
                    }
                }
            }
        }
    }

    /// Остановить анализ (смена папки) и сохранить готовое
    func cancel() {
        PhotoAnalyzer.cancelAll()
        PhotoAnalyzer.releaseModels()
        generation += 1
        takeArrived()
        arrivedCount = 0
        saveNow()
        total = 0
        done = 0
    }

    /// Выход из просмотра: анализ остановлен, метрики папки из памяти убираются (на диске они остаются)
    func close() {
        cancel()
        source = nil
        records = [:]
        keptRecords = [:]
        candidates = [:]
        probabilities = [:]
        learnedDetails = [:]
        series = []
        contexts = [:]
        neighbors = [:]
        signals = [:]
        people = []
        peopleRun += 1
    }

    private func finish(_ url: URL, _ record: AnalysisRecord?, run: Int) {
        guard run == generation else { return }
        if let record {
            arrived[url] = record
        }
        arrivedCount += 1
        scheduleFlush()
    }

    // MARK: Замер времени

    @ObservationIgnored private var runStarted: Date?
    @ObservationIgnored private var runPending = 0
    /// Итог последнего анализа: «Анализ: 1500 кадров за 2 мин 10 с»
    private(set) var lastRunSummary: String?
    /// Сессия показывает итог тостом
    @ObservationIgnored var onFinished: ((String) -> Void)?

    nonisolated static func duration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        if total < 60 { return "\(max(total, 1)) с" }
        let minutes = total / 60
        let rest = total % 60
        return rest == 0 ? "\(minutes) мин" : "\(minutes) мин \(rest) с"
    }

    // MARK: Для просмотра и калибровки

    /// Куда смотреть в 100 %: глаза самого крупного лица или центр объекта (доли кадра, сверху слева)
    func focusPoint(for url: URL) -> CGPoint? {
        guard let m = metrics(for: url) else { return nil }
        return PhotoAnalyzer.focusPoint(faces: m.faces, subject: m.subjectRect)
    }

    /// Настройки серий изменились — пересобрать без повторного анализа
    func seriesSettingsChanged() {
        recomputeDefects()
    }

    /// Файл перенесли или вернули: запись переезжает за ним, чтобы undo не требовал повторного анализа
    func moveRecord(from old: URL, to new: URL) {
        if let record = records.removeValue(forKey: old) {
            records[new] = record
        }
        if let record = arrived.removeValue(forKey: old) {
            arrived[new] = record
        }
        if let found = candidates.removeValue(forKey: old) {
            candidates[new] = found
        }
        if let p = probabilities.removeValue(forKey: old) {
            probabilities[new] = p
        }
        if let text = learnedDetails.removeValue(forKey: old) {
            learnedDetails[new] = text
        }
        if let context = contexts.removeValue(forKey: old) {
            contexts[new] = context
        }
        if let signal = signals.removeValue(forKey: old) {
            signals[new] = signal
        }
        if let value = labels.removeValue(forKey: old.standardizedFileURL) {
            labels[new.standardizedFileURL] = value
            saveLabels()
        }
    }

    // MARK: Запись на диск

    private func scheduleSave() {
        guard !saveScheduled else { return }
        saveScheduled = true
        Task {
            try? await Task.sleep(for: .seconds(10))
            saveScheduled = false
            saveNow()
        }
    }

    private func saveNow() {
        guard unsaved, let source else { return }
        unsaved = false
        AnalysisCache.save(records, keeping: keptRecords, source: source)
    }

    // MARK: Кэш для настроек

    func clearCache() {
        unsaved = false
        keptRecords = [:]
        AnalysisCache.clear()
    }
}

// MARK: - Кэш на диске

/// `~/Library/Caches/PhotoChoice/Analysis/` внутри контейнера песочницы; рядом с фото ничего не пишем.
/// Один файл на исходную папку (имя — SHA256 пути), внутри «относительный путь → запись»
nonisolated enum AnalysisCache {
    /// Запись и чтение по очереди: иначе медленная старая запись могла лечь поверх новой,
    /// и при следующем открытии часть кадров анализировалась заново
    private static let disk = DispatchQueue(label: "PhotoChoice.analysisCache", qos: .utility)

    static var directory: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("PhotoChoice/Analysis", isDirectory: true)
    }

    private static func file(for source: URL) -> URL? {
        let digest = SHA256.hash(data: Data(source.standardizedFileURL.path.utf8))
        let name = digest.map { String(format: "%02x", $0) }.joined()
        return directory?.appendingPathComponent(name).appendingPathExtension("plist")
    }

    private static func relativePath(_ url: URL, in source: URL) -> String? {
        let base = source.standardizedFileURL.path + "/"
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(base) else { return nil }
        return String(path.dropFirst(base.count))
    }

    /// Готовые записи (совпали размер, дата изменения и версия), кадры, которые надо проанализировать,
    /// и записи файлов, которых среди кадров нет
    static func prepare(photos: [URL], source: URL) -> (cached: [URL: AnalysisRecord], pending: [URL], kept: [String: AnalysisRecord]) {
        // Дожидаемся записи, начатой при прошлом открытии этой папки
        var stored: [String: AnalysisRecord] = disk.sync { read(source) }
        var cached: [URL: AnalysisRecord] = [:]
        var pending: [URL] = []
        // Модель включена — кадры без её векторов анализируются заново (саму модель здесь не грузим).
        // Не загрузилась — кадры остались без векторов, и анализировать их снова бессмысленно
        let needsClip = QualityModel.isEnabled && !QualityModel.failedToLoad
        let needsFaces = FaceModel.isEnabled && !FaceModel.failedToLoad
        for url in photos {
            if let record = relativePath(url, in: source).flatMap({ stored.removeValue(forKey: $0) }),
               record.version == PhotoAnalyzer.version,
               !needsClip || record.metrics.clipModel == QualityModel.identifier,
               !needsFaces || record.metrics.faceModel == FaceModel.identifier,
               let stamp = PhotoAnalyzer.fileStamp(url),
               stamp.size == record.fileSize,
               abs(stamp.modified.timeIntervalSince(record.modified)) < 1 {
                cached[url] = record
            } else {
                pending.append(url)
            }
        }
        // Остальные записи храним, пока файл существует (например, кадр в «Отобранных» внутри папки)
        let kept = stored.filter { FileManager.default.fileExists(atPath: source.appendingPathComponent($0.key).path) }
        return (cached, pending, kept)
    }

    private static func read(_ source: URL) -> [String: AnalysisRecord] {
        guard let file = file(for: source), let data = try? Data(contentsOf: file) else { return [:] }
        return (try? PropertyListDecoder().decode([String: AnalysisRecord].self, from: data)) ?? [:]
    }

    /// Записывает в фоне файлы, лежащие в исходной папке, и `kept`; файл кэша целиком заменяется
    static func save(_ records: [URL: AnalysisRecord], keeping kept: [String: AnalysisRecord], source: URL) {
        disk.async {
            guard let directory, let file = file(for: source) else { return }
            var stored = kept
            for (url, record) in records {
                if let key = relativePath(url, in: source) {
                    stored[key] = record
                }
            }
            let encoder = PropertyListEncoder()
            encoder.outputFormat = .binary
            guard let data = try? encoder.encode(stored) else { return }
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try? data.write(to: file, options: .atomic)
        }
    }

    /// Размер кэша в байтах — для кнопки в настройках
    static func size() -> Int64 {
        guard let directory,
              let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        return files.reduce(0) { total, url in
            total + Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
    }

    /// Удаляет файлы кэша (это служебные данные приложения, а не фото). В очереди — после начатых записей
    static func clear() {
        disk.sync {
            guard let directory,
                  let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
            for url in files {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }
}
