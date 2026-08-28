import XCTest
@testable import DailyReader

@MainActor
final class HomeViewModelTests: XCTestCase {
    private let persistedStoryStateKeys = [
        "DailyReader.readStoryIDs",
        "DailyReader.hiddenStories",
        "DailyReader.favoriteStories",
        "DailyReader.readStories"
    ]

    override func setUp() {
        super.setUp()
        resetPersistedStoryState()
    }

    override func tearDown() {
        resetPersistedStoryState()
        super.tearDown()
    }

    private func resetPersistedStoryState() {
        let readingStateBackup = KeychainReadingStateBackup()
        for key in persistedStoryStateKeys {
            UserDefaults.standard.removeObject(forKey: key)
            try? readingStateBackup.delete(account: key)
        }
    }

    func testLoadLatestShowsNetworkContent() async {
        let service = MockDailyService()
        let viewModel = HomeViewModel(repository: makeRepository(service: service, cacheStore: DiskCacheStore(rootURL: temporaryRoot())))

        await viewModel.load()

        XCTAssertEqual(viewModel.topStories.count, 1)
        XCTAssertEqual(viewModel.sections.first?.stories.count, 2)
        XCTAssertEqual(viewModel.phase, .loaded(.network))
    }

    func testNetworkFailureFallsBackToCachedLatest() async {
        let store = DiskCacheStore(rootURL: temporaryRoot())
        await store.saveHomeFeed(sections: [DailySection(date: DailyResponse.fixture.date, stories: DailyResponse.fixture.stories)], topStories: DailyResponse.fixture.topStories, historyCursor: DailyResponse.fixture.date)
        let service = MockDailyService()
        service.latestResult = .failure(APIError.transport("offline"))
        let viewModel = HomeViewModel(repository: makeRepository(service: service, cacheStore: store))

        await viewModel.load()

        XCTAssertEqual(viewModel.sections.first?.stories.count, 2)
        XCTAssertEqual(viewModel.bannerMessage, "当前离线，正在显示缓存内容")
        XCTAssertTrue(viewModel.phase.isCacheLoaded)
    }

    func testLoadLatestWithCacheAndNetworkSuccess() async {
        let store = DiskCacheStore(rootURL: temporaryRoot())
        await store.saveHomeFeed(sections: [DailySection(date: DailyResponse.fixture.date, stories: DailyResponse.fixture.stories)], topStories: DailyResponse.fixture.topStories, historyCursor: DailyResponse.fixture.date)

        let service = MockDailyService()
        let networkResponse = DailyResponse(
            date: "20260621",
            stories: [
                StorySummary(id: 1, title: "第一篇日报"),
                StorySummary(id: 2, title: "第二篇日报"),
                StorySummary(id: 3, title: "第三篇日报新加入")
            ],
            topStories: [
                TopStory(id: 1, title: "顶部故事")
            ]
        )
        service.latestResult = .success(networkResponse)

        let viewModel = HomeViewModel(repository: makeRepository(service: service, cacheStore: store))

        await viewModel.load()

        XCTAssertEqual(viewModel.sections.first?.stories.count, 3)
        XCTAssertEqual(viewModel.sections.first?.stories[0].id, 3)
        XCTAssertEqual(viewModel.phase, .loaded(.network))
        XCTAssertNil(viewModel.bannerMessage)
    }

    func testNetworkFailureWithoutCacheShowsRetryableErrorState() async {
        let service = MockDailyService()
        service.latestResult = .failure(APIError.transport("offline"))
        let viewModel = HomeViewModel(repository: makeRepository(service: service, cacheStore: DiskCacheStore(rootURL: temporaryRoot())))

        await viewModel.load()

        XCTAssertEqual(viewModel.phase, .failed("网络不可用，请检查连接后重试"))
        XCTAssertTrue(viewModel.sections.isEmpty)
        XCTAssertNil(viewModel.bannerMessage)
    }

