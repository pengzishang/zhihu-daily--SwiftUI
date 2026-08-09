import XCTest

final class MeFlowUITests: XCTestCase {
    
    private func launchApp(scenario: String, resetCache: Bool = true) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestMode"]
        if resetCache {
            app.launchArguments.append("-ResetCache")
        }
        app.launchEnvironment = ["MOCK_SCENARIO": scenario]
        app.launch()
        return app
    }
    
    private func attachScreenshot(named name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
    
    /// Helper to populate one favorite and read story
    private func populateFavoriteAndRead(app: XCUIApplication) {
        // Tap first story to mark as read and go to detail
        XCTAssertTrue(app.staticTexts["今天，先读一篇长一点的故事"].waitForExistence(timeout: 5))
        app.staticTexts["今天，先读一篇长一点的故事"].tap()
        
        // Tap "操作" menu button
        let actionButton = app.buttons["操作"]
        XCTAssertTrue(actionButton.waitForExistence(timeout: 5))
        actionButton.tap()
        
        // Tap "收藏"
        let favoriteButton = app.buttons["收藏"]
        XCTAssertTrue(favoriteButton.waitForExistence(timeout: 5))
        favoriteButton.tap()
        
        // Go back to home
        app.navigationBars.firstMatch.buttons.firstMatch.tap()
    }

    // MARK: - Tier 1: Functional Coverage
    
    func testT1_ME_01_TabNavigationAndBookroomLayout() {
        let app = launchApp(scenario: "latest_success")

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5))
        XCTAssertEqual(tabBar.buttons.count, 3)
        XCTAssertFalse(tabBar.buttons["设置"].exists)

        let meTab = tabBar.buttons["我的"]
        XCTAssertTrue(meTab.exists)
        meTab.tap()

        XCTAssertTrue(app.staticTexts["me.header"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.otherElements["me.readingArchive"].exists)
        XCTAssertTrue(app.buttons["me.settingsButton"].exists)

        XCTAssertFalse(app.otherElements["auth.card"].exists)
        XCTAssertFalse(app.buttons["auth.signInButton"].exists)
        XCTAssertFalse(app.buttons["注册"].exists)

        attachScreenshot(named: "me-paper-bookroom-layout", app: app)
    }

    func testT1_ME_01A_SettingsMovesIntoBookroomHeader() {
        let app = launchApp(scenario: "latest_success")

        app.tabBars.buttons["我的"].tap()

        let settingsButton = app.buttons["me.settingsButton"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 5))
        settingsButton.tap()

        XCTAssertTrue(app.navigationBars["设置"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["阅读设置"].exists)

        app.navigationBars["设置"].buttons.firstMatch.tap()
        XCTAssertTrue(app.staticTexts["me.header"].waitForExistence(timeout: 5))
    }
    
    func testT1_ME_02_CapsuleSliderSwitching() {
        let app = launchApp(scenario: "latest_success")
        populateFavoriteAndRead(app: app)
        
        // Switch to Me Tab
        app.tabBars.buttons["我的"].tap()
        
        // Favorites list and the local reading archive should reflect the populated story.
        XCTAssertTrue(app.collectionViews["me.favorites.list"].waitForExistence(timeout: 5))
        let archive = app.otherElements["me.readingArchive"]
        XCTAssertTrue(archive.waitForExistence(timeout: 5))
        XCTAssertTrue(archive.label.contains("收藏 1 篇"))
        XCTAssertFalse(app.navigationBars["设置"].exists)

        // Tap "已读" switcher
        let readSegmentButton = app.buttons["me.segment.read"]
        XCTAssertTrue(readSegmentButton.exists)
        readSegmentButton.tap()
        
        XCTAssertFalse(app.navigationBars["设置"].exists)

        // Read list should exist
        XCTAssertTrue(app.collectionViews["me.read.list"].waitForExistence(timeout: 5))
        attachScreenshot(named: "me-read-list-selected", app: app)

        app.buttons["me.segment.favorites"].tap()
        XCTAssertFalse(app.navigationBars["设置"].exists)
        XCTAssertTrue(app.collectionViews["me.favorites.list"].waitForExistence(timeout: 5))
    }
    
    func testT1_ME_03_FavoritesListSearch() {
        let app = launchApp(scenario: "latest_success")
        populateFavoriteAndRead(app: app)
        
        app.tabBars.buttons["我的"].tap()
        
        let searchField = app.textFields["me.searchField"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        
        searchField.tap()
        searchField.typeText("长故事")
        
        // Should find "今天，先读一篇长一点的故事"
        XCTAssertTrue(app.staticTexts["今天，先读一篇长一点的故事"].exists)
        
        searchField.tap()
        // Delete text or type something else
        searchField.typeText("SwiftUI")
        // "今天，先读一篇长一点的故事" should filter out
        XCTAssertFalse(app.staticTexts["今天，先读一篇长一点的故事"].exists)
    }
    
    func testT1_ME_04_ReadListSearch() {
        let app = launchApp(scenario: "latest_success")
        populateFavoriteAndRead(app: app)
        
        app.tabBars.buttons["我的"].tap()
        app.buttons["me.segment.read"].tap()
        
        let searchField = app.textFields["me.searchField"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        
        searchField.tap()
        searchField.typeText("长一点")
        
        XCTAssertTrue(app.staticTexts["今天，先读一篇长一点的故事"].exists)
    }
    
    func testT1_ME_05_SearchFieldReset() {
        let app = launchApp(scenario: "latest_success")
        populateFavoriteAndRead(app: app)
        
        app.tabBars.buttons["我的"].tap()
        
        let searchField = app.textFields["me.searchField"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        
        searchField.tap()
        searchField.typeText("SwiftUI")
        
        XCTAssertFalse(app.staticTexts["今天，先读一篇长一点的故事"].exists)
        
        // Tap the clear (xmark) button
        let clearButton = app.buttons["Clear text"] // standard SwiftUI textfield clear button label or custom
        if clearButton.exists {
            clearButton.tap()
        } else {
            // fallback: select all and delete, or delete using backspace
            searchField.doubleTap()
            app.keys["delete"].tap()
        }
        
        // Restore items
        XCTAssertTrue(app.staticTexts["今天，先读一篇长一点的故事"].waitForExistence(timeout: 5))
    }
    
    // MARK: - Tier 2: Boundary & Exceptions
    
    func testT2_ME_02_SearchSpecialCharacters() {
        let app = launchApp(scenario: "latest_success")
        populateFavoriteAndRead(app: app)
        
        app.tabBars.buttons["我的"].tap()
        
        let searchField = app.textFields["me.searchField"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        
        searchField.tap()
        searchField.typeText("~!@#$%^&*()_+")
        
        XCTAssertTrue(app.staticTexts["未找到匹配的内容，换个词试试吧"].waitForExistence(timeout: 5))
        attachScreenshot(named: "me-search-no-results", app: app)
    }
    
    func testT2_ME_03_SearchTrimWhitespace() {
        let app = launchApp(scenario: "latest_success")
        populateFavoriteAndRead(app: app)
        
        app.tabBars.buttons["我的"].tap()
        
        let searchField = app.textFields["me.searchField"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        
        searchField.tap()
        searchField.typeText("   故事   ")
        
        // Should find "今天，先读一篇长一点的故事" due to auto-trimming
        XCTAssertTrue(app.staticTexts["今天，先读一篇长一点的故事"].waitForExistence(timeout: 5))
    }
    
    func testT2_ME_04_TabSwitchInheritsSearchText() {
        let app = launchApp(scenario: "latest_success")
        populateFavoriteAndRead(app: app)
        
        app.tabBars.buttons["我的"].tap()
        
        let searchField = app.textFields["me.searchField"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        
        searchField.tap()
        searchField.typeText("故事")
        
        // Switch tab to Read
        app.buttons["me.segment.read"].tap()
        
        // Verify search field still has the text "故事"
        XCTAssertEqual(searchField.value as? String, "故事")
        
        // Read list should be filtered immediately
        XCTAssertTrue(app.staticTexts["今天，先读一篇长一点的故事"].exists)
    }
    
    func testT2_ME_05_SearchNoMatchEmptyState() {
        let app = launchApp(scenario: "latest_success")
        populateFavoriteAndRead(app: app)
        
        app.tabBars.buttons["我的"].tap()
        
        let searchField = app.textFields["me.searchField"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        
        searchField.tap()
        searchField.typeText("不存在的测试文章")
        
        XCTAssertTrue(app.staticTexts["未找到匹配的内容，换个词试试吧"].waitForExistence(timeout: 5))
    }
}
