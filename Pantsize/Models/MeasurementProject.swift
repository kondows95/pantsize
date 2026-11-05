import Foundation
import UIKit

struct MeasurementProjectRecord: Codable, Equatable, Identifiable {
    var id: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date
    var measurements: [MeasurementItem]
    var activeMeasurementID: UUID?
    var referenceMeasurementID: UUID?
    /// JSON 用（キーは MeasurementItem.id の uuidString）
    var referenceCmTextByMeasurementID: [String: String]

    var referenceCmByID: [UUID: String] {
        get {
            referenceCmTextByMeasurementID.reduce(into: [:]) { result, pair in
                if let id = UUID(uuidString: pair.key) {
                    result[id] = pair.value
                }
            }
        }
        set {
            referenceCmTextByMeasurementID = newValue.reduce(into: [:]) { result, pair in
                result[pair.key.uuidString] = pair.value
            }
        }
    }

    static func new(from _: UIImage, title: String) -> MeasurementProjectRecord {
        let now = Date()
        let first = MeasurementItem()
        return MeasurementProjectRecord(
            id: UUID(),
            title: title,
            createdAt: now,
            updatedAt: now,
            measurements: [first],
            activeMeasurementID: first.id,
            referenceMeasurementID: nil,
            referenceCmTextByMeasurementID: [:]
        )
    }
}

struct MeasurementProjectSummary: Codable, Equatable, Identifiable {
    var id: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date
    var measurementCount: Int
    var completeMeasurementCount: Int

    init(record: MeasurementProjectRecord) {
        id = record.id
        title = record.title
        createdAt = record.createdAt
        updatedAt = record.updatedAt
        measurementCount = record.measurements.count
        completeMeasurementCount = record.measurements.filter(\.line.isComplete).count
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        measurementCount = try container.decode(Int.self, forKey: .measurementCount)
        completeMeasurementCount = try container.decode(Int.self, forKey: .completeMeasurementCount)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? updatedAt
    }
}
