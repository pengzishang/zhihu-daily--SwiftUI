import Foundation

enum ArticleDetailPhase: Equatable {
    case idle
    case loading
    case loaded(ArticleDetail, ContentSource)
    case failed(String)
}

@MainActor
final class ArticleDetailViewModel: ObservableObject {
    @Published private(set) var phase: ArticleDetailPhase = .idle
    @Published private(set) var storyMetrics: DailyStoryMetrics?
    @Published private(set) var originalAnswerMetrics: OriginalAnswerMetrics?
    @Published var bannerMessage: String?

    let story: StorySummary
    private let repository: ArticleRepositoryProtocol
    private let metricsRepository: ArticleMetricsRepositoryProtocol?

    /// 后台 AI 分类服务（可选，便于测试 / 无 AI 配置时留空）。
    private let classificationService: ArticleClassificationService?
    /// 分类结果缓存（articleID → 类目）。
    private let classificationStore: ArticleClassificationStore
    /// 阅读兴趣汇总落盘。
    private let interestStore: ReadingInterestStore
    /// 类目体系（冻结后才参与分类与画像）。
    private let taxonomyStore: CategoryTaxonomyStore

    @Published private(set) var categoryName: String?

    init(
        story: StorySummary,
        repository: ArticleRepositoryProtocol,
        metricsRepository: ArticleMetricsRepositoryProtocol? = nil,
        classificationService: ArticleClassificationService? = nil,
        classificationStore: ArticleClassificationStore = ArticleClassificationStore(),
        interestStore: ReadingInterestStore = ReadingInterestStore(),
        taxonomyStore: CategoryTaxonomyStore = CategoryTaxonomyStore()
    ) {
        self.story = story
        self.repository = repository
        self.metricsRepository = metricsRepository
        self.classificationService = classificationService
        self.classificationStore = classificationStore
        self.interestStore = interestStore
        self.taxonomyStore = taxonomyStore
    }

    var shareURL: URL? {
        guard case .loaded(let detail, _) = phase else {
            return nil
        }
        return Self.validShareURL(from: detail.shareURL ?? detail.url)
    }

    var shareTitle: String {
        guard case .loaded(let detail, _) = phase, !detail.title.isEmpty else {
            return story.title
        }
        return detail.title
    }

    var loadedDetailID: Int? {
        guard case .loaded(let detail, _) = phase else { return nil }
        return detail.id
    }

    private static func validShareURL(from rawValue: String?) -> URL? {
        guard
            let rawValue,
            let url = URL(string: rawValue),
            let scheme = url.scheme?.lowercased(),
            ["http", "https"].contains(scheme),
            url.host?.isEmpty == false
        else {
            return nil
        }
        return url
    }

    func load() async {
        guard phase == .idle else { return }
        async let detailLoad: Void = reload()
        async let metricsLoad: Void = loadStoryMetrics()
        _ = await (detailLoad, metricsLoad)
    }

    func reload() async {
        phase = .loading
        do {
            let result = try await repository.fetchDetail(id: story.id)
            try Task.checkCancellation()
            phase = .loaded(result.value, result.source)
            bannerMessage = nil
            await loadOriginalAnswerMetrics(from: result.value.body)
        } catch is CancellationError {
            return
        } catch {
            phase = .failed("文章加载失败，请稍后重试")
        }
    }

    private func loadStoryMetrics() async {
        guard let metricsRepository else { return }
        do {
            let value = try await metricsRepository.fetchStoryMetrics(id: story.id)
            try Task.checkCancellation()
            storyMetrics = value.hasVisibleValues ? value : nil
        } catch {
            storyMetrics = nil
        }
    }

    private func loadOriginalAnswerMetrics(from body: String?) async {
        guard let metricsRepository,
              let answerID = OriginalAnswerReferenceParser.uniqueAnswerID(in: body)
        else {
            originalAnswerMetrics = nil
            return
        }

        do {
            let value = try await metricsRepository.fetchAnswerMetrics(answerID: answerID)
            try Task.checkCancellation()
            originalAnswerMetrics = value.hasVisibleValues ? value : nil
        } catch {
            originalAnswerMetrics = nil
        }
    }

    // MARK: - 文章分类（后台，fire-and-forget）

    /// 详情加载完成后触发：先查缓存命中（去重），未命中且体系已冻结再走 AI。
    func classifyCurrentArticle() async {
        guard let service = classificationService else { return }
        guard let detail = loadedDetail, let body = detail.body, !body.isEmpty else { return }

        if let existing = await classificationStore.classification(for: story.id) {
            categoryName = await resolveName(for: existing.categoryID)
            return
        }

        guard let taxonomy = await taxonomyStore.load(), taxonomy.isFrozen else { return }
        let plainText = AIArticleContextBuilder.extractText(from: body)
        let result = await service.classify(articleID: story.id, title: detail.title, text: plainText, taxonomy: taxonomy)
        await classificationStore.save(result)
        categoryName = taxonomy.category(byID: result.categoryID)?.name
    }

    // MARK: - 阅读信号采集（落盘）

    /// 一次阅读会话结束（退出详情 / 进入后台前）提交信号。
    func recordReadingSession(
        maxScrollPercent: Double,
        dwellSeconds: Double,
        isFavorited: Bool,
        isHidden: Bool
    ) {
        let signal = ReadingSessionSignal(
            articleID: story.id,
            maxScrollPercent: maxScrollPercent,
            dwellSeconds: dwellSeconds,
            isFavorited: isFavorited,
            isHidden: isHidden
        )
        Task {
            await interestStore.record(signal)
        }
    }

    private var loadedDetail: ArticleDetail? {
        if case .loaded(let detail, _) = phase { return detail }
        return nil
    }

    private func resolveName(for categoryID: String) async -> String? {
        guard let taxonomy = await taxonomyStore.load() else { return nil }
        return taxonomy.category(byID: categoryID)?.name
    }
}
