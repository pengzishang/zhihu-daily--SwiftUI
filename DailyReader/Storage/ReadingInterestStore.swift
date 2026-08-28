import Foundation

/// 阅读兴趣汇总存储：按 articleID 存 / 合并 `ReadingInterestRecord`，落 `Application Support`。
///
/// 落点 `Application Support/DailyReader/interest/records.json`。纯本地，绝不上报。
actor ReadingInterestStore {
    private let fileURL: URL
    private var cache: [Int: ReadingInterestRecord] = [:]
    private var hasLoaded = false

    init(fileManager: FileManager = .default, rootURL: URL? = nil) {
        let base = rootURL
            ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.fileURL = base.appendingPathComponent("DailyReader/interest/records.json")
    }

    /// 合并一次会话信号（落盘）。
    func record(_ signal: ReadingSessionSignal) {
        ensureLoaded()
        var record = cache[signal.articleID] ?? ReadingInterestRecord(articleID: signal.articleID)
        record.merge(signal)
        cache[signal.articleID] = record
        persist()
    }

    func record(for articleID: Int) -> ReadingInterestRecord? {
        ensureLoaded()
        return cache[articleID]
    }

    func all() -> [Int: ReadingInterestRecord] {
        ensureLoaded()
        return cache
    }

    private func ensureLoaded() {
        guard !hasLoaded else { return }
        hasLoaded = true
        if let loaded = Self.readFromDisk(fileURL: fileURL) {
            cache = loaded
        }
    }

    private nonisolated static func readFromDisk(fileURL: URL) -> [Int: ReadingInterestRecord]? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode([Int: ReadingInterestRecord].self, from: data)
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
