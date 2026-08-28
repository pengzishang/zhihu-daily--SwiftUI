import XCTest
@testable import DailyReader

final class InterestIndexEngineTests: XCTestCase {
    private func record(
        articleID: Int = 1,
        dwellSeconds: Double = 0,
        maxScrollPercent: Double = 0,
        readCount: Int = 0,
        isFavorited: Bool = false,
        isHidden: Bool = false
    ) -> ReadingInterestRecord {
        ReadingInterestRecord(
            articleID: articleID,
            dwellSeconds: dwellSeconds,
            maxScrollPercent: maxScrollPercent,
            readCount: readCount,
            isFavorited: isFavorited,
            isHidden: isHidden
        )
    }

    private func taxonomy(with categories: [ArticleCategory]) -> CategoryTaxonomy {
        CategoryTaxonomy(categories: categories, isFrozen: true)
    }

    func testHiddenStoryScoresZero() {
        let value = InterestIndexEngine.rawScore(for: record(isHidden: true))
        XCTAssertEqual(value, 0, accuracy: 0.0001)
    }

    func testFullEngagementWithoutFavoriteReachesOne() {
        let value = InterestIndexEngine.rawScore(
            for: record(dwellSeconds: 180, maxScrollPercent: 1, readCount: 5)
        )
        XCTAssertEqual(value, 1.0, accuracy: 0.0001)
    }

    func testFavoriteAddsBonus() {
        let base = InterestIndexEngine.rawScore(
            for: record(dwellSeconds: 180, maxScrollPercent: 1, readCount: 5)
        )
        var favorited = record(dwellSeconds: 180, maxScrollPercent: 1, readCount: 5)
        favorited.isFavorited = true
        let withFavorite = InterestIndexEngine.rawScore(for: favorited)
        XCTAssertEqual(base, 1.0, accuracy: 0.0001)
        XCTAssertEqual(withFavorite, 1.0, accuracy: 0.0001)
        XCTAssertGreaterThanOrEqual(withFavorite, base)
    }

    func testDwellIsNormalizedAndCapped() {
        let half = InterestIndexEngine.rawScore(for: record(dwellSeconds: 90, maxScrollPercent: 0, readCount: 0))
        let full = InterestIndexEngine.rawScore(for: record(dwellSeconds: 400, maxScrollPercent: 0, readCount: 0))
        XCTAssertEqual(half, 0.2, accuracy: 0.0001)
        XCTAssertEqual(full, 0.4, accuracy: 0.0001)
    }

    func testDecayHalvesAfterThirtyDays() {
        let rec = record(lastReadAt: Date())
        let now = rec.lastReadAt.addingTimeInterval(30 * 86_400)
        let factor = InterestIndexEngine.decayFactor(for: rec, now: now)
        XCTAssertEqual(factor, 0.5, accuracy: 0.01)
    }

    func testDecayPreservesRecentReading() {
        let rec = record(lastReadAt: Date())
        let factor = InterestIndexEngine.decayFactor(for: rec, now: rec.lastReadAt)
        XCTAssertEqual(factor, 1.0, accuracy: 0.0001)
    }

    func testCategoryIndexSortsDescendingAndPinsOtherToBottom() {
        let tech = ArticleCategory(id: "tech", name: "科技", order: 0)
        let business = ArticleCategory(id: "business", name: "商业", order: 1)
        let tax = taxonomy(with: [tech, business])

        var classifications: [Int: ArticleClassification] = [:]
        var records: [Int: ReadingInterestRecord] = [:]
        for id in 1...3 {
            classifications[id] = ArticleClassification(articleID: id, categoryID: "tech", confidence: 1, source: .remote)
            records[id] = record(articleID: id, dwellSeconds: 180, maxScrollPercent: 1, readCount: 5)
        }
        classifications[4] = ArticleClassification(articleID: 4, categoryID: "business", confidence: 1, source: .remote)
        records[4] = record(articleID: 4, dwellSeconds: 180, maxScrollPercent: 1, readCount: 5)

        let result = InterestIndexEngine.categoryIndex(
            classifications: classifications,
            records: records,
            taxonomy: tax
        )

        XCTAssertEqual(result.count, 3)
        XCTAssertTrue(result.last?.category.isOther == true)
        XCTAssertEqual(result.first?.category.id, "tech")
        XCTAssertEqual(result.first?.score, 1.0, accuracy: 0.0001)
        XCTAssertEqual(result.first?.isLowSample, false)
    }

    func testCategoryIndexFlagsLowSample() {
        let tech = ArticleCategory(id: "tech", name: "科技", order: 0)
        let tax = taxonomy(with: [tech])

        var classifications: [Int: ArticleClassification] = [:]
        var records: [Int: ReadingInterestRecord] = [:]
        classifications[1] = ArticleClassification(articleID: 1, categoryID: "tech", confidence: 1, source: .remote)
        records[1] = record(articleID: 1, dwellSeconds: 180, maxScrollPercent: 1, readCount: 5)

        let result = InterestIndexEngine.categoryIndex(
            classifications: classifications,
            records: records,
            taxonomy: tax
        )

        let techEntry = result.first { $0.category.id == "tech" }
        XCTAssertEqual(techEntry?.memberCount, 1)
        XCTAssertTrue(techEntry?.isLowSample == true)
    }

    // MARK: - 边界用例补充

    /// (a) 单篇各信号均为 0 且未收藏/未隐藏时，score 必须为 0。
    func testAllSignalsZeroScoresZero() {
        let value = InterestIndexEngine.rawScore(for: record())
        XCTAssertEqual(value, 0, accuracy: 0.0001)
    }

