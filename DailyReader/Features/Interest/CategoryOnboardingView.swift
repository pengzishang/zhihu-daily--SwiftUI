import SwiftUI

/// 「你的阅读类目」归纳冻结页：用户删 / 并 / 改名后冻结体系。
///
/// - 传入 `initialCategories` 为 AI 归纳或内置默认得到的候选类目（不含「其他」兜底）。
/// - 「其他」作为锁定兜底，仅展示、不可删 / 改名 / 合并。
/// - 合并某类目时，会同步把已分类文章中指向它的记录重新映射到目标类目。
struct CategoryOnboardingView: View {
    let initialCategories: [ArticleCategory]
    let taxonomyStore: CategoryTaxonomyStore
    let classificationStore: ArticleClassificationStore
    let onComplete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var categories: [ArticleCategory]

    init(
        initialCategories: [ArticleCategory],
        taxonomyStore: CategoryTaxonomyStore,
        classificationStore: ArticleClassificationStore,
        onComplete: @escaping () -> Void
    ) {
        self.initialCategories = initialCategories
        self.taxonomyStore = taxonomyStore
        self.classificationStore = classificationStore
        self.onComplete = onComplete
        _categories = State(initialValue: initialCategories)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                header
                List {
                    Section {
                        ForEach($categories) { $category in
                            editableRow($category)
                        }
                        .onDelete(perform: delete)
                    }
                    Section {
                        lockedRow(ArticleCategory.other)
                    } header: {
                        Text("兜底类目")
                    }
                }
                .listStyle(.plain)
                .paperListBackground()
            }
            .navigationTitle("你的阅读类目")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { complete() }
                        .font(DS.songBold(15))
                        .foregroundStyle(DS.indigo)
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("你的阅读类目")
                .font(DS.songBlack(26))
                .foregroundStyle(DS.ink)
            Text("我们已为你的阅读归纳出以下类目。你可以删除、合并或重命名，完成后它们将用于自动归类文章。")
                .font(.system(size: 13))
                .foregroundStyle(DS.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    private func editableRow(_ category: Binding<ArticleCategory>) -> some View {
        HStack(spacing: 10) {
            TextField("类目名", text: category.name)
                .font(DS.songBold(15))
                .foregroundStyle(DS.ink)
            Spacer(minLength: 8)
            Menu {
                ForEach(categories.filter { $0.id != category.wrappedValue.id }) { target in
                    Button(target.name) {
                        merge(sourceID: category.wrappedValue.id, into: target.id)
                    }
                }
            } label: {
                Image(systemName: "arrow.2.squarepath")
                    .foregroundStyle(DS.inkSecondary)
            }
            .accessibilityLabel("合并 \(category.wrappedValue.name) 到其它类目")
        }
        .listRowBackground(Color.clear)
    }

    private func lockedRow(_ category: ArticleCategory) -> some View {
        HStack(spacing: 10) {
            Text(category.name)
                .font(DS.songBold(15))
                .foregroundStyle(DS.inkSecondary)
            Spacer(minLength: 8)
            Text("锁定")
                .font(.system(size: 12))
                .foregroundStyle(DS.inkSecondary)
        }
        .listRowBackground(Color.clear)
    }

    private func delete(at offsets: IndexSet) {
        let removable = IndexSet(offsets.filter { !categories[$0].isOther })
        categories.remove(atOffsets: removable)
        reindex()
    }

    private func merge(sourceID: String, into targetID: String) {
        guard let sourceIndex = categories.firstIndex(where: { $0.id == sourceID }),
              categories.contains(where: { $0.id == targetID }) else { return }
        categories.remove(at: sourceIndex)
        reindex()
        Task {
            await classificationStore.remap(categoryID: sourceID, to: targetID)
        }
    }

    private func reindex() {
        for index in categories.indices {
            categories[index].order = index
        }
    }

    private func complete() {
        reindex()
        let taxonomy = CategoryTaxonomy(categories: categories, isFrozen: true, frozenAt: Date())
        Task {
            await taxonomyStore.save(taxonomy)
            onComplete()
        }
    }
}
