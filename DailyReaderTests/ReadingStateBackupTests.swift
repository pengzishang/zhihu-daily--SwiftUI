import XCTest
import Foundation
@testable import DailyReader

/// 阅读状态「备份 / 恢复」功能测试。
///
/// 被测实现位于 `HomeViewModel.swift`（`exportState` / `importState` / 私有 `mergeStories`），
/// 以及 `PersistentStories.swift`（`HiddenStory` / `FavoriteStory` / `ReadStory`，其中 `ReadStory`
/// 带有自定义 `init(from:)`）。
///
/// 本文件仅新增测试，不修改任何实现文件。沙箱环境无法运行 `xcodebuild`，以下断言基于
/// 静态类型 / 可访问性审查，需由用户在正式 Xcode 中回归。
@MainActor
final class ReadingStateBackupTests: XCTestCase {

    // MARK: - 测试环境清理

    /// 与 HomeViewModel 持久化状态对应的 UserDefaults 键（跨测试共享进程，必须清理）。
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
        for key in persistedStoryStateKeys {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    // MARK: - 测试桩（轻量，避免触碰真实 Keychain / 网络）

    /// 不依赖任何真实数据源的 HomeRepository 桩；备份/恢复测试不触发任何仓库调用。
    private final class StubHomeRepository: HomeRepositoryProtocol {
        func loadHomeFeed() -> AsyncThrowingStream<HomeFeedEvent, Error> {
            AsyncThrowingStream { continuation in
                continuation.finish()
            }
        }

        func refreshHomeFeed(current: HomeFeedSnapshot) async throws -> RepositoryValue<HomeFeedSnapshot> {
            RepositoryValue(
                value: HomeFeedSnapshot(sections: [], topStories: [], historyCursor: nil),
                source: .network
            )
        }

        func loadMore(before oldestDate: String, current: HomeFeedSnapshot) async throws -> RepositoryValue<HomeFeedSnapshot> {
            RepositoryValue(
                value: HomeFeedSnapshot(sections: [], topStories: [], historyCursor: nil),
                source: .network
            )
        }
    }

    /// 内存版 ReadingStateBackingUp 桩，隔离 Keychain 副作用。
    private final class InMemoryReadingStateBackup: ReadingStateBackingUp, @unchecked Sendable {
        private var store: [String: Data] = [:]

        func read(account: String) throws -> Data? { store[account] }

        func save(_ data: Data, account: String) throws { store[account] = data }

        func delete(account: String) throws { store.removeValue(forKey: account) }
    }

    private func makeViewModel() -> HomeViewModel {
        HomeViewModel(
            repository: StubHomeRepository(),
            readingStateBackup: InMemoryReadingStateBackup()
        )
    }

    // MARK: - 样本构造辅助

    private func sampleStory(id: Int, title: String) -> StorySummary {
        StorySummary(id: id, title: title)
    }

    private func makeBackup(
        schemaVersion: Int = 1,
        appVersion: String = "1.2.3",
        exportDate: Date = Date(timeIntervalSince1970: 1_700_000_000),
        readStoryIDs: [Int] = [],
        hiddenStories: [HiddenStory] = [],
        favoriteStories: [FavoriteStory] = [],
        readStories: [ReadStory] = []
    ) -> ReadingStateBackup {
        ReadingStateBackup(
            schemaVersion: schemaVersion,
            appVersion: appVersion,
            exportDate: exportDate,
            readStoryIDs: readStoryIDs,
            hiddenStories: hiddenStories,
            favoriteStories: favoriteStories,
            readStories: readStories
        )
    }

    /// 复刻 HomeViewModel.mergeStories 的去重算法（实例方法为 private，无法直接调用），
    /// 用于「逻辑等价验证」：现有项优先、按 id 去重、保持顺序、幂等。
    private func mergeStoriesEquivalent<T>(_ current: [T], _ incoming: [T]) -> [T]
    where T: Identifiable, T.ID == Int {
        var seen = Set<Int>()
        var merged: [T] = []
        for item in current + incoming {
            guard !seen.contains(item.id) else { continue }
            seen.insert(item.id)
            merged.append(item)
        }
        return merged
    }

    // MARK: - 1. 序列化往返（最高优先级）

    /// 构造含 HiddenStory / FavoriteStory / ReadStory（含 Date 字段）样本的 ReadingStateBackup，
    /// 用 `.prettyPrinted, .sortedKeys` 编码 → 默认 JSONDecoder 解码 → 断言所有字段逐一相等。
    func testReadingStateBackupCodableRoundTrip() throws {
        let exportDate = Date(timeIntervalSince1970: 1_700_000_000)
        let readAt = Date(timeIntervalSince1970: 1_700_000_123.5)

        let backup = makeBackup(
            schemaVersion: 1,
            appVersion: "2.3.4",
            exportDate: exportDate,
            readStoryIDs: [10, 3, 7],
            hiddenStories: [
                HiddenStory(date: "2024-01-01", story: sampleStory(id: 1, title: "隐藏-A")),
                HiddenStory(date: "2024-02-02", story: sampleStory(id: 6, title: "隐藏-F"))
            ],
            favoriteStories: [
                FavoriteStory(date: "2024-03-03", story: sampleStory(id: 2, title: "收藏-B"))
            ],
            readStories: [
                ReadStory(date: "2024-04-04", story: sampleStory(id: 3, title: "已读-C"), readAt: readAt),
                ReadStory(date: "2024-05-05", story: sampleStory(id: 8, title: "已读-H"))
            ]
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(backup)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(ReadingStateBackup.self, from: data)

        XCTAssertEqual(decoded.schemaVersion, 1)
        XCTAssertEqual(decoded.appVersion, "2.3.4")
        XCTAssertEqual(decoded.exportDate, exportDate)
        XCTAssertEqual(decoded.readStoryIDs, [10, 3, 7])
        XCTAssertEqual(decoded.hiddenStories, backup.hiddenStories)
        XCTAssertEqual(decoded.favoriteStories, backup.favoriteStories)
        XCTAssertEqual(decoded.readStories, backup.readStories)

        // 重点：ReadStory 的自定义 init(from:) 必须能安全往返其 Date 字段。
        XCTAssertEqual(decoded.readStories.first?.readAt, readAt)
        XCTAssertEqual(decoded.readStories.first?.date, "2024-04-04")
    }

    /// 验证 ReadStory 自定义 init(from:) 的容错：缺少 readAt 时回退为 Date()，不应抛错。
    func testReadStoryCustomDecoderHandlesMissingReadAt() throws {
        let json = """
        {
            "date" : "2024-01-01",
            "story" : { "id" : 1, "title" : "X" }
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(ReadStory.self, from: json)
        XCTAssertEqual(decoded.id, 1)
        XCTAssertEqual(decoded.date, "2024-01-01")
        // readAt 由 decodeIfPresent(Date.self) ?? Date() 兜底，必然为有效 Date。
        XCTAssertNotNil(decoded.readAt)
    }

    /// 验证 ReadStory 自定义 init(from:) 在 readAt 存在时使用提供的值（而非回退）。
    /// 通过「编码 → 解码」同源往返，避免手写 JSON 数字与默认 dateDecodingStrategy
    /// （.deferredToDate，以 2001 参考纪元计）产生的人类可读数值歧义。
    func testReadStoryDecoderUsesProvidedReadAt() throws {
        let readAt = Date(timeIntervalSince1970: 1_700_000_999.25)
        let original = ReadStory(date: "2024-01-01", story: sampleStory(id: 1, title: "X"), readAt: readAt)
        let data = try JSONEncoder().encode(original)

        let decoded = try JSONDecoder().decode(ReadStory.self, from: data)
        XCTAssertEqual(decoded.readAt, readAt)
    }

    // MARK: - 2. 错误路径

    /// 喂入非 JSON 的 Data 给 JSONDecoder().decode(ReadingStateBackup.self, ...) 必须抛错。
    func testInvalidJSONThrowsOnDecode() {
        let garbage = Data("this is not json".utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(ReadingStateBackup.self, from: garbage))
    }

    /// 两个 ReadingStateImportError case 的 errorDescription 必须非空（中文文案）。
    func testImportErrorDescriptionsAreNonEmpty() {
        let invalid = ReadingStateImportError.invalidFile(underlying: NSError(domain: "t", code: 1))
        let unsupported = ReadingStateImportError.unsupportedSchema(version: 2)

        let invalidDesc = invalid.errorDescription
        let unsupportedDesc = unsupported.errorDescription

        XCTAssertNotNil(invalidDesc)
        XCTAssertFalse(invalidDesc?.isEmpty ?? true)
        XCTAssertNotNil(unsupportedDesc)
        XCTAssertFalse(unsupportedDesc?.isEmpty ?? true)

        // 版本号应出现在文案中，便于用户定位。
        XCTAssertTrue(unsupportedDesc?.contains("2") ?? false)
    }

    /// importState 喂入损坏数据应抛 .invalidFile。
    func testImportStateThrowsInvalidFileOnCorruptedData() throws {
        let viewModel = makeViewModel()
        let garbage = Data("garbage-bytes".utf8)

        XCTAssertThrowsError(try viewModel.importState(garbage)) { error in
            guard let importError = error as? ReadingStateImportError else {
                return XCTFail("期望 ReadingStateImportError，实际得到 \(type(of: error))")
            }
            guard case .invalidFile = importError else {
                return XCTFail("期望 .invalidFile，实际得到 \(importError)")
            }
        }
    }

    /// schema 版本高于当前（>1）应抛 .unsupportedSchema(version:)。
    func testImportStateRejectsUnsupportedSchema() throws {
        let viewModel = makeViewModel()
        let backup = makeBackup(schemaVersion: 99, readStoryIDs: [1])
        let data = try JSONEncoder().encode(backup)

        XCTAssertThrowsError(try viewModel.importState(data)) { error in
            guard let importError = error as? ReadingStateImportError else {
                return XCTFail("期望 ReadingStateImportError，实际得到 \(type(of: error))")
            }
            guard case .unsupportedSchema(let version) = importError else {
                return XCTFail("期望 .unsupportedSchema，实际得到 \(importError)")
            }
            XCTAssertEqual(version, 99)
        }
    }

    /// schema 版本等于当前（==1）应被接受（不抛 unsupportedSchema）。
    func testImportStateAcceptsCurrentSchema() throws {
        let viewModel = makeViewModel()
        let backup = makeBackup(schemaVersion: 1, readStoryIDs: [1])
        let data = try JSONEncoder().encode(backup)
        XCTAssertNoThrow(try viewModel.importState(data))
    }

    // MARK: - 3. 合并 / 导入语义

    /// 当前状态为空时导入备份：等同于整体恢复，全部明细应被还原。
    func testImportStateRestoresAllDetailsWhenCurrentEmpty() throws {
        let viewModel = makeViewModel()

        let backup = makeBackup(
            schemaVersion: 1,
            readStoryIDs: [3, 4, 5],
            hiddenStories: [HiddenStory(date: "2024-01-01", story: sampleStory(id: 1, title: "A"))],
            favoriteStories: [FavoriteStory(date: "2024-01-02", story: sampleStory(id: 2, title: "B"))],
            readStories: [ReadStory(date: "2024-01-03", story: sampleStory(id: 3, title: "C"), readAt: Date(timeIntervalSince1970: 1_700_000_000))]
        )
        let data = try JSONEncoder().encode(backup)

        try viewModel.importState(data)

        XCTAssertEqual(viewModel.readStoryIDs, Set([3, 4, 5]))
        XCTAssertEqual(viewModel.hiddenStories.count, 1)
        XCTAssertEqual(viewModel.hiddenStories.first?.id, 1)
        XCTAssertEqual(viewModel.favoriteStories.count, 1)
        XCTAssertEqual(viewModel.favoriteStories.first?.id, 2)
        XCTAssertEqual(viewModel.readStories.count, 1)
        XCTAssertEqual(viewModel.readStories.first?.id, 3)
    }

    /// 已有部分状态再导入：readStoryIDs 取并集；明细按 id 去重且「现有优先」，数量正确、顺序正确。
    func testImportStateMergesWithExistingPriority() throws {
        let viewModel = makeViewModel()

        // 注入「现有」状态
        viewModel.hideStory(sampleStory(id: 1, title: "A"), date: "2024-01-01")
        viewModel.toggleFavorite(sampleStory(id: 2, title: "B"), date: "2024-01-02")
        viewModel.markStoryRead(sampleStory(id: 3, title: "C"), date: "2024-01-03")

        // 捕获现有 readAt，用于验证「现有优先」未被导入值覆盖
        let existingReadAt = try XCTUnwrap(viewModel.readStories.first(where: { $0.id == 3 })?.readAt)

        // 备份中含有与现有同 id 的明细（但字段不同）以及若干新 id
        let backup = makeBackup(
            schemaVersion: 1,
            readStoryIDs: [3, 4, 5],
            hiddenStories: [
                HiddenStory(date: "2099-01-01", story: sampleStory(id: 1, title: "A-modified")),
                HiddenStory(date: "2024-01-06", story: sampleStory(id: 6, title: "F"))
            ],
            favoriteStories: [
                FavoriteStory(date: "2099-01-02", story: sampleStory(id: 2, title: "B-modified")),
                FavoriteStory(date: "2024-01-07", story: sampleStory(id: 7, title: "G"))
            ],
            readStories: [
                ReadStory(date: "2099-01-03", story: sampleStory(id: 3, title: "C-modified"), readAt: Date(timeIntervalSince1970: 1_799_999_999)),
                ReadStory(date: "2024-01-08", story: sampleStory(id: 8, title: "H"))
            ]
        )
        let data = try JSONEncoder().encode(backup)

        try viewModel.importState(data)

        // 已读 ID：并集
        XCTAssertEqual(viewModel.readStoryIDs, Set([3, 4, 5]))

        // 冷宫：现有 id=1 优先（保留原 date/title），新增 id=6 追加在后
        XCTAssertEqual(viewModel.hiddenStories.count, 2)
        XCTAssertEqual(viewModel.hiddenStories[0].id, 1)
        XCTAssertEqual(viewModel.hiddenStories[0].date, "2024-01-01")
        XCTAssertEqual(viewModel.hiddenStories[0].story.title, "A")
        XCTAssertEqual(viewModel.hiddenStories[1].id, 6)

        // 收藏：同上
        XCTAssertEqual(viewModel.favoriteStories.count, 2)
        XCTAssertEqual(viewModel.favoriteStories[0].id, 2)
        XCTAssertEqual(viewModel.favoriteStories[0].date, "2024-01-02")
        XCTAssertEqual(viewModel.favoriteStories[0].story.title, "B")
        XCTAssertEqual(viewModel.favoriteStories[1].id, 7)

        // 已读明细：现有 id=3 优先（保留原 readAt），新增 id=8 追加在后
        XCTAssertEqual(viewModel.readStories.count, 2)
        XCTAssertEqual(viewModel.readStories[0].id, 3)
        XCTAssertEqual(viewModel.readStories[0].readAt, existingReadAt)
        XCTAssertEqual(viewModel.readStories[0].date, "2024-01-03")
        XCTAssertEqual(viewModel.readStories[1].id, 8)
    }

    /// 端到端：exportState 导出 → 新实例 importState 导入 → 状态应完全一致。
    func testExportStateThenImportStateRoundTrip() throws {
        let source = makeViewModel()
        source.hideStory(sampleStory(id: 1, title: "A"), date: "2024-01-01")
        source.toggleFavorite(sampleStory(id: 2, title: "B"), date: "2024-01-02")
        source.markStoryRead(sampleStory(id: 3, title: "C"), date: "2024-01-03")

        let data = try source.exportState()

        // 导出的数据能解码为合法的 ReadingStateBackup，且 appVersion 非空
        let decodedEnvelope = try JSONDecoder().decode(ReadingStateBackup.self, from: data)
        XCTAssertFalse(decodedEnvelope.appVersion.isEmpty)

        let target = makeViewModel()
        try target.importState(data)

        XCTAssertEqual(target.readStoryIDs, source.readStoryIDs)
        XCTAssertEqual(target.hiddenStories, source.hiddenStories)
        XCTAssertEqual(target.favoriteStories, source.favoriteStories)
        XCTAssertEqual(target.readStories, source.readStories)
    }

    /// 逻辑等价验证：复刻 mergeStories 的去重算法，确认「现有优先 + 按 id 去重 + 保持顺序」。
    /// 说明：HomeViewModel.mergeStories 为 private 实例方法，此处用等价最小复刻验证算法正确性。
    func testMergeStoriesDeduplicationLogicEquivalence() {
        let current = [
            HiddenStory(date: "2024-01-01", story: sampleStory(id: 1, title: "A")),
            HiddenStory(date: "2024-01-02", story: sampleStory(id: 2, title: "B"))
        ]
        let incoming = [
            HiddenStory(date: "2099-01-01", story: sampleStory(id: 1, title: "A-new")),
            HiddenStory(date: "2024-01-03", story: sampleStory(id: 3, title: "C"))
        ]

        let merged = mergeStoriesEquivalent(current, incoming)

        XCTAssertEqual(merged.map(\.id), [1, 2, 3])
        // 现有优先：id=1 保留 current 的字段
        XCTAssertEqual(merged[0].date, "2024-01-01")
        XCTAssertEqual(merged[0].story.title, "A")

        // 幂等性：重复传入相同集合结果不变
        let again = mergeStoriesEquivalent(merged, merged)
        XCTAssertEqual(again.map(\.id), [1, 2, 3])
    }
}
