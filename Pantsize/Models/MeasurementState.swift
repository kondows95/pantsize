import CoreGraphics
import SwiftUI

struct MeasurementItem: Identifiable, Equatable, Codable {
    let id: UUID
    var line: LineMeasurement

    init(id: UUID = UUID(), line: LineMeasurement = LineMeasurement()) {
        self.id = id
        self.line = line
    }
}

enum LineEndpoint: String, CaseIterable, Identifiable {
    case start
    case end

    var id: String { rawValue }

    var label: String {
        switch self {
        case .start: return "始点"
        case .end: return "終点"
        }
    }
}

struct LineMeasurement: Equatable, Codable {
    /// aspect-fit 表示領域内の正規化座標 (0...1)。レイアウト変動の影響を受けない。
    var start: CGPoint?
    var end: CGPoint?

    init(start: CGPoint? = nil, end: CGPoint? = nil) {
        self.start = start
        self.end = end
    }

    var isComplete: Bool { start != nil && end != nil }

    var pointCount: Int {
        (start != nil ? 1 : 0) + (end != nil ? 1 : 0)
    }

    mutating func reset() {
        start = nil
        end = nil
    }

    mutating func undoLastPoint() {
        if end != nil {
            end = nil
        } else {
            start = nil
        }
    }

    mutating func migrateLegacyViewPointsIfNeeded(displayRect: CGRect) {
        guard displayRect.width > 0, displayRect.height > 0 else { return }
        if let start, isLikelyLegacyViewPoint(start) {
            self.start = Self.normalized(fromViewPoint: start, displayRect: displayRect)
        }
        if let end, isLikelyLegacyViewPoint(end) {
            self.end = Self.normalized(fromViewPoint: end, displayRect: displayRect)
        }
    }

    func distanceInImageSpace(imageSize: CGSize, displayRect: CGRect) -> CGFloat? {
        guard let start, let end,
              imageSize.width > 0, imageSize.height > 0 else { return nil }

        // 正規化座標 (aspect-fit 内) → 画像 px。レイアウト変動で displayRect が潰れても距離は不変。
        if displayRect.width > 1, displayRect.height > 1 {
            let s = Self.viewPoint(fromNormalized: start, displayRect: displayRect)
            let e = Self.viewPoint(fromNormalized: end, displayRect: displayRect)
            let si = ImageCoordinateMapper.imagePoint(fromViewPoint: s, displayRect: displayRect, imageSize: imageSize)
            let ei = ImageCoordinateMapper.imagePoint(fromViewPoint: e, displayRect: displayRect, imageSize: imageSize)
            let distance = hypot(ei.x - si.x, ei.y - si.y)
            if distance.isFinite { return distance }
        }

        let si = CGPoint(x: start.x * imageSize.width, y: start.y * imageSize.height)
        let ei = CGPoint(x: end.x * imageSize.width, y: end.y * imageSize.height)
        let distance = hypot(ei.x - si.x, ei.y - si.y)
        return distance.isFinite ? distance : nil
    }

    func normalized(for endpoint: LineEndpoint) -> CGPoint? {
        switch endpoint {
        case .start: return start
        case .end: return end
        }
    }

    func viewPoint(for endpoint: LineEndpoint, displayRect: CGRect) -> CGPoint? {
        guard let normalized = normalized(for: endpoint) else { return nil }
        return Self.viewPoint(fromNormalized: normalized, displayRect: displayRect)
    }

    mutating func setNormalizedPoint(_ point: CGPoint, for endpoint: LineEndpoint) {
        switch endpoint {
        case .start: start = point
        case .end: end = point
        }
    }

    mutating func setViewPoint(_ viewPoint: CGPoint, for endpoint: LineEndpoint, displayRect: CGRect) {
        setNormalizedPoint(Self.normalized(fromViewPoint: viewPoint, displayRect: displayRect), for: endpoint)
    }

    static func normalized(fromViewPoint viewPoint: CGPoint, displayRect: CGRect) -> CGPoint {
        CGPoint(
            x: (viewPoint.x - displayRect.minX) / displayRect.width,
            y: (viewPoint.y - displayRect.minY) / displayRect.height
        )
    }

    static func viewPoint(fromNormalized normalized: CGPoint, displayRect: CGRect) -> CGPoint {
        CGPoint(
            x: displayRect.minX + normalized.x * displayRect.width,
            y: displayRect.minY + normalized.y * displayRect.height
        )
    }

