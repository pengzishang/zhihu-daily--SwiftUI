import Foundation

/// 兴趣画像 ViewModel：聚合分类 + 兴趣汇总 + 类目体系，调用引擎出榜。
///
/// 仅在类目体系已冻结时计算；否则 `isReady = false`，UI 显示空态。
@MainActor
final class InterestProfileViewModel: ObservableObject {
    @Published private(set) var entries: [CategoryInterestIndex] = []
    @Published private(set) var isReady = false

    private let classificationStore: ArticleClassificationStore
    private let interestStore: ReadingInterestStore
    private let taxonomyStore: CategoryTaxonomyStore

    init(
        classificationStore: ArticleClassificationStore,
        interestStore: ReadingInterestStore,
        taxonomyStore: CategoryTaxonomyStore
    ) {
        self.classificationStore = classificationStore
        self.interestStore = interestStore
        self.taxonomyStore = taxonomyStore
    }

    func load() async {
        guard let taxonomy = await taxonomyStore.load(), taxonomy.isFrozen else {
            isReady = false
            entries = []
            return
        }
        let classifications = await classificationStore.all()
        let records = await interestStore.all()
        entries = InterestIndexEngine.categoryIndex(
            classifications: classifications,
            records: records,
            taxonomy: taxonomy
        )
        isReady = true
    }

    /// 是否完全没有可展示的阅读信号。
    var isEmpty: Bool { entries.allSatisfy { $0.memberCount == 0 } }
}
