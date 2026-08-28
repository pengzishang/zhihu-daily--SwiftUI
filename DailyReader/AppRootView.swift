import SwiftUI

// 「设置」并入“我的”页头部，底部保留三项核心导航。
struct AppRootView: View {
    @StateObject private var homeViewModel = AppEnvironment.makeHomeViewModel()
    @StateObject private var aiCoordinator = AppEnvironment.makeAIChatCoordinator()
    @StateObject private var authenticationViewModel = AppEnvironment.makeAuthenticationViewModel()
    @StateObject private var interestProfileViewModel = AppEnvironment.makeInterestProfileViewModel()
    @State private var selectedTab = 0
    @State private var onboardingPresentation: OnboardingPresentation?

    var body: some View {
        TabView(selection: $selectedTab) {
            // 1. Daily (Home)
            NavigationStack {
                HomeView(viewModel: homeViewModel)
                    .enablesInteractiveSwipeBack()
            }
            .tabItem {
                Label("日报", systemImage: "newspaper")
            }
            .tag(0)

            // 2. Hot List
            NavigationStack {
                HotListView(
                    viewModel: AppEnvironment.makeHotListViewModel(),
                    homeViewModel: homeViewModel,
                    makeAnswersViewModel: AppEnvironment.makeAnswersViewModel(questionID:)
                )
                .enablesInteractiveSwipeBack()
            }
            .tabItem {
                Label("热榜", systemImage: "flame")
            }
            .tag(1)

            // 3. Me (bookroom + settings entry)
            NavigationStack {
                MeView(
                    viewModel: homeViewModel,
                    authenticationViewModel: authenticationViewModel,
                    interestProfileViewModel: interestProfileViewModel
                )
                    .enablesInteractiveSwipeBack()
            }
            .tabItem {
                Label("我的", systemImage: "person.crop.circle")
            }
            .tag(2)
        }
        // 全局强调色：靛蓝（蓝黑墨水），覆盖链接、按钮、滑杆等控件
        .tint(DS.indigo)
        .environmentObject(aiCoordinator)
        .fullScreenCover(item: $aiCoordinator.presentation) { presentation in
            AIChatContainer(presentation: presentation, coordinator: aiCoordinator)
                .id(presentation.sessionID)
                .environmentObject(aiCoordinator)
        }
        .fullScreenCover(item: $onboardingPresentation) { presentation in
            CategoryOnboardingView(
                initialCategories: presentation.categories,
                taxonomyStore: AppEnvironment.taxonomyStore,
                classificationStore: AppEnvironment.classificationStore,
                onComplete: { onboardingPresentation = nil }
            )
        }
        .task {
            ArticleWebViewPrewarmer.shared.warmUpIfNeeded()
            await aiCoordinator.loadIfNeeded()
            authenticationViewModel.restoreIfNeeded()
            await prepareCategoryOnboardingIfNeeded()
        }
    }

    /// 首次启动（类目体系未冻结）时，用样本标题归纳候选类目，或退化为内置默认类目，弹出归纳页。
    @MainActor
    private func prepareCategoryOnboardingIfNeeded() async {
        guard !(await AppEnvironment.taxonomyStore.isFrozen) else { return }
        let titles = homeViewModel.inductionSampleTitles()
        let categories: [ArticleCategory]
        if titles.count >= 30,
           let names = await AppEnvironment.makeCategoryInductionService().induce(titles: titles),
           !names.isEmpty {
            categories = names.enumerated().map { index, name in
                ArticleCategory(id: "cat-\(index)", name: name, order: index)
            }
        } else {
            categories = BuiltInCategoryDefaults.categories
        }
        onboardingPresentation = OnboardingPresentation(categories: categories)
    }
}

/// 首次类目归纳页的展示载体（无需网络，纯本地候选类目）。
private struct OnboardingPresentation: Identifiable {
    let id = UUID()
    let categories: [ArticleCategory]
}

private struct EmptyAICredentialStore: AICredentialStoring {
    func loadAPIKey() throws -> String? { nil }
    func saveAPIKey(_ value: String) throws {}
    func deleteAPIKey() throws {}
}

enum AppEnvironment {
    private static let cache = DiskCacheStore()
    private static let service = makeService()
    private static let repository = DailyRepository(service: service, cacheStore: cache)

    /// 共享的分类 / 兴趣 / 类目体系存储（actor，落 Application Support/DailyReader/...）。
    static let classificationStore = ArticleClassificationStore()
    static let interestStore = ReadingInterestStore()
    static let taxonomyStore = CategoryTaxonomyStore()

    private static var _aiConfigurationStore: AIConfigurationStore?

    @MainActor
    static func makeHomeViewModel() -> HomeViewModel {
        HomeViewModel(
            repository: repository,
            articleRepository: repository
        )
    }

    @MainActor
    static func makeDetailViewModel(story: StorySummary) -> ArticleDetailViewModel {
        ArticleDetailViewModel(
            story: story,
            repository: repository,
            metricsRepository: repository,
            classificationService: makeArticleClassificationService(),
            classificationStore: classificationStore,
            interestStore: interestStore,
            taxonomyStore: taxonomyStore
        )
    }

