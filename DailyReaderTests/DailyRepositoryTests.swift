import XCTest
@testable import DailyReader

final class DailyRepositoryTests: XCTestCase {
    func testHomeFeedEmitsCachedValueBeforeNetworkRefresh() async throws {
        let cachedAt = Date(timeIntervalSince1970: 1_782_446_400)
        let cache = RepositoryInMemoryCacheStore(home: CachedValue(
            value: CachedHomeFeed(
                sections: [DailySection(date: "20260620", stories: [DailyResponse.historyFixture.stories[1]])],
                topStories: []
            ),
            cachedAt: cachedAt
        ))
        let repository = DailyRepository(service: RepositoryMockDailyService(), cacheStore: cache)

        var events: [HomeFeedEvent] = []
        for try await event in repository.loadHomeFeed() {
            events.append(event)
        }

        XCTAssertEqual(events.count, 2)
        guard case .cached(let cached) = events[0],
              case .refreshed(let refreshed) = events[1]
        else {
            return XCTFail("Expected cache then network events")
        }
        XCTAssertEqual(cached.source, .cache(cachedAt))
        XCTAssertEqual(cached.value.sections.first?.date, "20260620")
        XCTAssertEqual(refreshed.source, .network)
        XCTAssertEqual(refreshed.value.sections.first?.date, "20260621")
    }

