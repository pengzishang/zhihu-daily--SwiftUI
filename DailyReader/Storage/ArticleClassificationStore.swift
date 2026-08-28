import Foundation

/// 文章分类缓存：按 articleID 存 `ArticleClassification`，落 `Application Support`。
///
/// 落点 `Application Support/DailyReader/classification/classifications.json`：
/// 不被系统清缓存（区别于 `Caches/`），也不进 Keychain（数据量较大），随整机备份。
actor ArticleClassificationStore {
    private let fileURL: URL
    private var cache: [Int: ArticleClassification] = [:]
    private var hasLoaded = false

    init(fileManager: FileManager = .default, rootURL: URL? = nil) {
        let base = rootURL
            ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.fileURL = base.appendingPathComponent("DailyReader/classification/classifications.json")
    }

    func classification(for articleID: Int) -> ArticleClassification? {
        ensureLoaded()
        return cache[articleID]
    }

    func save(_ value: ArticleClassification) {
        ensureLoaded()
        cache[value.articleID] = value
        persist()
    }

    func all() -> [Int: ArticleClassification] {
        ensureLoaded()
        return cache
    }

    /// 将某类目下的文章重新映射到目标类目（用于「合并」类目）。
    func remap(categoryID oldID: String, to newID: String) {
        ensureLoaded()
        var updated: [Int: ArticleClassification] = [:]
        for (key, var record) in cache where record.categoryID == oldID {
            record.categoryID = newID
            updated[key] = record
        }
        guard !updated.isEmpty else { return }
        cache.merge(updated) { _, new in new }
        persist()
    }

    private func ensureLoaded() {
        guard !hasLoaded else { return }
        hasLoaded = true
        if let loaded = Self.readFromDisk(fileURL: fileURL) {
            cache = loaded
        }
    }

    private nonisolated static func readFromDisk(fileURL: URL) -> [Int: ArticleClassification]? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode([Int: ArticleClassification].self, from: data)
    }

    private func persist() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(cache) else { return }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: fileURL, options: [.atomic])
    }
}
