import XCTest
@testable import DailyReader

@MainActor
final class ArticleDetailViewModelTests: XCTestCase {
    func testClassificationTextLimitsLongArticleInput() {
        let html = (1...2_000)
            .map { "<p>第 \($0) 段用于分类的正文内容。</p>" }
            .joined()

        let text = ArticleDetailViewModel.classificationText(from: html)

        XCTAssertLessThanOrEqual(text.count, 6_000)
    }

    func testLoadDetailUsesDetailShareURLFirst() async {
        let viewModel = ArticleDetailViewModel(
            story: StorySummary(id: 1, title: "列表标题", url: "https://example.com/list"),
            repository: makeRepository(service: MockDailyService(), cacheStore: DiskCacheStore(rootURL: temporaryRoot()))
        )

        await viewModel.load()

        XCTAssertEqual(viewModel.shareURL?.absoluteString, "https://example.com/1")
        XCTAssertEqual(viewModel.shareTitle, "第一篇日报")
    }

    func testShareIsUnavailableBeforeDetailFinishesLoading() {
        let viewModel = ArticleDetailViewModel(
            story: StorySummary(id: 1, title: "列表标题", url: "https://example.com/list"),
            repository: makeRepository(service: MockDailyService(), cacheStore: DiskCacheStore(rootURL: temporaryRoot()))
        )

        XCTAssertNil(viewModel.shareURL)
    }

    func testLoadDetailFallsBackToDetailURLBeforeListURL() async {
        let service = MockDailyService()
        service.detailResult = .success(
            ArticleDetail(
                id: 1,
                title: "第一篇日报",
                body: "<p>正文</p>",
                shareURL: nil,
                url: "https://daily.example.com/detail-url"
            )
        )
        let viewModel = ArticleDetailViewModel(
            story: StorySummary(id: 1, title: "列表标题", url: "https://example.com/list"),
            repository: makeRepository(service: service, cacheStore: DiskCacheStore(rootURL: temporaryRoot()))
        )

        await viewModel.load()

        XCTAssertEqual(viewModel.shareURL?.absoluteString, "https://daily.example.com/detail-url")
    }

    func testLoadDetailFallsBackToCachedDetail() async {
        let store = DiskCacheStore(rootURL: temporaryRoot())
        await store.saveDetail(.fixture)
        let service = MockDailyService()
        service.detailResult = .failure(APIError.transport("offline"))
        let viewModel = ArticleDetailViewModel(
            story: StorySummary(id: 1, title: "列表标题"),
            repository: makeRepository(service: service, cacheStore: store)
        )

        await viewModel.load()

        XCTAssertNil(viewModel.bannerMessage)
        XCTAssertTrue(viewModel.phase.isCacheLoaded)
    }

    func testLoadDetailFailureWithoutCacheShowsRetryableError() async {
        let service = MockDailyService()
        service.detailResult = .failure(APIError.transport("offline"))
        let viewModel = ArticleDetailViewModel(
            story: StorySummary(id: 1, title: "列表标题"),
            repository: makeRepository(service: service, cacheStore: DiskCacheStore(rootURL: temporaryRoot()))
        )

        await viewModel.load()

        XCTAssertEqual(viewModel.phase, .failed("文章加载失败，请稍后重试"))
        XCTAssertNil(viewModel.shareURL)
    }

    func testMissingShareLinkDoesNotProduceFallbackGarbageURL() async {
        let service = MockDailyService()
        service.detailResult = .success(
            ArticleDetail(
                id: 1,
                title: "无分享链接文章",
                body: "<p>正文</p>",
                shareURL: nil,
                url: nil
            )
        )
        let viewModel = ArticleDetailViewModel(
            story: StorySummary(id: 1, title: "列表标题", url: nil),
            repository: makeRepository(service: service, cacheStore: DiskCacheStore(rootURL: temporaryRoot()))
        )

        await viewModel.load()

        XCTAssertNil(viewModel.shareURL)
    }

    func testInvalidShareLinkIsRejected() async {
        let service = MockDailyService()
        service.detailResult = .success(
            ArticleDetail(
                id: 1,
                title: "无效分享链接文章",
                body: "<p>正文</p>",
                shareURL: "javascript:alert(1)",
                url: "not-a-valid-article-url"
            )
        )
        let viewModel = ArticleDetailViewModel(
            story: StorySummary(id: 1, title: "列表标题", url: "ftp://example.com/story"),
            repository: makeRepository(service: service, cacheStore: DiskCacheStore(rootURL: temporaryRoot()))
        )

        await viewModel.load()

        XCTAssertNil(viewModel.shareURL)
    }

