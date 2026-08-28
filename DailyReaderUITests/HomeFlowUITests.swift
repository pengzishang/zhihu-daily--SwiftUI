import XCTest

final class HomeFlowUITests: XCTestCase {
    func testLaunchShowsMockHomeContent() {
        let app = launchApp(scenario: "latest_success")

        XCTAssertTrue(app.navigationBars["日报阅读器"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["今天，先读一篇长一点的故事"].waitForExistence(timeout: 5))
        let storyMetrics = app.descendants(matching: .any)["storyMetrics"].firstMatch
        XCTAssertTrue(storyMetrics.waitForExistence(timeout: 5))
        XCTAssertEqual(storyMetrics.label, "知乎日报热度 30，评论 10")
        attachScreenshot(named: "home-latest-success", app: app)
    }

    func testTodayStoryOpeningAppearsAndOpensExistingArticleDetail() {
        let app = launchApp(scenario: "latest_success")

        let opening = app.descendants(matching: .any)["home.todayStoryOpening"]
        XCTAssertTrue(opening.waitForExistence(timeout: 5))
        XCTAssertEqual(opening.label, "今日故事：今天，先读一篇长一点的故事")

        opening.tap()

        XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["枫问"].waitForExistence(timeout: 5))
    }

    func testTodayStoryOpeningIsHiddenWhenTopStoriesAreEmpty() {
        let app = launchApp(scenario: "latest_without_top_stories", resetCache: true)

        XCTAssertTrue(app.navigationBars["日报阅读器"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["今天，先读一篇长一点的故事"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["home.todayStoryOpening"].waitForExistence(timeout: 2))
    }

    func testHomeDensityCanSwitchBetweenThreeLayouts() {
        let app = launchApp(scenario: "latest_success")

        let moreButton = app.buttons["home.moreButton"]
        XCTAssertTrue(moreButton.waitForExistence(timeout: 5))
        moreButton.tap()

        let sheet = app.descendants(matching: .any)["homeDensity.sheet"]
        XCTAssertTrue(sheet.waitForExistence(timeout: 3))

        let low = app.buttons["homeDensity.option.low"]
        let medium = app.buttons["homeDensity.option.medium"]
        let high = app.buttons["homeDensity.option.high"]
        XCTAssertTrue(low.exists)
        XCTAssertTrue(medium.exists)
        XCTAssertTrue(high.exists)

        high.tap()
        XCTAssertEqual(high.value as? String, "1")

        app.swipeDown()
        let firstRowPredicate = NSPredicate(format: "identifier BEGINSWITH %@", "storyRow-")
        let firstRow = app.descendants(matching: .any).matching(firstRowPredicate).firstMatch
        XCTAssertTrue(firstRow.waitForExistence(timeout: 3))
        XCTAssertEqual(firstRow.value as? String, "速览")

        moreButton.tap()
        XCTAssertTrue(high.waitForExistence(timeout: 3))
        medium.tap()
        XCTAssertEqual(medium.value as? String, "1")
        attachScreenshot(named: "home-density-picker", app: app)
    }

    func testHomeDensitySettingIsAvailableFromSettings() {
        let app = launchApp(scenario: "latest_success")

        app.tabBars.buttons["我的"].tap()
        XCTAssertTrue(app.buttons["me.settingsButton"].waitForExistence(timeout: 5))
        app.buttons["me.settingsButton"].tap()

        let densitySetting = app.buttons["settings.homeDensity"]
        XCTAssertTrue(densitySetting.waitForExistence(timeout: 5))
        densitySetting.tap()
        XCTAssertTrue(app.descendants(matching: .any)["settings.homeDensity.screen"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["homeDensity.option.low"].exists)
        XCTAssertTrue(app.buttons["homeDensity.option.medium"].exists)
        XCTAssertTrue(app.buttons["homeDensity.option.high"].exists)
    }

    func testAISearchShowsProviderConfigurationPromptWhenNoProviderAvailable() {
        let app = launchApp(scenario: "latest_success")

        let aiButton = app.buttons["home.aiButton"]
        XCTAssertTrue(aiButton.waitForExistence(timeout: 5))
        aiButton.tap()

        XCTAssertTrue(app.staticTexts["尚无可用 AI 服务"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["去设置"].exists)
        XCTAssertFalse(app.buttons["发送"].isEnabled)
        attachScreenshot(named: "ai-no-provider-configuration", app: app)
    }

    func testArticleQuickPromptsKeepSelectionWhenNoProviderIsAvailable() {
        let app = launchApp(scenario: "latest_success")

        openFirstStory(in: app)
        let articleAIButton = app.buttons["articleAIButton"]
        XCTAssertTrue(articleAIButton.waitForExistence(timeout: 5))
        articleAIButton.tap()

        let expectedPrompts = [
            "用三句话总结这篇文章",
            "解释文中的核心概念",
            "查证文章中的关键结论"
        ]
        for (index, prompt) in expectedPrompts.enumerated() {
            let quickPrompt = app.buttons["ai.quickPrompt.\(index)"]
            XCTAssertTrue(quickPrompt.waitForExistence(timeout: 5))
            XCTAssertEqual(quickPrompt.label, prompt)
        }

        app.buttons["ai.quickPrompt.0"].tap()

        let composer = app.textFields["ai.chat.composer"]
        XCTAssertTrue(composer.waitForExistence(timeout: 5))
        XCTAssertEqual(composer.value as? String, "用三句话总结这篇文章")
        XCTAssertTrue(app.staticTexts["暂无可用 AI 服务，请前往设置启用或配置"].exists)
        XCTAssertTrue(app.buttons["配置服务"].exists)
    }

    func testAISettingsShowsOneDefaultServiceAndHidesInternalLanes() {
        let app = launchApp(
            scenario: "latest_success",
            additionalEnvironment: ["MOCK_AI_DEFAULT_SERVICE": "1"]
        )

        XCTAssertTrue(app.tabBars.buttons["我的"].waitForExistence(timeout: 5))
        app.tabBars.buttons["我的"].tap()
        XCTAssertTrue(app.buttons["me.settingsButton"].waitForExistence(timeout: 5))
        app.buttons["me.settingsButton"].tap()
        XCTAssertTrue(app.staticTexts["AI 服务设置"].waitForExistence(timeout: 5))
        app.staticTexts["AI 服务设置"].tap()

        XCTAssertTrue(app.navigationBars["AI 服务"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts.matching(identifier: "默认服务").count, 1)
        XCTAssertFalse(app.staticTexts["ONLINE"].exists)
        XCTAssertFalse(app.staticTexts["SENSENOVA_GOU"].exists)
        XCTAssertFalse(app.staticTexts["ERIC"].exists)
        XCTAssertFalse(app.staticTexts["ui-test-lane"].exists)
    }

    func testOpenArticleDetailAndReturnHome() {
        let app = launchApp(scenario: "latest_success")

        XCTAssertTrue(app.staticTexts["今天，先读一篇长一点的故事"].waitForExistence(timeout: 5))
        app.staticTexts["今天，先读一篇长一点的故事"].firstMatch.tap()

        XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["枫问"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["写回答挣猫粮"].exists)
        let dailyMetrics = app.descendants(matching: .any)["articleMetrics.daily"]
        let originalAnswerMetrics = app.descendants(matching: .any)["articleMetrics.originalAnswer"]
        XCTAssertTrue(dailyMetrics.waitForExistence(timeout: 5))
        XCTAssertEqual(dailyMetrics.label, "日报数据，热度 30，评论 10")
        XCTAssertTrue(originalAnswerMetrics.waitForExistence(timeout: 5))
        XCTAssertEqual(originalAnswerMetrics.label, "原回答，赞同 1848，评论 179，收藏 1050")
        let progressButton = app.descendants(matching: .any)["articleReadingProgressButton"]
        XCTAssertFalse(progressButton.exists)

        XCTAssertTrue(app.buttons["操作"].exists)
        attachScreenshot(named: "detail-success", app: app)

        app.navigationBars.firstMatch.buttons.firstMatch.tap()
        XCTAssertTrue(app.navigationBars["日报阅读器"].waitForExistence(timeout: 5))
    }

    func testSwipeRightFromLeftEdgeReturnsToHome() {
        let app = launchApp(scenario: "latest_success")

        XCTAssertTrue(app.staticTexts["今天，先读一篇长一点的故事"].waitForExistence(timeout: 5))
        app.staticTexts["今天，先读一篇长一点的故事"].firstMatch.tap()

        XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout: 5))
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .fast, thenHoldForDuration: 0)

        XCTAssertTrue(app.navigationBars["日报阅读器"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["今天，先读一篇长一点的故事"].exists)
    }

    func testShareSheetCanOpenAndDismissWithoutLeavingDetail() throws {
        throw XCTSkip("系统分享面板由手工验收覆盖；该面板在 XCUITest runner 中存在系统级不稳定，避免阻塞整组 UI 测试。")
    }

    func testLoadHistoryShowsOlderStory() {
        let app = launchApp(scenario: "latest_success")

        XCTAssertTrue(app.staticTexts["今天，先读一篇长一点的故事"].waitForExistence(timeout: 5))
        for _ in 0..<5 where !app.staticTexts["昨天的好问题"].exists {
            app.swipeUp()
        }

        XCTAssertTrue(app.staticTexts["昨天的好问题"].waitForExistence(timeout: 5))
        attachScreenshot(named: "history-loaded", app: app)
    }

    func testOfflineWithoutCacheShowsRetryableChineseError() {
        let app = launchApp(scenario: "offline_no_cache", resetCache: true)

        XCTAssertTrue(app.staticTexts["网络不可用，请检查连接后重试"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["重试"].exists)
        attachScreenshot(named: "offline-no-cache", app: app)
    }

    func testLatestEmptyShowsEmptyState() {
        let app = launchApp(scenario: "latest_empty", resetCache: true)

        XCTAssertTrue(app.staticTexts["今日暂无内容"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["稍后再试，或者下拉刷新。"].exists)
        attachScreenshot(named: "latest-empty", app: app)
    }

    func testDetailEmptyBodyShowsUnavailableState() {
        let app = launchApp(scenario: "detail_empty_body")

        openFirstStory(in: app)

        XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["文章内容暂不可用"].waitForExistence(timeout: 5))
        attachScreenshot(named: "detail-empty-body", app: app)
    }

    func testDetailMissingShareLinkDisablesShareButton() {
        let app = launchApp(scenario: "detail_missing_share")

        openFirstStory(in: app)

        XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["无分享链接文章"].waitForExistence(timeout: 5))
        
        XCTAssertTrue(app.buttons["操作"].waitForExistence(timeout: 5))
        app.buttons["操作"].tap()
        XCTAssertTrue(app.buttons["分享"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.buttons["分享"].isEnabled)
        attachScreenshot(named: "detail-missing-share", app: app)
    }

    func testLongBodyCanScrollToTail() {
        let app = launchApp(scenario: "detail_long_body", resetCache: true)

        openFirstStory(in: app)

        XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 5))
        for _ in 0..<8 where !app.staticTexts["长正文结尾标记"].exists {
            app.swipeUp()
        }
        XCTAssertTrue(app.staticTexts["长正文结尾标记"].waitForExistence(timeout: 5))
        let progressButton = app.descendants(matching: .any)["articleReadingProgressButton"]
        XCTAssertTrue(progressButton.waitForExistence(timeout: 2))
        let progressValue = progressButton.value as? String
        XCTAssertNotNil(progressValue)
        XCTAssertNotEqual(progressValue, "已阅读百分之零")
        progressButton.tap()
        XCTAssertFalse(progressButton.waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["长正文阅读验证"].firstMatch.waitForExistence(timeout: 2))
        attachScreenshot(named: "detail-long-body-returned-top", app: app)
    }

    func testFullScreenImageDismissesWhenTappingBlackBackground() {
        let app = launchApp(scenario: "detail_body_image", resetCache: true)

        openFirstStory(in: app)

        let title = app.staticTexts["图片预览验证"].firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        let imagePreviewTrigger = app.buttons["articleImagePreviewTestTrigger"]
        XCTAssertTrue(imagePreviewTrigger.waitForExistence(timeout: 5))
        imagePreviewTrigger.tap()

        let closeButton = app.buttons["fullScreenImageViewer.closeButton"]
        XCTAssertTrue(closeButton.waitForExistence(timeout: 5))
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5)).tap()

        XCTAssertFalse(closeButton.waitForExistence(timeout: 2))
        XCTAssertTrue(title.waitForExistence(timeout: 2))
        attachScreenshot(named: "detail-image-dismissed-by-background", app: app)
    }

