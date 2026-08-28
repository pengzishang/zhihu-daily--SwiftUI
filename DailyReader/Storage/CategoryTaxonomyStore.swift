import Foundation

/// 类目体系存储：存 `CategoryTaxonomy`（含 `isFrozen`、冻结时间），落 `Application Support`。
///
/// 落点 `Application Support/DailyReader/category/taxonomy.json`。
actor CategoryTaxonomyStore {
    private let fileURL: URL
    private var taxonomy: CategoryTaxonomy?
    private var hasLoaded = false

    init(fileManager: FileManager = .default, rootURL: URL? = nil) {
        let base = rootURL
            ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.fileURL = base.appendingPathComponent("DailyReader/category/taxonomy.json")
    }

    var isFrozen: Bool {
        ensureLoaded()
        return taxonomy?.isFrozen ?? false
    }

    func load() -> CategoryTaxonomy? {
        ensureLoaded()
        return taxonomy
    }

    func save(_ value: CategoryTaxonomy) {
        taxonomy = value
        hasLoaded = true
        persist()
    }

    private func ensureLoaded() {
        guard !hasLoaded else { return }
        hasLoaded = true
        taxonomy = Self.readFromDisk(fileURL: fileURL)
    }

    private nonisolated static func readFromDisk(fileURL: URL) -> CategoryTaxonomy? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(CategoryTaxonomy.self, from: data)
    }

    private func persist() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(taxonomy) else { return }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: fileURL, options: [.atomic])
    }
}
