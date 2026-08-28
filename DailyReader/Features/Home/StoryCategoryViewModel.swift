import Foundation

/// 行视图用 ViewModel：从存储读类目并解析展示名（含是否为「其他」兜底）。
@MainActor
final class StoryCategoryViewModel: ObservableObject {
    @Published private(set) var categoryName: String?
    @Published private(set) var isOtherCategory = false

    private let storyID: Int
    private let classificationStore: ArticleClassificationStore
    private let taxonomyStore: CategoryTaxonomyStore

    init(
        storyID: Int,
        classificationStore: ArticleClassificationStore,
        taxonomyStore: CategoryTaxonomyStore
    ) {
        self.storyID = storyID
        self.classificationStore = classificationStore
        self.taxonomyStore = taxonomyStore
    }

    func load() async {
        guard let cls = await classificationStore.classification(for: storyID) else { return }
        guard let taxonomy = await taxonomyStore.load() else { return }
        guard let category = taxonomy.category(byID: cls.categoryID) else { return }
        categoryName = category.name
        isOtherCategory = category.isOther
    }
}
