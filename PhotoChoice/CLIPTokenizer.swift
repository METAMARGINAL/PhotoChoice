import Foundation

// Токенизатор CLIP для текстовой части MobileCLIP: текст → 77 номеров токенов.
// Тот же BPE, что simple_tokenizer.py в openai/CLIP (MIT). Словарь отдельно не хранится:
// он однозначно строится из списка слияний clip-merges.txt (первые 48 894 строки оригинала).
// Нужен только для расчёта подсказок в калибровке; при анализе фото не используется.

nonisolated struct CLIPTokenizer: Sendable {
    static let contextLength = 77

    private static let pattern = #"<\|startoftext\|>|<\|endoftext\|>|'s|'t|'re|'ve|'m|'ll|'d|[\p{L}]+|[\p{N}]|[^\s\p{L}\p{N}]+"#

    /// «a b» → ранг слияния: меньше — сливается раньше
    private let ranks: [String: Int]
    private let vocab: [String: Int]
    /// Байт UTF-8 → символ словаря
    private let symbols: [String]
    private let startToken: Int
    private let endToken: Int

    init?(bundle: Bundle = .main) {
        guard let url = bundle.url(forResource: "clip-merges", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        // Первая строка — «#version»
        let merges = text.split(separator: "\n").dropFirst().map(String.init)
        guard merges.count > 1000 else { return nil }

        // Печатные байты — своими символами, остальные — по порядку с U+0100
        let printable = Array(33...126) + Array(161...172) + Array(174...255)
        let printableSet = Set(printable)
        let order = printable + (0..<256).filter { !printableSet.contains($0) }
        var symbols = [String](repeating: "", count: 256)
        var vocab: [String: Int] = [:]
        for (i, byte) in order.enumerated() {
            let code = i < printable.count ? byte : 256 + i - printable.count
            guard let scalar = Unicode.Scalar(UInt32(code)) else { return nil }
            let symbol = String(Character(scalar))
            symbols[byte] = symbol
            vocab[symbol] = i
            vocab[symbol + "</w>"] = 256 + i
        }
        var ranks: [String: Int] = [:]
        for (i, line) in merges.enumerated() {
            let parts = line.split(separator: " ")
            guard parts.count == 2 else { continue }
            ranks[line] = i
            vocab[String(parts[0]) + String(parts[1])] = 512 + i
        }
        self.ranks = ranks
        self.vocab = vocab
        self.symbols = symbols
        startToken = 512 + merges.count
        endToken = startToken + 1
    }

    /// Проверка на известном примере: без неё ошибка в словаре дала бы тихо неверные векторы
    var isValid: Bool {
        Array(tokens("a photo of a cat").prefix(7)) == [49406, 320, 1125, 539, 320, 2368, 49407]
    }

    /// Начало, текст (до 75 токенов), конец, дальше нули
    func tokens(_ text: String) -> [Int32] {
        let clean = text.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
        var ids: [Int] = []
        if let regex = try? NSRegularExpression(pattern: Self.pattern, options: [.caseInsensitive]) {
            for match in regex.matches(in: clean, range: NSRange(clean.startIndex..., in: clean)) {
                guard let range = Range(match.range, in: clean) else { continue }
                let word = clean[range].utf8.map { symbols[Int($0)] }.joined()
                ids += bpe(word).compactMap { vocab[$0] }
            }
        }
        var result = [Int32](repeating: 0, count: Self.contextLength)
        result[0] = Int32(startToken)
        let body = ids.prefix(Self.contextLength - 2)
        for (i, id) in body.enumerated() {
            result[i + 1] = Int32(id)
        }
        result[body.count + 1] = Int32(endToken)
        return result
    }

    /// Слово → части словаря: раз за разом сливаем соседнюю пару с наименьшим рангом
    private func bpe(_ word: String) -> [String] {
        var parts = word.unicodeScalars.map { String($0) }
        guard !parts.isEmpty else { return [] }
        parts[parts.count - 1] += "</w>"
        while parts.count > 1 {
            var best: (index: Int, rank: Int)?
            for i in 0..<(parts.count - 1) {
                if let rank = ranks[parts[i] + " " + parts[i + 1]], rank < (best?.rank ?? .max) {
                    best = (i, rank)
                }
            }
            guard let best else { break }
            let first = parts[best.index]
            let second = parts[best.index + 1]
            var merged: [String] = []
            var i = 0
            while i < parts.count {
                if i < parts.count - 1, parts[i] == first, parts[i + 1] == second {
                    merged.append(first + second)
                    i += 2
                } else {
                    merged.append(parts[i])
                    i += 1
                }
            }
            parts = merged
        }
        return parts
    }
}
