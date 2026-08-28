import Foundation

/// 单篇文章的累计阅读兴趣汇总（本地，绝不联网上报）。
struct ReadingInterestRecord: Codable, Equatable, Sendable {
    let articleID: Int
    var dwellSeconds: Double
    var maxScrollPercent: Double
    var readCount: Int
    var lastReadAt: Date
    var isFavorited: Bool
    var isHidden: Bool

    init(
        articleID: Int,
        dwellSeconds: Double = 0,
        maxScrollPercent: Double = 0,
        readCount: Int = 0,
        lastReadAt: Date = Date(),
        isFavorited: Bool = false,
        isHidden: Bool = false
    ) {
        self.articleID = articleID
        self.dwellSeconds = dwellSeconds
        self.maxScrollPercent = maxScrollPercent
        self.readCount = readCount
        self.lastReadAt = lastReadAt
        self.isFavorited = isFavorited
        self.isHidden = isHidden
    }

    /// 合并一次阅读会话信号（用于落盘）。
    mutating func merge(_ signal: ReadingSessionSignal) {
        dwellSeconds += max(0, signal.dwellSeconds)
        maxScrollPercent = max(maxScrollPercent, min(1, signal.maxScrollPercent))
        readCount += 1
        lastReadAt = Date()
        isFavorited = signal.isFavorited
        isHidden = signal.isHidden
    }
}

/// 一次阅读会话采集到的原始信号（由 ArticleDetailView 提交）。
struct ReadingSessionSignal: Sendable {
    let articleID: Int
    let maxScrollPercent: Double
    let dwellSeconds: Double
    let isFavorited: Bool
    let isHidden: Bool
}