    func testRefreshFailureWithoutCacheKeepsVisibleContent() async {
        let service = MockDailyService()
        let viewModel = HomeViewModel(repository: makeRepository(service: service, cacheStore: DiskCacheStore(rootURL: temporaryRoot())))

        await viewModel.load()
        service.latestResult = .failure(APIError.transport("offline"))
        await viewModel.refresh()

        XCTAssertEqual(viewModel.sections.flatMap(\.stories).map(\.id), [1, 2])
        XCTAssertEqual(viewModel.bannerMessage, "刷新失败，已保留上次内容")
    }

    func testRefreshFailureKeepsLoadedHistorySections() async {
        let service = MockDailyService()
        let viewModel = HomeViewModel(repository: makeRepository(service: service, cacheStore: DiskCacheStore(rootURL: temporaryRoot())))

        await viewModel.load()
        await viewModel.loadMore()
        service.latestResult = .failure(APIError.transport("offline"))
        await viewModel.refresh()

        XCTAssertEqual(viewModel.sections.map(\.date), ["20260621", "20260620"])
        XCTAssertEqual(viewModel.sections.flatMap(\.stories).map(\.id), [1, 2, 3])
        XCTAssertEqual(viewModel.bannerMessage, "刷新失败，已保留上次内容")
    }

    func testLoadMoreDeduplicatesStories() async {
        let service = MockDailyService()
        let viewModel = HomeViewModel(repository: makeRepository(service: service, cacheStore: DiskCacheStore(rootURL: temporaryRoot())))

        await viewModel.load()
        await viewModel.loadMore()

        XCTAssertEqual(viewModel.sections.flatMap(\.stories).map(\.id), [1, 2, 3])
        XCTAssertEqual(viewModel.historyLoadState, .idle)
    }

    func testLoadMoreFailureKeepsExistingStoriesAndExposesRetryState() async {
        let service = MockDailyService()
        service.beforeResult = .failure(APIError.httpStatus(502))
        let viewModel = HomeViewModel(repository: makeRepository(service: service, cacheStore: DiskCacheStore(rootURL: temporaryRoot())))

        await viewModel.load()
        await viewModel.loadMore()

        XCTAssertEqual(viewModel.sections.flatMap(\.stories).map(\.id), [1, 2])
        XCTAssertEqual(viewModel.historyLoadState, .failed("加载历史失败，已保留当前内容"))
        XCTAssertNil(viewModel.bannerMessage)
    }

    func testLoadMoreFailureFallsBackToCachedPreviousDailyList() async {
        let store = DiskCacheStore(rootURL: temporaryRoot())
        await store.saveDaily(.historyFixture)
        let service = MockDailyService()
        service.beforeResult = .failure(APIError.transport("offline"))
        let viewModel = HomeViewModel(repository: makeRepository(service: service, cacheStore: store))

        await viewModel.load()
        await viewModel.loadMore()

        XCTAssertEqual(viewModel.sections.map(\.date), ["20260621", "20260620"])
        XCTAssertEqual(viewModel.sections.flatMap(\.stories).map(\.id), [1, 2, 3])
        XCTAssertEqual(viewModel.historyLoadState, .idle)
        XCTAssertNil(viewModel.bannerMessage)
    }

    func testThresholdUsesVisibleStories() async {
        let readIDsKey = "DailyReader.readStoryIDs"
        let readStoriesKey = "DailyReader.readStories"
        UserDefaults.standard.set([2], forKey: readIDsKey)
        UserDefaults.standard.removeObject(forKey: readStoriesKey)
        defer {
            UserDefaults.standard.removeObject(forKey: readIDsKey)
            UserDefaults.standard.removeObject(forKey: readStoriesKey)
        }

        let service = MockDailyService()
        let viewModel = HomeViewModel(repository: makeRepository(
            service: service,
            cacheStore: DiskCacheStore(rootURL: temporaryRoot())
        ))

        await viewModel.load()

        XCTAssertEqual(viewModel.visibleSections.flatMap(\.stories).map(\.id), [1])
        XCTAssertEqual(viewModel.thresholdStoryID, 1)
    }