    func testShareTitleUsesDisplayedDetailTitle() async {
        let service = MockDailyService()
        service.detailResult = .success(
            ArticleDetail(
                id: 1,
                title: "详情标题",
                body: "<p>正文</p>",
                shareURL: "https://example.com/detail-title"
            )
        )
        let viewModel = ArticleDetailViewModel(
            story: StorySummary(id: 1, title: "列表标题", url: "https://example.com/list-title"),
            repository: makeRepository(service: service, cacheStore: DiskCacheStore(rootURL: temporaryRoot()))
        )

        await viewModel.load()

        XCTAssertEqual(viewModel.shareTitle, "详情标题")
    }

    func testLoadMetricsSeparatesDailyAndUniqueOriginalAnswerValues() async {
        let service = MockDailyService()
        service.detailResult = .success(
            ArticleDetail(
                id: 1,
                title: "带原回答的文章",
                body: "<a class='originUrl' href='https://www.zhihu.com/question/123/answer/456' hidden></a><p>正文</p>",
                shareURL: "https://example.com/1"
            )
        )
        let repository = makeRepository(
            service: service,
            cacheStore: DiskCacheStore(rootURL: temporaryRoot())
        )
        let viewModel = ArticleDetailViewModel(
            story: StorySummary(id: 1, title: "列表标题"),
            repository: repository,
            metricsRepository: repository
        )

        await viewModel.load()

        XCTAssertEqual(viewModel.storyMetrics, .fixture)
        XCTAssertEqual(viewModel.originalAnswerMetrics, .fixture)
        XCTAssertEqual(service.storyMetricsCallCount, 1)
        XCTAssertEqual(service.answerMetricsCallCount, 1)
    }

    func testMultipleOriginalAnswersDoNotProduceMisleadingAggregateMetrics() async {
        let service = MockDailyService()
        service.detailResult = .success(
            ArticleDetail(
                id: 1,
                title: "回答合集",
                body: """
                <a href='https://www.zhihu.com/question/123/answer/456'>回答一</a>
                <a href='https://www.zhihu.com/question/789/answer/999'>回答二</a>
                """,
                shareURL: "https://example.com/1"
            )
        )
        let repository = makeRepository(
            service: service,
            cacheStore: DiskCacheStore(rootURL: temporaryRoot())
        )
        let viewModel = ArticleDetailViewModel(
            story: StorySummary(id: 1, title: "列表标题"),
            repository: repository,
            metricsRepository: repository
        )

        await viewModel.load()

        XCTAssertEqual(viewModel.storyMetrics, .fixture)
        XCTAssertNil(viewModel.originalAnswerMetrics)
        XCTAssertEqual(service.answerMetricsCallCount, 0)
    }

    func testMetricsFailureDoesNotChangeLoadedArticlePhase() async {
        let service = MockDailyService()
        service.storyMetricsResult = .failure(APIError.transport("metrics offline"))
        service.answerMetricsResult = .failure(APIError.transport("metrics offline"))
        service.detailResult = .success(
            ArticleDetail(
                id: 1,
                title: "正文仍可阅读",
                body: "<a href='https://www.zhihu.com/question/123/answer/456'>原回答</a><p>正文</p>",
                shareURL: "https://example.com/1"
            )
        )
        let repository = makeRepository(
            service: service,
            cacheStore: DiskCacheStore(rootURL: temporaryRoot())
        )
        let viewModel = ArticleDetailViewModel(
            story: StorySummary(id: 1, title: "列表标题"),
            repository: repository,
            metricsRepository: repository
        )

        await viewModel.load()

        if case .loaded(let detail, .network) = viewModel.phase {
            XCTAssertEqual(detail.title, "正文仍可阅读")
        } else {
            XCTFail("Expected article to remain loaded when optional metrics fail")
        }
        XCTAssertNil(viewModel.storyMetrics)
        XCTAssertNil(viewModel.originalAnswerMetrics)
    }

    func testOriginalAnswerParserAcceptsRepeatedSameAnswerButRejectsInvalidLinks() {
        let repeated = """
        <a class='originUrl' href='https://www.zhihu.com/question/123/answer/456'>来源</a>
        <a href='https://www.zhihu.com/question/123/answer/456'>再次查看</a>
        """
        XCTAssertEqual(OriginalAnswerReferenceParser.uniqueAnswerID(in: repeated), 456)
        XCTAssertNil(
            OriginalAnswerReferenceParser.uniqueAnswerID(
                in: "<a href='https://www.zhihu.com/question/None/answer/None'>无来源</a>"
            )
        )
    }