    @MainActor
    static func makeStoryCategoryViewModel(storyID: Int) -> StoryCategoryViewModel {
        StoryCategoryViewModel(
            storyID: storyID,
            classificationStore: classificationStore,
            taxonomyStore: taxonomyStore
        )
    }

    @MainActor
    static func makeInterestProfileViewModel() -> InterestProfileViewModel {
        InterestProfileViewModel(
            classificationStore: classificationStore,
            interestStore: interestStore,
            taxonomyStore: taxonomyStore
        )
    }

    @MainActor
    static func makeStoryMetricsViewModel(storyID: Int) -> StoryMetricsViewModel {
        StoryMetricsViewModel(storyID: storyID, repository: repository)
    }

    @MainActor
    static func makeHotListViewModel() -> HotListViewModel {
        HotListViewModel(repository: repository)
    }

    @MainActor
    static func makeAnswersViewModel(questionID: Int) -> AnswersViewModel {
        AnswersViewModel(repository: repository, questionID: questionID)
    }

    @MainActor
    static func makeAuthenticationViewModel(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> AuthenticationViewModel {
        let service: any AuthenticationServicing
        if arguments.contains("-UITestMode") {
            let scenario = AuthMockScenario(value: environment["MOCK_AUTH_SCENARIO"])
            service = FixtureAuthenticationService(scenario: scenario)
        } else {
            service = UnavailableAuthenticationService(reason: .missingRequiredValues)
        }
        return AuthenticationViewModel(service: service)
    }

    @MainActor
    static func makeAIChatCoordinator() -> AIChatCoordinator {
        AIChatCoordinator(configurationStore: aiConfigurationStore())
    }

    @MainActor
    static func makeArticleClassificationService() -> ArticleClassificationService {
        ArticleClassificationService(configurationStore: aiConfigurationStore())
    }

    @MainActor
    static func makeCategoryInductionService() -> CategoryInductionService {
        CategoryInductionService(configurationStore: aiConfigurationStore())
    }

    @MainActor
    private static func aiConfigurationStore() -> AIConfigurationStore {
        if let existing = _aiConfigurationStore { return existing }
        let store = buildAIConfigurationStore()
        _aiConfigurationStore = store
        return store
    }

    @MainActor
    private static func buildAIConfigurationStore() -> AIConfigurationStore {
        let processInfo = ProcessInfo.processInfo
        if processInfo.arguments.contains("-UITestMode") {
            let suiteName = "DailyReader.UITests.AI"
            let defaults = UserDefaults(suiteName: suiteName) ?? .standard
            defaults.removePersistentDomain(forName: suiteName)
            let builtIns: [AIBuiltInProviderLoader.LoadedProvider]
            if processInfo.environment["MOCK_AI_DEFAULT_SERVICE"] == "1" {
                builtIns = [
                    AIBuiltInProviderLoader.LoadedProvider(
                        profile: AIProviderProfile(
                            id: AIConfigurationStore.defaultProviderID,
                            name: "默认服务",
                            lanes: [
                                AIProviderLaneProfile(
                                    id: "ui-test-lane",
                                    configuration: AIConfiguration(
                                        endpoint: "https://example.com/v1",
                                        model: "ui-test-model",
                                        allowsSearchTools: false
                                    )
                                )
                            ],
                            source: .builtIn
                        ),
                        apiKeys: [:]
                    )
                ]
            } else {
                builtIns = []
            }
            return AIConfigurationStore(
                defaults: defaults,
                credentialStore: EmptyAICredentialStore(),
                builtInProviders: builtIns.map(\.profile)
            )
        }

        let builtIns = AIBuiltInProviderLoader().load()
        let store = AIConfigurationStore(builtInProviders: builtIns.map(\.profile))
        try? store.installBuiltInProviders(
            builtIns.map(\.profile),
            apiKeys: builtIns.reduce(into: [:]) { result, loaded in
                result.merge(loaded.apiKeys) { current, _ in current }
            }
        )
        return store
    }

    static func makeService() -> DailyServiceProtocol {
        let processInfo = ProcessInfo.processInfo
        if processInfo.arguments.contains("-UITestMode") {
            let defaults = UserDefaults.standard
            defaults.removeObject(forKey: "DailyReader.readStoryIDs")
            defaults.removeObject(forKey: "DailyReader.hiddenStories")
            defaults.removeObject(forKey: "DailyReader.favoriteStories")
            defaults.removeObject(forKey: "DailyReader.readStories")
            defaults.removeObject(forKey: HomeInformationDensity.storageKey)

            try? FileManager.default.removeItem(
                at: FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
                    .first!
                    .appendingPathComponent("DailyReaderCache", isDirectory: true)
            )
            let scenario = processInfo.environment["MOCK_SCENARIO"] ?? "latest_success"
            return LocalFixtureDailyService(scenario: scenario)
        }
        return ZhihuDailyService()
    }
}