    func testThresholdStartsPrefetchWithEightVisibleStoriesRemaining() async {
        let readIDsKey = "DailyReader.readStoryIDs"
        UserDefaults.standard.set([999], forKey: readIDsKey)
        defer { UserDefaults.standard.removeObject(forKey: readIDsKey) }

        let service = MockDailyService()
        service.latestResult = .success(DailyResponse(
            date: "20260621",
            stories: (1...15).map { StorySummary(id: $0, title: "日报 \($0)") }
        ))
        let viewModel = HomeViewModel(repository: makeRepository(
            service: service,
            cacheStore: DiskCacheStore(rootURL: temporaryRoot())
        ))

        await viewModel.load()

        XCTAssertEqual(viewModel.thresholdStoryID, 7)
        let visibleIDs = viewModel.visibleSections.flatMap(\.stories).map(\.id)
        let thresholdIndex = try? XCTUnwrap(
            visibleIDs.firstIndex(of: viewModel.thresholdStoryID ?? -1)
        )
        XCTAssertEqual(thresholdIndex.map { visibleIDs.count - $0 - 1 }, 8)
    }

    func testLoadMoreContinuesByTenDayBatchesUntilUnreadStoryAppears() async {
        let readIDsKey = "DailyReader.readStoryIDs"
        let readStoriesKey = "DailyReader.readStories"
        UserDefaults.standard.set([3], forKey: readIDsKey)
        UserDefaults.standard.removeObject(forKey: readStoriesKey)
        defer {
            UserDefaults.standard.removeObject(forKey: readIDsKey)
            UserDefaults.standard.removeObject(forKey: readStoriesKey)
        }

        let service = MockDailyService()
        service.beforeResults = Dictionary(uniqueKeysWithValues: (1...20).map { offset in
            let requestDay = 22 - offset
            let responseDay = requestDay - 1
            let requestDate = String(format: "202606%02d", requestDay)
            let responseDate = String(format: "202606%02d", responseDay)
            let storyID = requestDate == "20260611" ? 4 : 3
            return (requestDate, .success(DailyResponse(
                date: responseDate,
                stories: [StorySummary(
                    id: storyID,
                    title: storyID == 4 ? "跨过已读区间后的未读日报" : "已读日报"
                )]
            )))
        })
        let viewModel = HomeViewModel(repository: makeRepository(
            service: service,
            cacheStore: DiskCacheStore(rootURL: temporaryRoot())
        ))

        await viewModel.load()
        await viewModel.loadMore()

        XCTAssertEqual(service.beforeCallCount, 20)
        XCTAssertTrue(viewModel.visibleSections.flatMap(\.stories).contains(where: { $0.id == 4 }))
        XCTAssertEqual(viewModel.historyCursor, "20260601")
        XCTAssertNil(viewModel.bannerMessage)
        XCTAssertEqual(viewModel.historyLoadState, .idle)
    }

    func testReadStoryIDsPersistAcrossViewModelInstances() {
        let key = "DailyReader.readStoryIDs"
        UserDefaults.standard.removeObject(forKey: key)
        defer { UserDefaults.standard.removeObject(forKey: key) }

        let firstViewModel = HomeViewModel(repository: makeRepository(service: MockDailyService(), cacheStore: DiskCacheStore(rootURL: temporaryRoot())))
        firstViewModel.markStoryRead(42)

        let secondViewModel = HomeViewModel(repository: makeRepository(service: MockDailyService(), cacheStore: DiskCacheStore(rootURL: temporaryRoot())))
        XCTAssertTrue(secondViewModel.isStoryRead(42))
    }