    func testHomeFeedFailsWithoutAnyCacheWhenNetworkFails() async {
        let service = RepositoryMockDailyService()
        service.latestResult = .failure(APIError.transport("offline"))
        let repository = DailyRepository(service: service, cacheStore: RepositoryInMemoryCacheStore())

        do {
            for try await _ in repository.loadHomeFeed() {}
            XCTFail("Expected an error")
        } catch let error as APIError {
            XCTAssertEqual(error, .transport("offline"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testStoppingHomeFeedConsumerCancelsProducerAndSkipsNetworkCacheWrites() async throws {
        let cachedAt = Date(timeIntervalSince1970: 1_782_446_400)
        let cachedHome = CachedValue(
            value: CachedHomeFeed(
                sections: [DailySection(date: "20260620", stories: [DailyResponse.historyFixture.stories[1]])],
                topStories: []
            ),
            cachedAt: cachedAt
        )
        let service = RepositoryMockDailyService()
        service.latestDelayNanoseconds = 5_000_000_000
        let cache = RepositoryInMemoryCacheStore(home: cachedHome)
        let repository = DailyRepository(service: service, cacheStore: cache)

        let consumer = Task {
            for try await _ in repository.loadHomeFeed() {}
        }
        for _ in 0..<100 where service.latestCallCount == 0 {
            await Task.yield()
        }
        XCTAssertEqual(service.latestCallCount, 1)

        consumer.cancel()
        do {
            try await consumer.value
        } catch is CancellationError {
            // Expected: consumer cancellation terminates the stream and producer.
        }

        for _ in 0..<100 where service.latestCancellationCount == 0 {
            await Task.yield()
        }

        let latestCache = await cache.loadLatest()
        let homeFeedCache = await cache.loadHomeFeed()

        XCTAssertEqual(service.latestCancellationCount, 1)
        XCTAssertNil(latestCache)
        XCTAssertEqual(homeFeedCache?.value, cachedHome.value)
    }

    func testDetailUsesCacheBeforeService() async throws {
        let detail = ArticleDetail.fixture
        let cachedAt = Date(timeIntervalSince1970: 1_782_446_400)
        let service = RepositoryMockDailyService()
        let cache = RepositoryInMemoryCacheStore(details: [1: CachedValue(value: detail, cachedAt: cachedAt)])
        let repository = DailyRepository(service: service, cacheStore: cache)

        let result = try await repository.fetchDetail(id: 1)

        XCTAssertEqual(result.value, detail)
        XCTAssertEqual(result.source, .cache(cachedAt))
        XCTAssertEqual(service.detailCallCount, 0)
    }

    func testHistoricalLoadUsesCachedDatesWithoutNetworkAndAdvancesTenDays() async throws {
        let cachedAt = Date(timeIntervalSince1970: 1_782_446_400)
        let cachedResponses = (11...20).reduce(into: [String: CachedValue<DailyResponse>]()) { result, day in
            let date = String(format: "202606%02d", day)
            result[date] = CachedValue(
                value: .history(date: date, storyID: day),
                cachedAt: cachedAt
            )
        }
        let service = RepositoryMockDailyService()
        service.beforeResult = .failure(APIError.transport("network should not be used"))
        let repository = DailyRepository(
            service: service,
            cacheStore: RepositoryInMemoryCacheStore(daily: cachedResponses)
        )

        let result = try await repository.loadMore(before: "20260621", current: .fixture)

        XCTAssertEqual(service.beforeCallCount, 0)
        XCTAssertEqual(result.source, .cache(cachedAt))
        XCTAssertEqual(result.value.sections.first?.date, "20260621")
        XCTAssertEqual(result.value.sections.last?.date, "20260611")
        XCTAssertEqual(result.value.historyCursor, "20260611")
    }

    func testHistoricalLoadFetchesOnlyCacheMissesConcurrentlyAndSortsResponses() async throws {
        let cachedDate = "20260620"
        let service = RepositoryMockDailyService()
        service.beforeDelayNanoseconds = 20_000_000
        service.beforeResults = Dictionary(uniqueKeysWithValues: (11...19).map { day in
            let requestDate = String(format: "202606%02d", day + 1)
            let responseDate = String(format: "202606%02d", day)
            return (requestDate, .success(.history(date: responseDate, storyID: day)))
        })
        let cache = RepositoryInMemoryCacheStore(daily: [
            cachedDate: CachedValue(
                value: .history(date: cachedDate, storyID: 20),
                cachedAt: Date(timeIntervalSince1970: 1_782_446_400)
            )
        ])
        let repository = DailyRepository(service: service, cacheStore: cache)

        let result = try await repository.loadMore(before: "20260621", current: .fixture)

        XCTAssertEqual(service.beforeCallCount, 9)
        XCTAssertFalse(service.requestedBeforeDates.contains("20260621"))
        XCTAssertGreaterThan(service.maximumConcurrentBeforeCallCount, 1)
        XCTAssertEqual(result.source, .network)
        XCTAssertEqual(result.value.sections.map(\.date), [
            "20260621", "20260620", "20260619", "20260618", "20260617",
            "20260616", "20260615", "20260614", "20260613", "20260612", "20260611"
        ])
        XCTAssertEqual(result.value.historyCursor, "20260611")
        let saved = await cache.loadDaily(dates: (11...20).map { String(format: "202606%02d", $0) })
        XCTAssertEqual(saved.count, 10)
    }

    func testHistoricalLoadSortsOlderResponsesBehindExistingSections() async throws {
        let service = RepositoryMockDailyService()
        service.beforeResults = Dictionary(uniqueKeysWithValues: (11...20).map { day in
            let requestDate = String(format: "202606%02d", day + 1)
            let responseDate = String(format: "202606%02d", day)
            return (requestDate, .success(.history(date: responseDate, storyID: day)))
        })
        let current = HomeFeedSnapshot(
            sections: [
                DailySection(date: "20260621", stories: DailyResponse.fixture.stories),
                DailySection(date: "20260501", stories: [StorySummary(id: 500, title: "既有旧日报")])
            ],
            topStories: DailyResponse.fixture.topStories,
            historyCursor: "20260621"
        )
        let repository = DailyRepository(
            service: service,
            cacheStore: RepositoryInMemoryCacheStore()
        )

        let result = try await repository.loadMore(before: "20260621", current: current)

        XCTAssertEqual(result.value.sections.first?.date, "20260621")
        XCTAssertEqual(result.value.sections.last?.date, "20260501")
        XCTAssertEqual(result.value.sections.map(\.date), result.value.sections.map(\.date).sorted(by: >))
    }

    func testHistoricalLoadKeepsPartialSuccessAndStopsCursorBeforeFailedGap() async throws {
        let service = RepositoryMockDailyService()
        service.beforeResult = .failure(APIError.transport("offline"))
        service.beforeResults["20260621"] = .success(.history(date: "20260620", storyID: 20))
        let repository = DailyRepository(
            service: service,
            cacheStore: RepositoryInMemoryCacheStore()
        )

        let result = try await repository.loadMore(before: "20260621", current: .fixture)

        XCTAssertEqual(service.beforeCallCount, 10)
        XCTAssertEqual(result.value.sections.map(\.date), ["20260621", "20260620"])
        XCTAssertEqual(result.value.historyCursor, "20260620")
    }

    func testHistoricalLoadAdvancesCursorWhenResponsesContainNoStories() async throws {
        let service = RepositoryMockDailyService()
        service.beforeResults = Dictionary(uniqueKeysWithValues: (11...20).map { day in
            let requestDate = String(format: "202606%02d", day + 1)
            let responseDate = String(format: "202606%02d", day)
            return (requestDate, .success(DailyResponse(date: responseDate, stories: [])))
        })
        let repository = DailyRepository(
            service: service,
            cacheStore: RepositoryInMemoryCacheStore()
        )

        let result = try await repository.loadMore(before: "20260621", current: .fixture)

        XCTAssertEqual(result.value.sections.map(\.date), ["20260621"])
        XCTAssertEqual(result.value.historyCursor, "20260611")
    }

    func testHistoricalLoadThrowsWhenEntireBatchIsUnavailable() async {
        let service = RepositoryMockDailyService()
        service.beforeResult = .failure(APIError.transport("offline"))
        let repository = DailyRepository(
            service: service,
            cacheStore: RepositoryInMemoryCacheStore()
        )

        do {
            _ = try await repository.loadMore(before: "20260621", current: .fixture)
            XCTFail("Expected an error")
        } catch let error as APIError {
            XCTAssertEqual(error, .transport("offline"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testHotListUsesSameDayCacheUnlessForced() async throws {
        let now = Date(timeIntervalSince1970: 1_782_446_400)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let cached = HotListResponse.fixture(questionID: 88)
        let service = RepositoryMockDailyService()
        let cache = RepositoryInMemoryCacheStore(hotList: CachedValue(value: cached, cachedAt: now))
        let repository = DailyRepository(service: service, cacheStore: cache, calendar: calendar, now: { now })

        let normal = try await repository.fetchHotList(forceRefresh: false)
        let forced = try await repository.fetchHotList(forceRefresh: true)

        XCTAssertEqual(normal.source, ContentSource.cache(now))
        XCTAssertEqual(normal.value.data.map(\.target.id), cached.data.map(\.target.id))
        XCTAssertEqual(forced.source, ContentSource.network)
        XCTAssertEqual(service.hotListCallCount, 1)
    }
}

private extension HomeFeedSnapshot {
    static var fixture: HomeFeedSnapshot {
        HomeFeedSnapshot(
            sections: [DailySection(
                date: DailyResponse.fixture.date,
                stories: DailyResponse.fixture.stories
            )],
            topStories: DailyResponse.fixture.topStories
        )
    }
}

private extension DailyResponse {
    static func history(date: String, storyID: Int) -> DailyResponse {
        DailyResponse(
            date: date,
            stories: [StorySummary(id: storyID, title: "历史日报 \(date)")]
        )
    }
}