    func testAutomaticReadQualificationOnlyAppliesToDailySource() {
        XCTAssertTrue(ArticleDetailSource.daily.enablesAutomaticReadQualification)
        XCTAssertFalse(ArticleDetailSource.favorites.enablesAutomaticReadQualification)
        XCTAssertFalse(ArticleDetailSource.coldPalace.enablesAutomaticReadQualification)
        XCTAssertFalse(ArticleDetailSource.read.enablesAutomaticReadQualification)
    }

    func testReadQualificationRequiresTenActiveSeconds() {
        var now = ContinuousClock.now
        let timer = ReadQualificationTimer(now: { now })
        timer.prepare(for: 1)

        timer.resume()
        now += .seconds(9.999)
        XCTAssertFalse(timer.qualifyIfNeeded())
        XCTAssertFalse(timer.hasQualified)

        now += .milliseconds(1)
        XCTAssertTrue(timer.qualifyIfNeeded())
        XCTAssertTrue(timer.hasQualified)
    }

    func testReadQualificationAccumulatesAcrossForegroundSessions() {
        var now = ContinuousClock.now
        let timer = ReadQualificationTimer(now: { now })
        timer.prepare(for: 1)

        timer.resume()
        now += .seconds(6)
        XCTAssertFalse(timer.pause())

        now += .seconds(30)
        XCTAssertFalse(timer.qualifyIfNeeded(), "后台时间不应计入阅读时长")

        timer.resume()
        now += .seconds(4)
        XCTAssertTrue(timer.qualifyIfNeeded())
    }

    func testReadQualificationOnlyReportsOnce() {
        var now = ContinuousClock.now
        let timer = ReadQualificationTimer(now: { now })
        timer.prepare(for: 1)

        timer.resume()
        now += .seconds(10)
        XCTAssertTrue(timer.qualifyIfNeeded())
        XCTAssertFalse(timer.qualifyIfNeeded())
        XCTAssertFalse(timer.pause())
    }

    func testReadQualificationResetsForAnotherStory() {
        var now = ContinuousClock.now
        let timer = ReadQualificationTimer(now: { now })
        timer.prepare(for: 1)

        timer.resume()
        now += .seconds(7)
        XCTAssertFalse(timer.pause())

        timer.prepare(for: 2)
        timer.resume()
        now += .seconds(3)
        XCTAssertFalse(timer.qualifyIfNeeded(), "不同文章之间不应共享阅读时长")

        now += .seconds(7)
        XCTAssertTrue(timer.qualifyIfNeeded())
    }

    func testReadingProgressIsClampedToScrollableRange() {
        XCTAssertEqual(
            ArticleDetailView.progress(offset: -40, contentHeight: 1_600, viewportHeight: 800),
            0,
            accuracy: 0.001
        )
        XCTAssertEqual(
            ArticleDetailView.progress(offset: 400, contentHeight: 1_600, viewportHeight: 800),
            0.5,
            accuracy: 0.001
        )
        XCTAssertEqual(
            ArticleDetailView.progress(offset: 1_200, contentHeight: 1_600, viewportHeight: 800),
            1,
            accuracy: 0.001
        )
    }

    func testReadingProgressHandlesContentShorterThanViewport() {
        XCTAssertEqual(
            ArticleDetailView.progress(offset: 0, contentHeight: 500, viewportHeight: 800),
            0,
            accuracy: 0.001
        )
    }

    func testReadingControlOnlyShowsAfterVisibilityThreshold() {
        XCTAssertFalse(ArticleDetailView.shouldShowReadingControl(offset: 0))
        XCTAssertFalse(
            ArticleDetailView.shouldShowReadingControl(
                offset: ArticleDetailView.readingControlVisibilityThreshold
            )
        )
        XCTAssertTrue(
            ArticleDetailView.shouldShowReadingControl(
                offset: ArticleDetailView.readingControlVisibilityThreshold + 1
            )
        )
    }

    func testEmptyBodyStillLoadsDetailForUnavailableContentState() async {
        let service = MockDailyService()
        service.detailResult = .success(
            ArticleDetail(
                id: 1,
                title: "空正文",
                body: "",
                shareURL: "https://example.com/empty"
            )
        )
        let viewModel = ArticleDetailViewModel(
            story: StorySummary(id: 1, title: "列表标题"),
            repository: makeRepository(service: service, cacheStore: DiskCacheStore(rootURL: temporaryRoot()))
        )

        await viewModel.load()

        if case .loaded(let detail, .network) = viewModel.phase {
            XCTAssertEqual(detail.body, "")
        } else {
            XCTFail("Expected loaded detail with empty body fallback content state")
        }
    }

    private func temporaryRoot() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }
}

private extension ArticleDetailPhase {
    var isCacheLoaded: Bool {
        if case .loaded(_, .cache) = self { return true }
        return false
    }
}
