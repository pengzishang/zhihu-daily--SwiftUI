import XCTest
@testable import DailyReader

@MainActor
final class ClassificationServiceTests: XCTestCase {
    private struct StubCredentialStore: AICredentialStoring {
        func loadAPIKey() throws -> String? { nil }
        func saveAPIKey(_ value: String) throws {}
        func deleteAPIKey() throws {}
        func loadAPIKey(providerID: String) throws -> String? { nil }
        func saveAPIKey(_ value: String, providerID: String) throws {}
        func deleteAPIKey(providerID: String) throws {}
    }

    private func makeService() -> ArticleClassificationService {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let store = AIConfigurationStore(defaults: defaults, credentialStore: StubCredentialStore())
        return ArticleClassificationService(configurationStore: store)
    }

    private func taxonomy() -> CategoryTaxonomy {
        CategoryTaxonomy(categories: [ArticleCategory(id: "tech", name: "科技")], isFrozen: true)
    }

    func testClassifyWithoutConfigurationReturnsLocalFallback() async {
        let service = makeService()
        let result = await service.classify(
            articleID: 1,
            title: "AI 芯片取得新突破",
            text: "关于人工智能芯片的研究",
            taxonomy: taxonomy()
        )
        XCTAssertEqual(result.source, .local)
    }

    func testParseReturnsOtherForOutOfSetCategory() {
        let service = makeService()
        let parsed = service.parse(
            "{\"category\":\"美食\",\"confidence\":0.9}",
            taxonomy: taxonomy(),
            articleID: 1
        )
        XCTAssertEqual(parsed?.categoryID, ArticleCategory.other.id)
    }

    func testParseReturnsMatchedCategoryForInSetName() {
        let service = makeService()
        let parsed = service.parse(
            "{\"category\":\"科技\",\"confidence\":0.9}",
            taxonomy: taxonomy(),
            articleID: 1
        )
        XCTAssertEqual(parsed?.categoryID, "tech")
    }

    func testParseReturnsOtherForLowConfidence() {
        let service = makeService()
        let parsed = service.parse(
            "{\"category\":\"科技\",\"confidence\":0.2}",
            taxonomy: taxonomy(),
            articleID: 1
        )
        XCTAssertEqual(parsed?.categoryID, ArticleCategory.other.id)
    }

    func testLocalFallbackMatchesKeyword() {
        let service = makeService()
        let result = service.localFallback(
            articleID: 1,
            title: "人工智能芯片发布",
            text: "新款手机处理器采用先进半导体技术"
        )
        XCTAssertEqual(result.categoryID, "tech")
    }

    func testLocalFallbackReturnsOtherWithoutMatch() {
        let service = makeService()
        let result = service.localFallback(
            articleID: 1,
            title: "随机标题",
            text: "一些毫不相关的文字内容"
        )
        XCTAssertEqual(result.categoryID, ArticleCategory.other.id)
    }

    // MARK: - 边界用例补充

    /// (i) 置信度恰好等于阈值 0.5（不小于 0.5）时，应保留命中类目而非归「其他」。
    func testParseKeepsCategoryAtExactConfidenceThreshold() {
        let service = makeService()
        let parsed = service.parse(
            "{\"category\":\"科技\",\"confidence\":0.5}",
            taxonomy: taxonomy(),
            articleID: 1
        )
        XCTAssertEqual(parsed?.categoryID, "tech")
    }

    /// (i) 置信度低于阈值归「其他」的边界（0.49 < 0.5）。
    func testParseReturnsOtherForJustBelowThreshold() {
        let service = makeService()
        let parsed = service.parse(
            "{\"category\":\"科技\",\"confidence\":0.49}",
            taxonomy: taxonomy(),
            articleID: 1
        )
        XCTAssertEqual(parsed?.categoryID, ArticleCategory.other.id)
    }

    /// (j) 关键词兜底在离线时给出可预期类别（明确命中词）。
    func testLocalFallbackPredictableForKnownKeyword() {
        let service = makeService()
        let result = service.localFallback(
            articleID: 2,
            title: "股票市场今日大跌",
            text: "投资者担忧经济与金融风险"
        )
        XCTAssertEqual(result.categoryID, "business")
        XCTAssertEqual(result.source, .local)
    }

    /// 置信度阈值常量须为 0.5（规格要求 static let）。
    func testConfidenceThresholdConstantIsPointFive() {
        XCTAssertEqual(ArticleClassificationService.confidenceThreshold, 0.5, accuracy: 0.0001)
    }
}