    func testHideAndRestoreStory() async {
        let hiddenKey = "DailyReader.hiddenStories"
        UserDefaults.standard.removeObject(forKey: hiddenKey)
        defer { UserDefaults.standard.removeObject(forKey: hiddenKey) }

        let service = MockDailyService()
        let viewModel = HomeViewModel(repository: makeRepository(service: service, cacheStore: DiskCacheStore(rootURL: temporaryRoot())))
        await viewModel.load()

        let storyToHide = StorySummary(id: 1, title: "Story 1", images: [], hint: "Hint 1", url: nil)
        
        // Hide
        viewModel.hideStory(storyToHide, date: "20260621")
        
        XCTAssertTrue(viewModel.isStoryHidden(1))
        XCTAssertFalse(viewModel.visibleSections.flatMap(\.stories).contains(where: { $0.id == 1 }))
        XCTAssertTrue(viewModel.hiddenSections.flatMap(\.stories).contains(where: { $0.id == 1 }))
        XCTAssertEqual(viewModel.hiddenSections.first?.date, "20260621")

        // Hide the second story in the same section to verify the section disappears
        let secondStory = StorySummary(id: 2, title: "Story 2", images: [], hint: "Hint 2", url: nil)
        viewModel.hideStory(secondStory, date: "20260621")
        XCTAssertTrue(viewModel.visibleSections.isEmpty) // The whole section was empty, so it's hidden!

        // Restore
        viewModel.restoreStory(1)
        XCTAssertFalse(viewModel.isStoryHidden(1))
        XCTAssertTrue(viewModel.visibleSections.flatMap(\.stories).contains(where: { $0.id == 1 }))
        XCTAssertFalse(viewModel.hiddenSections.flatMap(\.stories).contains(where: { $0.id == 1 }))
    }

    func testFavoriteStoryToggle() async {
        let favoriteKey = "DailyReader.favoriteStories"
        UserDefaults.standard.removeObject(forKey: favoriteKey)
        defer { UserDefaults.standard.removeObject(forKey: favoriteKey) }

        let service = MockDailyService()
        let viewModel = HomeViewModel(repository: makeRepository(service: service, cacheStore: DiskCacheStore(rootURL: temporaryRoot())))
        await viewModel.load()

        let story = StorySummary(id: 1, title: "Story 1", images: [], hint: "Hint 1", url: nil)
        
        // Favorite
        viewModel.toggleFavorite(story, date: "20260621")
        XCTAssertTrue(viewModel.isStoryFavorited(1))
        XCTAssertTrue(viewModel.favoriteSections.flatMap(\.stories).contains(where: { $0.id == 1 }))

        // Unfavorite
        viewModel.toggleFavorite(story, date: "20260621")
        XCTAssertFalse(viewModel.isStoryFavorited(1))
        XCTAssertFalse(viewModel.favoriteSections.flatMap(\.stories).contains(where: { $0.id == 1 }))
    }

    func testReadStoryToggleAndSync() async {
        let readIDsKey = "DailyReader.readStoryIDs"
        let readStoriesKey = "DailyReader.readStories"
        UserDefaults.standard.removeObject(forKey: readIDsKey)
        UserDefaults.standard.removeObject(forKey: readStoriesKey)
        defer {
            UserDefaults.standard.removeObject(forKey: readIDsKey)
            UserDefaults.standard.removeObject(forKey: readStoriesKey)
        }

        let service = MockDailyService()
        let viewModel = HomeViewModel(repository: makeRepository(service: service, cacheStore: DiskCacheStore(rootURL: temporaryRoot())))
        await viewModel.load()

        let story = StorySummary(id: 1, title: "Story 1", images: [], hint: "Hint 1", url: nil)
        
        // Mark read via toggle
        viewModel.toggleRead(story, date: "20260621")
        XCTAssertTrue(viewModel.isStoryRead(1))
        XCTAssertTrue(viewModel.readSections.flatMap(\.stories).contains(where: { $0.id == 1 }))

        // Mark unread via toggle
        viewModel.toggleRead(story, date: "20260621")
        XCTAssertFalse(viewModel.isStoryRead(1))
        XCTAssertFalse(viewModel.readSections.flatMap(\.stories).contains(where: { $0.id == 1 }))

        // Mark read via detail onAppear style
        viewModel.markStoryRead(story, date: "20260621")
        XCTAssertTrue(viewModel.isStoryRead(1))
        XCTAssertTrue(viewModel.readSections.flatMap(\.stories).contains(where: { $0.id == 1 }))
    }

