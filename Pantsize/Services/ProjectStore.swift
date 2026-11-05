import Foundation
import UIKit

@Observable
final class ProjectStore {
    private(set) var summaries: [MeasurementProjectSummary] = []

    private let fileManager = FileManager.default
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private var rootDirectory: URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("PantsizeProjects", isDirectory: true)
    }

    private var manifestURL: URL {
        rootDirectory.appendingPathComponent("manifest.json")
    }

    init() {
        try? ensureRootDirectory()
        reload()
    }

    func reload() {
        guard let data = try? Data(contentsOf: manifestURL),
              let decoded = try? decoder.decode([MeasurementProjectSummary].self, from: data) else {
            summaries = []
            return
        }
        summaries = decoded
    }

    func createProject(from image: UIImage, title: String? = nil) throws -> UUID {
        let defaultTitle = title ?? Self.defaultTitle(for: Date())
        var record = MeasurementProjectRecord.new(from: image, title: defaultTitle)
        record.updatedAt = Date()
        try write(record: record, image: image)
        upsertSummary(MeasurementProjectSummary(record: record), insertAtTop: true)
        try saveManifest()
        return record.id
    }

    func record(id: UUID) -> MeasurementProjectRecord? {
        let url = projectDirectory(id).appendingPathComponent("project.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(MeasurementProjectRecord.self, from: data)
    }

    func loadImage(id: UUID) -> UIImage? {
        let url = projectDirectory(id).appendingPathComponent("photo.jpg")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    func save(_ record: MeasurementProjectRecord, image: UIImage?) throws {
        var updated = record
        updated.updatedAt = Date()
        try write(record: updated, image: image)
        upsertSummary(MeasurementProjectSummary(record: updated))
        try saveManifest()
    }

    func moveSummaries(fromOffsets: IndexSet, toOffset: Int) {
        summaries.move(fromOffsets: fromOffsets, toOffset: toOffset)
        try? saveManifest()
    }

    func deleteProject(id: UUID) throws {
        let directory = projectDirectory(id)
        if fileManager.fileExists(atPath: directory.path) {
            try fileManager.removeItem(at: directory)
        }
        summaries.removeAll { $0.id == id }
        try saveManifest()
    }

    private func write(record: MeasurementProjectRecord, image: UIImage?) throws {
        try ensureRootDirectory()
        let directory = projectDirectory(record.id)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let json = try encoder.encode(record)
        try json.write(to: directory.appendingPathComponent("project.json"), options: .atomic)
        if let image, let data = image.jpegData(compressionQuality: 0.88) {
            try data.write(to: directory.appendingPathComponent("photo.jpg"), options: .atomic)
        }
    }

    private func projectDirectory(_ id: UUID) -> URL {
        rootDirectory.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    private func ensureRootDirectory() throws {
        try fileManager.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
    }

    private func upsertSummary(_ summary: MeasurementProjectSummary, insertAtTop: Bool = false) {
        if let index = summaries.firstIndex(where: { $0.id == summary.id }) {
            let createdAt = summaries[index].createdAt
            var updated = summary
            updated.createdAt = createdAt
            summaries[index] = updated
        } else if insertAtTop {
            summaries.insert(summary, at: 0)
        } else {
            summaries.append(summary)
        }
    }

    private func saveManifest() throws {
        try ensureRootDirectory()
        let data = try encoder.encode(summaries)
        try data.write(to: manifestURL, options: .atomic)
    }

    private static func defaultTitle(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
