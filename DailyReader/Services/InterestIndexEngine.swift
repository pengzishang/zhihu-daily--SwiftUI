import Foundation

/// 兴趣指数引擎：完全无状态、可单测的纯函数集合。
///
/// 所有计算仅依赖传入的 `ReadingInterestRecord` / `ArticleClassification` /
/// `CategoryTaxonomy` 与可变 `now: Date`，可在任意线程同步调用，不依赖任何 IO。
struct InterestIndexEngine {
    /// 单篇停留封顶：≥180s 视为满格。
    static let dwellCeilingSeconds: TimeInterval = 180
    /// 时间衰减半衰期（天）。
    static let decayHalfLifeDays: Double = 30
    /// 类目样本不足阈值（成员 < 3 标注「样本不足」）。
    static let lowSampleThreshold = 3
    /// 收藏额外强正加成。
    static let favoriteBonus: Double = 0.25
    /// 阅读次数满额（达到即拿满 0.2 权重）。
    static let readCountFullMark: Double = 5

    private static func clamp01(_ x: Double) -> Double { min(1, max(0, x)) }

    /// 单篇原始得分（未衰减），范围 [0,1]；不感兴趣 ≈ 0。
    static func rawScore(for record: ReadingInterestRecord) -> Double {
        if record.isHidden { return 0 }
        let scroll = clamp01(record.maxScrollPercent)
        let dwellNorm = clamp01(record.dwellSeconds / dwellCeilingSeconds)
        let readBonus = clamp01(Double(record.readCount) / readCountFullMark)
        var base = 0.4 * scroll + 0.4 * dwellNorm + 0.2 * readBonus
        if record.isFavorited { base = min(1, base + favoriteBonus) }
        return clamp01(base)
    }

    /// 时间衰减因子：decay = 0.5^(Δdays / 30)。
    static func decayFactor(for record: ReadingInterestRecord, now: Date = Date()) -> Double {
        let days = max(0, now.timeIntervalSince(record.lastReadAt) / 86_400)
        return pow(0.5, days / decayHalfLifeDays)
    }

    /// 衰减后单篇得分。
    static func decayedScore(for record: ReadingInterestRecord, now: Date = Date()) -> Double {
        rawScore(for: record) * decayFactor(for: record, now: now)
    }

    /// 类目指数：成员衰减后得分均值；按指数降序，「其他」强制置底弱化。
    static func categoryIndex(
        classifications: [Int: ArticleClassification],
        records: [Int: ReadingInterestRecord],
        taxonomy: CategoryTaxonomy,
        now: Date = Date()
    ) -> [CategoryInterestIndex] {
        var members: [String: [ReadingInterestRecord]] = [:]
        for (articleID, record) in records {
            guard let cls = classifications[articleID] else { continue }
            members[cls.categoryID, default: []].append(record)
        }
        let otherID = ArticleCategory.other.id
        var result: [CategoryInterestIndex] = []
        for category in taxonomy.categories {
            let recs = members[category.id] ?? []
            let score = recs.isEmpty ? 0 : recs.map { decayedScore(for: $0, now: now) }.reduce(0, +) / Double(recs.count)
            result.append(
                CategoryInterestIndex(
                    category: category,
                    score: score,
                    memberCount: recs.count,
                    isLowSample: recs.count < lowSampleThreshold
                )
            )
        }
        let otherRecs = members[otherID] ?? []
        let otherScore = otherRecs.isEmpty ? 0 : otherRecs.map { decayedScore(for: $0, now: now) }.reduce(0, +) / Double(otherRecs.count)
        result.append(
            CategoryInterestIndex(
                category: .other,
                score: otherScore,
                memberCount: otherRecs.count,
                isLowSample: otherRecs.count < lowSampleThreshold
            )
        )
        result.sort { lhs, rhs in
            if lhs.category.isOther { return false }
            if rhs.category.isOther { return true }
            return lhs.score > rhs.score
        }
        return result
    }
}

/// 类目指数展示模型。
struct CategoryInterestIndex: Identifiable, Sendable {
    let category: ArticleCategory
    let score: Double
    let memberCount: Int
    let isLowSample: Bool
    var id: String { category.id }
}