    func testPersistenceAcrossInstances() {
        let hiddenKey = "DailyReader.hiddenStories"
        let favoriteKey = "DailyReader.favoriteStories"
        let readIDsKey = "DailyReader.readStoryIDs"
        let readStoriesKey = "DailyReader.readStories"
        
        UserDefaults.standard.removeObject(forKey: hiddenKey)
        UserDefaults.standard.removeObject(forKey: favoriteKey)
        UserDefaults.standard.removeObject(forKey: readIDsKey)
        UserDefaults.standard.removeObject(forKey: readStoriesKey)
        
        defer {
            UserDefaults.standard.removeObject(forKey: hiddenKey)
            UserDefaults.standard.removeObject(forKey: favoriteKey)
            UserDefaults.standard.removeObject(forKey: readIDsKey)
            UserDefaults.standard.removeObject(forKey: readStoriesKey)
        }

        let firstViewModel = HomeViewModel(repository: makeRepository(service: MockDailyService(), cacheStore: DiskCacheStore(rootURL: temporaryRoot())))
        let story = StorySummary(id: 1, title: "Story 1", images: [], hint: "Hint 1", url: nil)
        
        firstViewModel.hideStory(story, date: "20260621")
        firstViewModel.toggleFavorite(story, date: "20260621")
        firstViewModel.markStoryRead(story, date: "20260621")

        let secondViewModel = HomeViewModel(repository: makeRepository(service: MockDailyService(), cacheStore: DiskCacheStore(rootURL: temporaryRoot())))
        
        XCTAssertTrue(secondViewModel.isStoryHidden(1))
        XCTAssertTrue(secondViewModel.isStoryFavorited(1))
        XCTAssertTrue(secondViewModel.isStoryRead(1))
        XCTAssertEqual(secondViewModel.hiddenSections.flatMap(\.stories).map(\.id), [1])
        XCTAssertEqual(secondViewModel.favoriteSections.flatMap(\.stories).map(\.id), [])
        XCTAssertEqual(secondViewModel.readSections.flatMap(\.stories).map(\.id), [])
    }

    func testUnfavoriteAutomaticallyUnhides() async {
        let hiddenKey = "DailyReader.hiddenStories"
        let favoriteKey = "DailyReader.favoriteStories"
        UserDefaults.standard.removeObject(forKey: hiddenKey)
        UserDefaults.standard.removeObject(forKey: favoriteKey)
        defer {
            UserDefaults.standard.removeObject(forKey: hiddenKey)
            UserDefaults.standard.removeObject(forKey: favoriteKey)
        }

        let service = MockDailyService()
        let viewModel = HomeViewModel(repository: makeRepository(service: service, cacheStore: DiskCacheStore(rootURL: temporaryRoot())))
        await viewModel.load()

        let story = StorySummary(id: 1, title: "Story 1", images: [], hint: "Hint 1", url: nil)

        // 1. Hide
        viewModel.hideStory(story, date: "20260621")
        XCTAssertTrue(viewModel.isStoryHidden(1))

        // 2. Favorite
        viewModel.toggleFavorite(story, date: "20260621")
        XCTAssertTrue(viewModel.isStoryFavorited(1))

        // 3. Unfavorite (should trigger unhide)
        viewModel.toggleFavorite(story, date: "20260621")
        XCTAssertFalse(viewModel.isStoryFavorited(1))
        XCTAssertFalse(viewModel.isStoryHidden(1))
    }

