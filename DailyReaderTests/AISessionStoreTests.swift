import XCTest
@testable import DailyReader

final class AISessionStoreTests: XCTestCase {
    func testRoundTripsSessionsInApplicationSupportStyleStore() async throws {
        let root = temporaryRoot()
        let store = AISessionStore(rootURL: root)
        let context = AIArticleContext(id: 1, title: "文章", text: "正文")
        let session = AIChatSession(
            title: "测试会话",
            articleContext: context,
            messages: [AIChatMessage(role: .user, content: "问题")],
            draft: "草稿"
        )

        try await store.save([session])
        let loaded = try await store.load()

        XCTAssertEqual(loaded, [session])
    }

    func testStreamingMessageRecoversAsInterrupted() async throws {
        let root = temporaryRoot()
        let store = AISessionStore(rootURL: root)
        let message = AIChatMessage(role: .assistant, content: "部分回答", state: .streaming)
        let session = AIChatSession(title: "中断会话", messages: [message])

        try await store.save([session])
        let loaded = try await store.load()

        XCTAssertEqual(loaded.first?.messages.first?.state, .interrupted)
        XCTAssertEqual(loaded.first?.messages.first?.content, "部分回答")
    }

    func testOlderRevisionCannotOverwriteLatestSnapshot() async throws {
        let root = temporaryRoot()
        let store = AISessionStore(rootURL: root)
        let latest = AIChatSession(title: "最新状态")
        let stale = AIChatSession(title: "旧状态")

        try await store.save([latest], revision: 2)
        try await store.save([stale], revision: 1)

        let loaded = try await store.load()
        XCTAssertEqual(loaded, [latest])
    }

    func testLatestEmptySnapshotCannotBeRevertedByOlderNonemptySnapshot() async throws {
        let root = temporaryRoot()
        let store = AISessionStore(rootURL: root)
        let deleted = AIChatSession(title: "已经删除")

        try await store.save([], revision: 9)
        try await store.save([deleted], revision: 8)

        let loaded = try await store.load()
        XCTAssertEqual(loaded, [])
    }

    private func temporaryRoot() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }
}