    private func isLikelyLegacyViewPoint(_ point: CGPoint) -> Bool {
        point.x > 1.5 || point.y > 1.5 || point.x < -0.25 || point.y < -0.25
    }

    enum CodingKeys: String, CodingKey {
        case start
        case end
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        start = try container.decodeIfPresent(StoredPoint.self, forKey: .start)?.cgPoint
        end = try container.decodeIfPresent(StoredPoint.self, forKey: .end)?.cgPoint
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(start.map(StoredPoint.init), forKey: .start)
        try container.encodeIfPresent(end.map(StoredPoint.init), forKey: .end)
    }
}

private struct StoredPoint: Codable, Equatable {
    var x: Double
    var y: Double

    init(_ point: CGPoint) {
        x = point.x
        y = point.y
    }

    var cgPoint: CGPoint {
        CGPoint(x: x, y: y)
    }
}

enum PointSnap {
    static let threshold: CGFloat = 28

    static func snap(
        _ viewPoint: CGPoint,
        anchors: [CGPoint],
        excluding: CGPoint? = nil,
        threshold: CGFloat = threshold
    ) -> CGPoint {
        for anchor in anchors {
            if let excluding, hypot(anchor.x - excluding.x, anchor.y - excluding.y) < 0.5 {
                continue
            }
            if hypot(anchor.x - viewPoint.x, anchor.y - viewPoint.y) <= threshold {
                return anchor
            }
        }
        return viewPoint
    }

    static func viewAnchors(from measurements: [MeasurementItem], displayRect: CGRect) -> [CGPoint] {
        measurements.flatMap { item -> [CGPoint] in
            var points: [CGPoint] = []
            if let start = item.line.viewPoint(for: .start, displayRect: displayRect) { points.append(start) }
            if let end = item.line.viewPoint(for: .end, displayRect: displayRect) { points.append(end) }
            return points
        }
    }
}

enum MeasurementPalette {
    static let colors: [Color] = [
        .cyan, .orange, .green, .pink, .yellow, .purple, .mint, .indigo,
    ]

    static func color(at index: Int) -> Color {
        colors[(index - 1) % colors.count]
    }
}

enum MeasurementScale {
    static func centimeters(
        forPx px: CGFloat,
        referencePx: CGFloat,
        referenceCm: Double
    ) -> Double? {
        guard referencePx > 0, referenceCm > 0, px >= 0 else { return nil }
        return (px / referencePx) * referenceCm
    }

    /// 実測値入力用。数字と小数点1つだけ残す（入力中の末尾「.」も許可）。
    static func sanitizeDecimalInput(_ text: String) -> String {
        let halfWidth = text.applyingTransform(StringTransform.fullwidthToHalfwidth, reverse: false) ?? text
        let trimmed = halfWidth.trimmingCharacters(in: .whitespaces)

        var result = ""
        var hasDecimalSeparator = false
        for character in trimmed {
            if character.isNumber {
                result.append(character)
                continue
            }
            if (character == "." || character == "," || character == "，") && !hasDecimalSeparator {
                hasDecimalSeparator = true
                result.append(".")
            }
        }
        return result
    }

    static func parseCm(_ text: String) -> Double? {
        let normalized = sanitizeDecimalInput(text)
        guard !normalized.isEmpty else { return nil }
        let forParse = normalized.hasSuffix(".") ? String(normalized.dropLast()) : normalized
        guard !forParse.isEmpty else { return nil }
        return Double(forParse)
    }
}

enum ImageCoordinateMapper {
    static func displayRect(imageSize: CGSize, in viewSize: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0,
              viewSize.width > 0, viewSize.height > 0 else {
            return .zero
        }
        let scale = min(viewSize.width / imageSize.width, viewSize.height / imageSize.height)
        let w = imageSize.width * scale
        let h = imageSize.height * scale
        let x = (viewSize.width - w) / 2
        let y = (viewSize.height - h) / 2
        return CGRect(x: x, y: y, width: w, height: h)
    }

    static func imagePoint(fromViewPoint viewPoint: CGPoint, displayRect: CGRect, imageSize: CGSize) -> CGPoint {
        let nx = (viewPoint.x - displayRect.minX) / displayRect.width
        let ny = (viewPoint.y - displayRect.minY) / displayRect.height
        return CGPoint(x: nx * imageSize.width, y: ny * imageSize.height)
    }
}