    func testMutualExclusivityOfSections() async {
        let hiddenKey = "DailyReader.hiddenStories"
        let favoriteKey = "DailyReader.favoriteStories"
        let readIDsKey = "DailyReader.readStoryIDs"
        let readStoriesKey = "DailyReader.readStories"

        UserDefaults.standard.removeObject(forKey: hiddenKey)
        UserDefaults.standard.removeObject(forKey: favoriteKey)
        UserDefaults.standard.removeObject(forKey: readIDsKey)
        UserDefaults.standard.removeObject(forKey: readStoriesKey)

        defer {
            UserDefaults.standard.removeObject(forKey: hiddenKey)
            UserDefaults.standard.removeObject(forKey: favoriteKey)
            UserDefaults.standard.removeObject(forKey: readIDsKey)
            UserDefaults.standard.removeObject(forKey: readStoriesKey)
        }

        let service = MockDailyService()
        let viewModel = HomeViewModel(repository: makeRepository(service: service, cacheStore: DiskCacheStore(rootURL: temporaryRoot())))
        await viewModel.load()

        let story = StorySummary(id: 1, title: "Story 1", images: [], hint: "Hint 1", url: nil)

        // Initial state: story 1 is in visibleSections (日报)
        XCTAssertTrue(viewModel.visibleSections.flatMap(\.stories).contains(where: { $0.id == 1 }))
        XCTAssertFalse(viewModel.readSections.flatMap(\.stories).contains(where: { $0.id == 1 }))
        XCTAssertFalse(viewModel.favoriteSections.flatMap(\.stories).contains(where: { $0.id == 1 }))
        XCTAssertFalse(viewModel.hiddenSections.flatMap(\.stories).contains(where: { $0.id == 1 }))

        // 1. Mark Read: moves from visibleSections to readSections
        viewModel.markStoryRead(story, date: "20260621")
        XCTAssertFalse(viewModel.visibleSections.flatMap(\.stories).contains(where: { $0.id == 1 }))
        XCTAssertTrue(viewModel.readSections.flatMap(\.stories).contains(where: { $0.id == 1 }))
        XCTAssertFalse(viewModel.favoriteSections.flatMap(\.stories).contains(where: { $0.id == 1 }))
        XCTAssertFalse(viewModel.hiddenSections.flatMap(\.stories).contains(where: { $0.id == 1 }))

        // 2. Favorite: moves from readSections to favoriteSections
        viewModel.toggleFavorite(story, date: "20260621")
        XCTAssertFalse(viewModel.visibleSections.flatMap(\.stories).contains(where: { $0.id == 1 }))
        XCTAssertFalse(viewModel.readSections.flatMap(\.stories).contains(where: { $0.id == 1 }))
        XCTAssertTrue(viewModel.favoriteSections.flatMap(\.stories).contains(where: { $0.id == 1 }))
        XCTAssertFalse(viewModel.hiddenSections.flatMap(\.stories).contains(where: { $0.id == 1 }))

        // 3. Hide: moves from favoriteSections to hiddenSections
        viewModel.hideStory(story, date: "20260621")
        XCTAssertFalse(viewModel.visibleSections.flatMap(\.stories).contains(where: { $0.id == 1 }))
        XCTAssertFalse(viewModel.readSections.flatMap(\.stories).contains(where: { $0.id == 1 }))
        XCTAssertFalse(viewModel.favoriteSections.flatMap(\.stories).contains(where: { $0.id == 1 }))
        XCTAssertTrue(viewModel.hiddenSections.flatMap(\.stories).contains(where: { $0.id == 1 }))

        // 4. Restore: moves back to favoriteSections (since it's still favorited!)
        viewModel.restoreStory(1)
        XCTAssertFalse(viewModel.visibleSections.flatMap(\.stories).contains(where: { $0.id == 1 }))
        XCTAssertFalse(viewModel.readSections.flatMap(\.stories).contains(where: { $0.id == 1 }))
        XCTAssertTrue(viewModel.favoriteSections.flatMap(\.stories).contains(where: { $0.id == 1 }))
        XCTAssertFalse(viewModel.hiddenSections.flatMap(\.stories).contains(where: { $0.id == 1 }))

        // 5. Unfavorite: moves back to readSections (since it's still read!)
        viewModel.toggleFavorite(story, date: "20260621")
        XCTAssertFalse(viewModel.visibleSections.flatMap(\.stories).contains(where: { $0.id == 1 }))
        XCTAssertTrue(viewModel.readSections.flatMap(\.stories).contains(where: { $0.id == 1 }))
        XCTAssertFalse(viewModel.favoriteSections.flatMap(\.stories).contains(where: { $0.id == 1 }))
        XCTAssertFalse(viewModel.hiddenSections.flatMap(\.stories).contains(where: { $0.id == 1 }))

        // 6. Unread (toggleRead): moves back to visibleSections (日报)
        viewModel.toggleRead(story, date: "20260621")
        XCTAssertTrue(viewModel.visibleSections.flatMap(\.stories).contains(where: { $0.id == 1 }))
        XCTAssertFalse(viewModel.readSections.flatMap(\.stories).contains(where: { $0.id == 1 }))
        XCTAssertFalse(viewModel.favoriteSections.flatMap(\.stories).contains(where: { $0.id == 1 }))
        XCTAssertFalse(viewModel.hiddenSections.flatMap(\.stories).contains(where: { $0.id == 1 }))
    }

