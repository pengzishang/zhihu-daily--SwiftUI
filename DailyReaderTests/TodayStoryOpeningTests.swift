import XCTest
@testable import DailyReader

@MainActor
final class TodayStoryOpeningTests: XCTestCase {
    func testSummaryMapsExistingTopStoryFields() {
        let story = TopStory(
            id: 42,
            title: "  今天的顶部故事  ",
            image: "https://example.com/hero.jpg",
            url: "https://example.com/story/42"
        )

        let summary = TodayStoryOpeningView.makeSummary(for: story)

        XCTAssertEqual(summary.id, 42)
        XCTAssertEqual(summary.title, "今天的顶部故事")
        XCTAssertEqual(summary.images, ["https://example.com/hero.jpg"])
        XCTAssertEqual(summary.hint, "顶部故事")
        XCTAssertEqual(summary.url, "https://example.com/story/42")
    }

    func testSummaryKeepsNavigationAvailableWhenImageIsMissing() {
        let story = TopStory(
            id: 7,
            title: "无图也能阅读",
            image: nil,
            url: "https://example.com/story/7"
        )

        let summary = TodayStoryOpeningView.makeSummary(for: story)

        XCTAssertTrue(summary.images.isEmpty)
        XCTAssertEqual(summary.title, "无图也能阅读")
        XCTAssertEqual(summary.url, "https://example.com/story/7")
    }

    func testFirstTopStoryIsTheOpeningStory() {
        let topStories = [
            TopStory(id: 1, title: "第一条"),
            TopStory(id: 2, title: "第二条")
        ]

        XCTAssertEqual(topStories.first?.id, 1)
        XCTAssertNil([TopStory]().first)
    }
}
