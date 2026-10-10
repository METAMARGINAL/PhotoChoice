import Accelerate
import CoreGraphics
import Foundation

// Умный отбор: раздел «Люди». Лица собираются в людей по векторам модели распознавания (AuraFace, FaceModel),
// а если её нет — по отпечаткам Vision (FaceMetrics.print): они не учены различать людей и путают их чаще.
// Людей начинают только хорошие лица (крупные, резкие, не в профиль), центры групп уточняются по всем
// их лицам, близкие группы сливаются. Слабые лица только присоединяются, и с запасом по порогу; сомнительное
// лицо остаётся без группы, а не уходит к кому попало.
// Векторы лиц — биометрические данные: они только в кэше анализа на этом Mac.

/// Лицо: кадр и номер лица в `PhotoMetrics.faces`
nonisolated struct FaceRef: Hashable, Sendable {
    let url: URL
    let index: Int
}

/// Человек — группа похожих лиц
nonisolated struct PersonCluster: Sendable {
    var faces: [FaceRef]
    /// Кадры с этим человеком (каждый один раз)
    var photos: [URL]
    /// Лицо для плитки: крупное, резкое, анфас
    var cover: FaceRef
}

nonisolated enum PeopleGrouping {
    /// Порог похожести по умолчанию — расстояние между нормированными отпечатками Vision.
    /// Подбирается в настройках («Похожесть лиц»); для векторов модели переводится в свой порог
    static let defaultDistance = 0.75

    /// Порог по косинусу для векторов модели: «Строго» (0.6) → 0.5, «Обычно» (0.75) → 0.41, «Свободно» (0.9) → 0.32
    static func identityThreshold(_ maxDistance: Double) -> Float {
        Float(0.5 - (maxDistance - 0.6) / 0.3 * 0.18)
    }

    private nonisolated struct Face {
        let ref: FaceRef
        let vector: [Float]
        let area: Double
        /// Насколько лицо годится в обложку и в начало группы
        let look: Double
        /// Достаточно хорошее, чтобы начать с него нового человека
        let core: Bool
    }

    private nonisolated struct Group {
        var members: [Int] = []
        var photos: Set<URL> = []
        var sum: [Float]
        var center: [Float]
    }

    /// Группы, где человек встречается меньше чем на 2 кадрах, отбрасываются. Больше кадров — раньше
    static func cluster(_ items: [(url: URL, metrics: PhotoMetrics)], maxDistance: Double) -> [PersonCluster] {
        var identities: [Face] = []
        var prints: [Face] = []
        for item in items {
            for (i, face) in item.metrics.faces.enumerated() {
                let area = Double(face.rect.width * face.rect.height)
                let frontal = abs(face.yaw ?? 0) <= 25 ? 1.0 : 0.4
                let look = area.squareRoot() * (face.quality ?? 0.3) * frontal
                let ref = FaceRef(url: item.url, index: i)
                if let vector = ClipVector.unpack(face.identity).flatMap(ClipVector.normalized) {
                    let core = abs(face.yaw ?? 0) <= 40 && (face.quality ?? 0.3) >= 0.25
                    identities.append(Face(ref: ref, vector: vector, area: area, look: look, core: core))
                } else if let vector = normalized(face.print) {
                    prints.append(Face(ref: ref, vector: vector, area: area, look: look, core: true))
                }
            }
        }
        // Расстояние между единичными векторами: d² = 2 − 2·(a·b) — порог Vision переводим в скалярное произведение
        let printDot = Float(1 - maxDistance * maxDistance / 2)
        let found = group(identities, minDot: identityThreshold(maxDistance)) + group(prints, minDot: printDot)
        return found.sorted { $0.photos.count > $1.photos.count }
    }

    private static func group(_ faces: [Face], minDot: Float) -> [PersonCluster] {
        guard !faces.isEmpty else { return [] }
        let core = faces.indices.filter { faces[$0].core }.sorted { faces[$0].look > faces[$1].look }
        let weak = faces.indices.filter { !faces[$0].core }.sorted { faces[$0].look > faces[$1].look }
        var groups: [Group] = []

        func best(_ i: Int, _ threshold: Float) -> Int? {
            var found: Int?
            var bestDot = threshold
            for g in groups.indices {
                // Два лица одного кадра — это разные люди; векторы разных моделей несравнимы
                guard !groups[g].photos.contains(faces[i].ref.url),
                      groups[g].center.count == faces[i].vector.count else { continue }
                let dot = vDSP.dot(faces[i].vector, groups[g].center)
                if dot >= bestDot {
                    bestDot = dot
                    found = g
                }
            }
            return found
        }

        func add(_ i: Int, to g: Int) {
            let vector = faces[i].vector
            groups[g].sum = groups[g].members.isEmpty ? vector : vDSP.add(groups[g].sum, vector)
            groups[g].center = normalized(groups[g].sum) ?? groups[g].center
            groups[g].members.append(i)
            groups[g].photos.insert(faces[i].ref.url)
        }

        func place(_ i: Int) {
            if let g = best(i, minDot) {
                add(i, to: g)
            } else {
                groups.append(Group(members: [i], photos: [faces[i].ref.url], sum: faces[i].vector, center: faces[i].vector))
            }
        }

        // 1. Первый проход: хорошие лица по убыванию качества
        for i in core { place(i) }

        // 2. Уточнение: центры уже собраны по всем лицам — раскладываем заново, ошибки первого прохода уходят
        for _ in 0..<2 {
            groups = groups.map { Group(sum: $0.center, center: $0.center) }
            for i in core { place(i) }
            groups.removeAll { $0.members.isEmpty }
        }

        // 3. Один человек мог разделиться на две группы (свет, ракурс) — сливаем очень близкие
        var merged = true
        while merged {
            merged = false
            search: for a in groups.indices {
                for b in groups.indices where b > a {
                    guard groups[a].photos.isDisjoint(with: groups[b].photos),
                          vDSP.dot(groups[a].center, groups[b].center) >= minDot + 0.1 else { continue }
                    for i in groups[b].members { add(i, to: a) }
                    groups.remove(at: b)
                    merged = true
                    break search
                }
            }
        }

        // 4. Слабые лица только присоединяются, с запасом по порогу
        for i in weak {
            if let g = best(i, minDot + 0.05) { add(i, to: g) }
        }

        var result: [PersonCluster] = []
        for g in groups where g.photos.count >= 2 {
            var seen = Set<URL>()
            let photos = g.members.map { faces[$0].ref.url }.filter { seen.insert($0).inserted }
            guard let cover = g.members.max(by: { faces[$0].look < faces[$1].look }) else { continue }
            result.append(PersonCluster(faces: g.members.map { faces[$0].ref }, photos: photos, cover: faces[cover].ref))
        }
        return result
    }

    // MARK: Помощники

    private static func normalized(_ data: Data?) -> [Float]? {
        guard let data, data.count >= MemoryLayout<Float>.size * 16 else { return nil }
        let count = data.count / MemoryLayout<Float>.size
        var values = [Float](repeating: 0, count: count)
        _ = values.withUnsafeMutableBytes { data.copyBytes(to: $0, count: count * MemoryLayout<Float>.size) }
        return normalized(values)
    }

    private static func normalized(_ values: [Float]) -> [Float]? {
        let norm = vDSP.sumOfSquares(values).squareRoot()
        guard norm > 0 else { return nil }
        return vDSP.divide(values, norm)
    }
}
