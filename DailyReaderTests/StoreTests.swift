import XCTest
@testable import DailyReader

final class StoreTests: XCTestCase {
    private func temporaryRoot() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    func testClassificationStoreRoundTrip() async {
        let root = temporaryRoot()
        let store1 = ArticleClassificationStore(rootURL: root)
        await store1.save(
            ArticleClassification(articleID: 5, categoryID: "tech", confidence: 0.9, source: .remote)
        )

        let store2 = ArticleClassificationStore(rootURL: root)
        let loaded = await store2.classification(for: 5)
        XCTAssertEqual(loaded?.categoryID, "tech")
        XCTAssertEqual(loaded?.confidence, 0.9, accuracy: 0.0001)
    }

    func testInterestStoreMergesSessions() async {
        let root = temporaryRoot()
        let store1 = ReadingInterestStore(rootURL: root)
        await store1.record(
            ReadingSessionSignal(articleID: 1, maxScrollPercent: 0.5, dwellSeconds: 30, isFavorited: false, isHidden: false)
        )
        await store1.record(
            ReadingSessionSignal(articleID: 1, maxScrollPercent: 0.8, dwellSeconds: 20, isFavorited: true, isHidden: false)
        )

        let store2 = ReadingInterestStore(rootURL: root)
        let record = await store2.record(for: 1)
        XCTAssertEqual(record?.dwellSeconds, 50, accuracy: 0.0001)
        XCTAssertEqual(record?.maxScrollPercent, 0.8, accuracy: 0.0001)
        XCTAssertEqual(record?.readCount, 2)
        XCTAssertTrue(record?.isFavorited == true)
    }

    func testInterestStoreKeepsMaxScrollAndResetsHidden() async {
        let root = temporaryRoot()
        let store = ReadingInterestStore(rootURL: root)
        await store.record(
            ReadingSessionSignal(articleID: 2, maxScrollPercent: 0.9, dwellSeconds: 10, isFavorited: false, isHidden: false)
        )
        await store.record(
            ReadingSessionSignal(articleID: 2, maxScrollPercent: 0.4, dwellSeconds: 5, isFavorited: false, isHidden: true)
        )
        let record = await store.record(for: 2)
        XCTAssertEqual(record?.maxScrollPercent, 0.9, accuracy: 0.0001)
        XCTAssertEqual(record?.dwellSeconds, 15, accuracy: 0.0001)
        XCTAssertTrue(record?.isHidden == true)
    }

    func testTaxonomyStoreRoundTrip() async {
        let root = temporaryRoot()
        let store1 = CategoryTaxonomyStore(rootURL: root)
        let taxonomy = CategoryTaxonomy(
            categories: [ArticleCategory(id: "tech", name: "科技")],
            isFrozen: true,
            frozenAt: Date()
        )
        await store1.save(taxonomy)

        let store2 = CategoryTaxonomyStore(rootURL: root)
        let loaded = await store2.load()
        XCTAssertTrue(loaded?.isFrozen == true)
        XCTAssertEqual(loaded?.categories.first?.name, "科技")
    }

    func testTaxonomyStoreReportsFrozenState() async {
        let root = temporaryRoot()
        let store = CategoryTaxonomyStore(rootURL: root)
        XCTAssertFalse(store.isFrozen)
        await store.save(CategoryTaxonomy(categories: [], isFrozen: true))
        XCTAssertTrue(store.isFrozen)
    }
}