    /// (b) 仅收藏（未读）时，分数应为 +0.25（clamp 后）。
    func testFavoriteOnlyYieldsQuarterBonus() {
        let value = InterestIndexEngine.rawScore(for: record(isFavorited: true))
        XCTAssertEqual(value, 0.25, accuracy: 0.0001)
    }

    /// (d) 停留=180s 与 360s 归一结果相同（封顶），180s 时 0.4 权重满格。
    func testDwellCeilingSameFor180And360() {
        let atCeiling = InterestIndexEngine.rawScore(for: record(dwellSeconds: 180))
        let beyondCeiling = InterestIndexEngine.rawScore(for: record(dwellSeconds: 360))
        XCTAssertEqual(atCeiling, beyondCeiling, accuracy: 0.0001)
        XCTAssertEqual(atCeiling, 0.4, accuracy: 0.0001)
    }

    /// (e) 阅读次数 5 次与 10 次加分相同（封顶），5 次时 0.2 权重满格。
    func testReadCountCapSameForFiveAndTen() {
        let five = InterestIndexEngine.rawScore(for: record(readCount: 5))
        let ten = InterestIndexEngine.rawScore(for: record(readCount: 10))
        XCTAssertEqual(five, ten, accuracy: 0.0001)
        XCTAssertEqual(five, 0.2, accuracy: 0.0001)
    }

    /// (f) 衰减：lastReadAt 距今 60 天的 decayFactor ≈ 0.25（0/30/60 → 1/0.5/0.25）。
    func testDecayAfterSixtyDaysIsQuarter() {
        let rec = record(lastReadAt: Date())
        let now = rec.lastReadAt.addingTimeInterval(60 * 86_400)
        let factor = InterestIndexEngine.decayFactor(for: rec, now: now)
        XCTAssertEqual(factor, 0.25, accuracy: 0.01)
    }

    /// (g) 类目聚合：3 篇标「样本充足」、2 篇标「样本不足」的边界区分。
    func testCategoryIndexLowSampleBoundaryThreeVsTwo() {
        let tech = ArticleCategory(id: "tech", name: "科技", order: 0)
        let business = ArticleCategory(id: "business", name: "商业", order: 1)
        let tax = taxonomy(with: [tech, business])

        var classifications: [Int: ArticleClassification] = [:]
        var records: [Int: ReadingInterestRecord] = [:]
        for id in 1...3 {
            classifications[id] = ArticleClassification(articleID: id, categoryID: "tech", confidence: 1, source: .remote)
            records[id] = record(articleID: id, dwellSeconds: 180, maxScrollPercent: 1, readCount: 5)
        }
        classifications[4] = ArticleClassification(articleID: 4, categoryID: "business", confidence: 1, source: .remote)
        records[4] = record(articleID: 4, dwellSeconds: 180, maxScrollPercent: 1, readCount: 5)
        classifications[5] = ArticleClassification(articleID: 5, categoryID: "business", confidence: 1, source: .remote)
        records[5] = record(articleID: 5, dwellSeconds: 180, maxScrollPercent: 1, readCount: 5)

        let result = InterestIndexEngine.categoryIndex(
            classifications: classifications,
            records: records,
            taxonomy: tax
        )
        let techEntry = result.first { $0.category.id == "tech" }
        let businessEntry = result.first { $0.category.id == "business" }
        XCTAssertEqual(techEntry?.memberCount, 3)
        XCTAssertFalse(techEntry?.isLowSample ?? true)
        XCTAssertEqual(businessEntry?.memberCount, 2)
        XCTAssertTrue(businessEntry?.isLowSample == true)
    }

    /// (h) 「其他」聚合后排序恒置底，即便其指数高于真实类目。
    func testOtherPinnedToBottomEvenWithHighestScore() {
        let tech = ArticleCategory(id: "tech", name: "科技", order: 0)
        let business = ArticleCategory(id: "business", name: "商业", order: 1)
        let tax = taxonomy(with: [tech, business])

        var classifications: [Int: ArticleClassification] = [:]
        var records: [Int: ReadingInterestRecord] = [:]
        for id in 1...3 {
            classifications[id] = ArticleClassification(articleID: id, categoryID: "tech", confidence: 1, source: .remote)
            records[id] = record(articleID: id, dwellSeconds: 90, maxScrollPercent: 0.5, readCount: 0)
        }
        classifications[99] = ArticleClassification(articleID: 99, categoryID: ArticleCategory.other.id, confidence: 1, source: .remote)
        records[99] = record(articleID: 99, dwellSeconds: 180, maxScrollPercent: 1, readCount: 5)

        let result = InterestIndexEngine.categoryIndex(
            classifications: classifications,
            records: records,
            taxonomy: tax
        )
        XCTAssertTrue(result.last?.category.isOther == true)
        XCTAssertEqual(result.last?.score, 1.0, accuracy: 0.0001)
        let firstScore = result.first?.score ?? 0
        let lastScore = result.last?.score ?? 0
        XCTAssertLessThan(firstScore, lastScore)
    }

    /// 引擎常量需与规格严丝合缝（static let）。
    func testEngineConstantsMatchSpec() {
        XCTAssertEqual(InterestIndexEngine.dwellCeilingSeconds, 180, accuracy: 0.0001)
        XCTAssertEqual(InterestIndexEngine.decayHalfLifeDays, 30, accuracy: 0.0001)
        XCTAssertEqual(InterestIndexEngine.favoriteBonus, 0.25, accuracy: 0.0001)
        XCTAssertEqual(InterestIndexEngine.readCountFullMark, 5, accuracy: 0.0001)
        XCTAssertEqual(InterestIndexEngine.lowSampleThreshold, 3)
    }
}