    func testV10OutOfScopeEntriesDoNotAppear() {
        let app = launchApp(scenario: "latest_success")
        let forbiddenTexts = ["登录", "注册", "评论", "点赞", "搜索", "主题日报"]

        XCTAssertTrue(app.navigationBars["日报阅读器"].waitForExistence(timeout: 5))
        for forbiddenText in forbiddenTexts {
            XCTAssertFalse(app.buttons[forbiddenText].exists)
            XCTAssertFalse(app.staticTexts[forbiddenText].exists)
        }
        attachScreenshot(named: "scope-boundary-no-out-of-scope-entry", app: app)
    }

    private func launchApp(
        scenario: String,
        resetCache: Bool = false,
        additionalEnvironment: [String: String] = [:]
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestMode"]
        if resetCache {
            app.launchArguments.append("-ResetCache")
        }
        var environment = ["MOCK_SCENARIO": scenario]
        environment.merge(additionalEnvironment) { _, newValue in newValue }
        if resetCache {
            environment["MOCK_KEYCHAIN_STATUS"] = "corrupted"
        }
        app.launchEnvironment = environment
        app.launch()
        return app
    }

    private func openFirstStory(in app: XCUIApplication) {
        if app.tabBars.buttons["日报"].exists {
            app.tabBars.buttons["日报"].tap()
        }

        let firstStory = app.staticTexts["今天，先读一篇长一点的故事"]
        if firstStory.waitForExistence(timeout: 8) {
            firstStory.tap()
            return
        }

        let fallbackStory = app.staticTexts["SwiftUI 里的温柔边界"]
        if fallbackStory.waitForExistence(timeout: 2) {
            fallbackStory.tap()
            return
        }

        let storyRowPredicate = NSPredicate(format: "identifier BEGINSWITH %@", "storyRow-")
        let firstStoryRow = app.descendants(matching: .any).matching(storyRowPredicate).firstMatch
        XCTAssertTrue(firstStoryRow.waitForExistence(timeout: 5))
        firstStoryRow.tap()
    }

    private func attachScreenshot(named name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