    func testLoadImmersiveImageReusesMatchingTopStoryWithoutDetailRequest() async {
        let service = MockDailyService()
        service.latestResult = .success(DailyResponse(
            date: "20260621",
            stories: [StorySummary(id: 1, title: "顶部文章", images: ["https://example.com/thumb.jpg"])],
            topStories: [TopStory(id: 1, title: "顶部文章", image: "https://example.com/top-hero.jpg")]
        ))
        let repository = makeRepository(
            service: service,
            cacheStore: DiskCacheStore(rootURL: temporaryRoot())
        )
        let viewModel = HomeViewModel(
            repository: repository,
            articleRepository: repository
        )
        await viewModel.load()

        guard let story = viewModel.sections.first?.stories.first else {
            return XCTFail("缺少测试文章")
        }
        await viewModel.loadImmersiveImage(for: story)

        XCTAssertEqual(viewModel.immersiveImageURLs[story.id], viewModel.topStories.first?.image)
        XCTAssertEqual(service.detailCallCount, 0)
    }

    func testLoadImmersiveImageUsesDetailImageAndDeduplicatesRequests() async {
        let service = MockDailyService()
        service.latestResult = .success(DailyResponse(
            date: "20260621",
            stories: [StorySummary(id: 7, title: "沉浸文章", images: ["https://example.com/thumb.jpg"])]
        ))
        service.detailResult = .success(ArticleDetail(
            id: 7,
            title: "沉浸文章",
            image: "https://example.com/hero.jpg",
            images: ["https://example.com/fallback.jpg"]
        ))
        let repository = makeRepository(
            service: service,
            cacheStore: DiskCacheStore(rootURL: temporaryRoot())
        )
        let viewModel = HomeViewModel(
            repository: repository,
            articleRepository: repository
        )
        let story = StorySummary(id: 7, title: "沉浸文章", images: ["https://example.com/thumb.jpg"])

        await viewModel.loadImmersiveImage(for: story)
        await viewModel.loadImmersiveImage(for: story)

        XCTAssertEqual(viewModel.immersiveImageURLs[7], "https://example.com/hero.jpg")
        XCTAssertEqual(service.detailCallCount, 1)
    }

    func testPreferredImmersiveImageFallsBackToDetailImages() {
        let detail = ArticleDetail(
            id: 8,
            title: "备用封面",
            image: "  ",
            images: ["https://example.com/images-fallback.jpg"]
        )

        XCTAssertEqual(
            HomeViewModel.preferredImmersiveImageURL(from: detail),
            "https://example.com/images-fallback.jpg"
        )
    }

    func testPreferredImmersiveImageReturnsNilWhenDetailHasNoImage() {
        let detail = ArticleDetail(id: 9, title: "无图文章")

        XCTAssertNil(HomeViewModel.preferredImmersiveImageURL(from: detail))
    }

    private func temporaryRoot() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }
}

private extension HomePhase {
    var isCacheLoaded: Bool {
        if case .loaded(.cache) = self { return true }
        return false
    }
}
