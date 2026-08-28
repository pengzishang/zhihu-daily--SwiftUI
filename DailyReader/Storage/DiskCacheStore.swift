import Foundation

actor DiskCacheStore: CacheStore {
    private let fileManager: FileManager
    private let rootURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    // MARK: - 缓存清理策略

    /// 磁盘缓存总量上限（与 ImageCacheService 一致）。
    static let maxTotalBytes: Int64 = 300 * 1024 * 1024
    /// 日报历史保留天数（用户翻旧刊需要）。
    static let dailyTTL: TimeInterval = 30 * 24 * 3600
    /// 文章详情保留天数（内容实时性较高）。
    static let detailTTL: TimeInterval = 7 * 24 * 3600
    /// 首页聚合 / 热榜保留天数。
    static let bundleTTL: TimeInterval = 7 * 24 * 3600


    init(fileManager: FileManager = .default, rootURL: URL? = nil) {
        self.fileManager = fileManager
        let baseURL = rootURL ?? fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
        self.rootURL = baseURL.appendingPathComponent("DailyReaderCache", isDirectory: true)
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func saveLatest(_ response: DailyResponse) async {
        await write(CacheEnvelope(value: response), to: latestURL)
        await saveDaily(response)
    }

    func loadLatest() async -> CachedValue<DailyResponse>? {
        await read(from: latestURL)
    }

    func saveDaily(_ response: DailyResponse) async {
        guard !response.date.isEmpty else { return }
        await write(CacheEnvelope(value: response), to: dailyURL(for: response.date))
    }

    func loadDaily(date: String) async -> CachedValue<DailyResponse>? {
        await read(from: dailyURL(for: date))
    }

    func loadDaily(dates: [String]) async -> [String: CachedValue<DailyResponse>] {
        var cachedValues: [String: CachedValue<DailyResponse>] = [:]
        for date in dates where cachedValues[date] == nil {
            if let cached: CachedValue<DailyResponse> = await read(from: dailyURL(for: date)) {
                cachedValues[date] = cached
            }
        }
        return cachedValues
    }

    func saveDetail(_ detail: ArticleDetail) async {
        await write(CacheEnvelope(value: detail), to: detailURL(for: detail.id))
    }

    func loadDetail(id: Int) async -> CachedValue<ArticleDetail>? {
        await read(from: detailURL(for: id))
    }

    func saveHomeFeed(
        sections: [DailySection],
        topStories: [TopStory],
        historyCursor: String?
    ) async {
        let feed = CachedHomeFeed(
            sections: sections,
            topStories: topStories,
            historyCursor: historyCursor
        )
        await write(CacheEnvelope(value: feed), to: homeFeedURL)
    }

    func loadHomeFeed() async -> CachedValue<CachedHomeFeed>? {
        await read(from: homeFeedURL)
    }

    func saveHotList(_ response: HotListResponse) async {
        await write(CacheEnvelope(value: response), to: hotListURL)
    }

    func loadHotList() async -> CachedValue<HotListResponse>? {
        await read(from: hotListURL)
    }

    private var hotListURL: URL {
        rootURL.appendingPathComponent("hot_list.json")
    }

    private var homeFeedURL: URL {
        rootURL.appendingPathComponent("home_feed.json")
    }

    private var latestURL: URL {
        rootURL.appendingPathComponent("latest.json")
    }

    private var dailyRootURL: URL {
        rootURL.appendingPathComponent("daily", isDirectory: true)
    }

    private var detailRootURL: URL {
        rootURL.appendingPathComponent("detail", isDirectory: true)
    }

    private func dailyURL(for date: String) -> URL {
        dailyRootURL.appendingPathComponent("\(date).json")
    }

    private func detailURL(for id: Int) -> URL {
        detailRootURL.appendingPathComponent("\(id).json")
    }

    private func write<Value: Codable>(_ envelope: CacheEnvelope<Value>, to url: URL) async {
        do {
            try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try encoder.encode(envelope)
            try data.write(to: url, options: [.atomic])
        } catch {
            return
        }
        await pruneIfNeeded()
    }

    private func read<Value: Codable>(from url: URL) async -> CachedValue<Value>? {
        do {
            let data = try Data(contentsOf: url)
            let envelope = try decoder.decode(CacheEnvelope<Value>.self, from: data)
            return CachedValue(value: envelope.value, cachedAt: envelope.cachedAt)
        } catch {
            return nil
        }
    }


    // MARK: - 缓存清理

    /// 递归遍历 rootURL 下所有文件，按目录 TTL 删除过期文件，
    /// 若总大小超过 maxTotalBytes 则按修改时间从旧到新删除，直至低于上限。
    private func pruneIfNeeded() async {
        let now = Date()
        guard let enumerator = fileManager.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .totalFileAllocatedSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        var files: [(url: URL, modified: Date, size: Int64, ttl: TimeInterval)] = []
        var totalSize: Int64 = 0

        for case let url as URL in enumerator {
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory),
                  !isDirectory.boolValue else { continue }

            let attrs = try? url.resourceValues(forKeys: [.contentModificationDateKey, .totalFileAllocatedSizeKey])
            guard let modified = attrs?.contentModificationDate else { continue }
            let size = Int64(attrs?.totalFileAllocatedSize ?? 0)
            totalSize += size
            files.append((url, modified, size, Self.ttl(for: url)))
        }

        // 过期清理：删除超过 TTL 的文件
        for file in files where now.timeIntervalSince(file.modified) > file.ttl {
            try? fileManager.removeItem(at: file.url)
            totalSize -= file.size
        }

        // 容量清理：保留最新文件，删除最旧的直到低于上限
        guard totalSize > Self.maxTotalBytes else { return }
        let aged = files.filter { fileManager.fileExists(atPath: $0.url.path) }
            .sorted { $0.modified < $1.modified }
        for file in aged where totalSize > Self.maxTotalBytes {
            try? fileManager.removeItem(at: file.url)
            totalSize -= file.size
        }
    }

    /// 按文件所在目录判断 TTL。
    private static func ttl(for url: URL) -> TimeInterval {
        let parentName = url.deletingLastPathComponent().lastPathComponent
        switch parentName {
        case "daily":   return dailyTTL
        case "detail":  return detailTTL
        default:        return bundleTTL
        }
    }

}

private struct CacheEnvelope<Value: Codable>: Codable {
    let cachedAt: Date
    let value: Value

    init(value: Value, cachedAt: Date = Date()) {
        self.cachedAt = cachedAt
        self.value = value
    }
}
