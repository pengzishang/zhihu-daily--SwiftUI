import Foundation
import SwiftUI

enum HomePhase: Equatable {
    case idle
    case loading
    case loaded(ContentSource)
    case empty
    case failed(String)

    var contentSource: ContentSource? {
        guard case .loaded(let source) = self else { return nil }
        return source
    }
}

enum HistoryLoadState: Equatable {
    case idle
    case loading
    case failed(String)
}

@MainActor
final class HomeViewModel: ObservableObject {
    @Published private(set) var phase: HomePhase = .idle
    @Published private(set) var topStories: [TopStory] = []
    @Published private(set) var sections: [DailySection] = []
    @Published private(set) var historyLoadState: HistoryLoadState = .idle
    @Published private(set) var historyCursor: String?
    @Published private(set) var readStoryIDs: Set<Int>
    @Published private(set) var hiddenStories: [HiddenStory] = []
    @Published private(set) var favoriteStories: [FavoriteStory] = []
    @Published private(set) var readStories: [ReadStory] = []
    @Published private(set) var immersiveImageURLs: [Int: String] = [:]
    @Published var bannerMessage: String?

    private static let maximumAutomaticHistoryBatchCount = 12
    private static let historyPrefetchRemainingStoryCount = 8

    private let repository: HomeRepositoryProtocol
    private let articleRepository: ArticleRepositoryProtocol?
    private let readingStateBackup: any ReadingStateBackingUp
    private let keychainErrorHandler: @Sendable (Error) -> Void
    private var loadedStoryIDs = Set<Int>()
    private var immersiveImageRequestIDs = Set<Int>()
    private var resolvedImmersiveImageIDs = Set<Int>()
    private var hasAttemptedInitialLoad = false
    private var loadingHistoryCursor: String?
    private let readStoryIDsKey = "DailyReader.readStoryIDs"
    private let hiddenStoriesKey = "DailyReader.hiddenStories"
    private let favoriteStoriesKey = "DailyReader.favoriteStories"
    private let readStoriesKey = "DailyReader.readStories"

    init(
        repository: HomeRepositoryProtocol,
        articleRepository: ArticleRepositoryProtocol? = nil,
        readingStateBackup: any ReadingStateBackingUp = KeychainReadingStateBackup(),
        keychainErrorHandler: @escaping @Sendable (Error) -> Void = { error in
            #if DEBUG
            print("Keychain reading-state operation failed: \(String(describing: error))")
            #endif
        }
    ) {
        self.repository = repository
        self.articleRepository = articleRepository
        self.readingStateBackup = readingStateBackup
        self.keychainErrorHandler = keychainErrorHandler

        let readInitialBackup: (String) -> Data? = { account in
            do {
                return try readingStateBackup.read(account: account)
            } catch {
                keychainErrorHandler(error)
                return nil
            }
        }
        let saveInitialBackup: (Data, String) -> Void = { data, account in
            do {
                try readingStateBackup.save(data, account: account)
            } catch {
                keychainErrorHandler(error)
            }
        }
        let deleteInitialBackup: (String) -> Void = { account in
            do {
                try readingStateBackup.delete(account: account)
            } catch {
                keychainErrorHandler(error)
            }
        }

        let readStoryIDsKey = "DailyReader.readStoryIDs"
        let hiddenStoriesKey = "DailyReader.hiddenStories"
        let favoriteStoriesKey = "DailyReader.favoriteStories"
        let readStoriesKey = "DailyReader.readStories"
        let defaults = UserDefaults.standard
        let readIDs = defaults.array(forKey: readStoryIDsKey) as? [Int]
        let hiddenData = defaults.data(forKey: hiddenStoriesKey)
        let favoriteData = defaults.data(forKey: favoriteStoriesKey)
        let readData = defaults.data(forKey: readStoriesKey)
        
        let isUserDefaultsEmpty = (readIDs == nil || readIDs!.isEmpty) &&
                                  (hiddenData == nil) &&
                                  (favoriteData == nil) &&
                                  (readData == nil)
                                  
        if isUserDefaultsEmpty {
            var restoredReadIDs: [Int]? = nil
            var restoredHidden: [HiddenStory]? = nil
            var restoredFavorite: [FavoriteStory]? = nil
            var restoredRead: [ReadStory]? = nil
            
            if let data = readInitialBackup(readStoryIDsKey) {
                if ProcessInfo.processInfo.environment["MOCK_KEYCHAIN_STATUS"] == "corrupted" {
                    deleteInitialBackup(readStoryIDsKey)
                } else {
                    do {
                        let list = try JSONDecoder().decode([Int].self, from: data)
                        restoredReadIDs = list
                        defaults.set(list, forKey: readStoryIDsKey)
                    } catch {
                        deleteInitialBackup(readStoryIDsKey)
                        defaults.removeObject(forKey: readStoryIDsKey)
                    }
                }
            }
            
            if let data = readInitialBackup(hiddenStoriesKey) {
                if ProcessInfo.processInfo.environment["MOCK_KEYCHAIN_STATUS"] == "corrupted" {
                    deleteInitialBackup(hiddenStoriesKey)
                } else {
                    do {
                        let list = try JSONDecoder().decode([HiddenStory].self, from: data)
                        restoredHidden = list
                        defaults.set(data, forKey: hiddenStoriesKey)
                    } catch {
                        deleteInitialBackup(hiddenStoriesKey)
                        defaults.removeObject(forKey: hiddenStoriesKey)
                    }
                }
            }
            
            if let data = readInitialBackup(favoriteStoriesKey) {
                if ProcessInfo.processInfo.environment["MOCK_KEYCHAIN_STATUS"] == "corrupted" {
                    deleteInitialBackup(favoriteStoriesKey)
                } else {
                    do {
                        let list = try JSONDecoder().decode([FavoriteStory].self, from: data)
                        restoredFavorite = list
                        defaults.set(data, forKey: favoriteStoriesKey)
                    } catch {
                        deleteInitialBackup(favoriteStoriesKey)
                        defaults.removeObject(forKey: favoriteStoriesKey)
                    }
                }
            }
            
            if let data = readInitialBackup(readStoriesKey) {
                if ProcessInfo.processInfo.environment["MOCK_KEYCHAIN_STATUS"] == "corrupted" {
                    deleteInitialBackup(readStoriesKey)
                } else {
                    do {
                        let list = try JSONDecoder().decode([ReadStory].self, from: data)
                        restoredRead = list
                        defaults.set(data, forKey: readStoriesKey)
                    } catch {
                        deleteInitialBackup(readStoriesKey)
                        defaults.removeObject(forKey: readStoriesKey)
                    }
                }
            }
            
            self.readStoryIDs = Set(restoredReadIDs ?? [])
            self.hiddenStories = restoredHidden ?? []
            self.favoriteStories = restoredFavorite ?? []
            self.readStories = restoredRead ?? []
        } else {
            self.readStoryIDs = Set(readIDs ?? [])
            
            if let data = hiddenData,
               let list = try? JSONDecoder().decode([HiddenStory].self, from: data) {
                self.hiddenStories = list
            } else {
                self.hiddenStories = []
            }
            
            if let data = favoriteData,
               let list = try? JSONDecoder().decode([FavoriteStory].self, from: data) {
                self.favoriteStories = list
            } else {
                self.favoriteStories = []
            }
            
            if let data = readData,
               let list = try? JSONDecoder().decode([ReadStory].self, from: data) {
                self.readStories = list
            } else {
                self.readStories = []
            }
            
            // Check if Keychain is empty, and if so, perform reverse backup (T2-KC-04)
            let kcReadData = readInitialBackup(readStoryIDsKey)
            if kcReadData == nil {
                if !self.readStoryIDs.isEmpty {
                    if let data = try? JSONEncoder().encode(Array(self.readStoryIDs)) {
                        saveInitialBackup(data, readStoryIDsKey)
                    }
                }
                if let data = hiddenData {
                    saveInitialBackup(data, hiddenStoriesKey)
                }
                if let data = favoriteData {
                    saveInitialBackup(data, favoriteStoriesKey)
                }
                if let data = readData {
                    saveInitialBackup(data, readStoriesKey)
                }
            }
        }
    }

    private func readBackup(for account: String) -> Data? {
        do {
            return try readingStateBackup.read(account: account)
        } catch {
            keychainErrorHandler(error)
            return nil
        }
    }

    private func saveBackup(_ data: Data, for account: String) {
        do {
            try readingStateBackup.save(data, account: account)
        } catch {
            keychainErrorHandler(error)
        }
    }

    private func deleteBackup(for account: String) {
        do {
            try readingStateBackup.delete(account: account)
        } catch {
            keychainErrorHandler(error)
        }
    }

    // MARK: - Filtered computed sections
    var visibleSections: [DailySection] {
        sections.map { section in
            var sec = section
            sec.stories = section.stories.filter { story in
                !isStoryHidden(story.id) && !isStoryFavorited(story.id) && !isStoryRead(story.id)
            }
            return sec
        }.filter { !$0.stories.isEmpty }
    }

    var hiddenSections: [DailySection] {
        let grouped = Dictionary(grouping: hiddenStories, by: { $0.date })
        return grouped.map { (date, list) in
            DailySection(date: date, stories: list.map { $0.story })
        }
        .filter { !$0.stories.isEmpty }
        .sorted(by: { $0.date > $1.date })
    }

    var favoriteSections: [DailySection] {
        let visibleFavorites = favoriteStories.filter { !isStoryHidden($0.id) }
        let grouped = Dictionary(grouping: visibleFavorites, by: { $0.date })
        return grouped.map { (date, list) in
            DailySection(date: date, stories: list.map { $0.story })
        }
        .filter { !$0.stories.isEmpty }
        .sorted(by: { $0.date > $1.date })
    }

    var readSections: [DailySection] {
        let visibleRead = readStories.filter { !isStoryHidden($0.id) && !isStoryFavorited($0.id) }
        let grouped = Dictionary(grouping: visibleRead, by: { $0.date })
        return grouped.map { (date, list) in
            DailySection(date: date, stories: list.map { $0.story })
        }
        .filter { !$0.stories.isEmpty }
        .sorted(by: { $0.date > $1.date })
    }

    var visibleReadStories: [ReadStory] {
        readStories
            .filter { !isStoryHidden($0.id) && !isStoryFavorited($0.id) }
            .sorted(by: { $0.readAt > $1.readAt })
    }

    // MARK: - API Actions
    func load() async {
        guard !hasAttemptedInitialLoad else { return }
        hasAttemptedInitialLoad = true
        phase = .loading

        do {
            for try await event in repository.loadHomeFeed() {
                switch event {
                case .cached(let value):
                    apply(value)
                    bannerMessage = "当前离线，正在显示缓存内容"
                case .refreshed(let value):
                    withAnimation {
                        apply(value)
                    }
                    bannerMessage = nil
                }
            }
        } catch {
            phase = .failed("网络不可用，请检查连接后重试")
        }
    }

    func refresh() async {
        do {
            let value = try await repository.refreshHomeFeed(current: snapshot)
            withAnimation {
                apply(value)
            }
            bannerMessage = nil
        } catch {
            bannerMessage = sections.isEmpty ? "网络不可用，请检查连接后重试" : "刷新失败，已保留上次内容"
            if sections.isEmpty {
                phase = .failed("网络不可用，请检查连接后重试")
            }
        }
    }

    func loadMore() async {
        guard historyLoadState != .loading,
              let cursor = historyCursor ?? sections.last?.date,
              loadingHistoryCursor != cursor
        else {
            return
        }

        loadingHistoryCursor = cursor
        historyLoadState = .loading
        defer { loadingHistoryCursor = nil }

        do {
            let initialVisibleStoryIDs = Set(visibleSections.flatMap(\.stories).map(\.id))
            var nextCursor = cursor
            var currentSnapshot = snapshot
            var latestSource = phase.contentSource ?? .network

            for _ in 0..<Self.maximumAutomaticHistoryBatchCount {
                let value = try await repository.loadMore(
                    before: nextCursor,
                    current: currentSnapshot
                )
                currentSnapshot = value.value
                latestSource = value.source

                let candidateVisibleIDs = visibleStoryIDs(in: currentSnapshot)
                if !candidateVisibleIDs.subtracting(initialVisibleStoryIDs).isEmpty {
                    apply(value)
                    historyLoadState = .idle
                    return
                }

                guard let advancedCursor = currentSnapshot.historyCursor,
                      advancedCursor != nextCursor
                else {
                    apply(value)
                    historyLoadState = .idle
                    return
                }
                nextCursor = advancedCursor
            }

            apply(RepositoryValue(value: currentSnapshot, source: latestSource))
            historyLoadState = .idle
        } catch {
            historyLoadState = .failed("加载历史失败，已保留当前内容")
        }
    }

    func loadImmersiveImage(for story: StorySummary) async {
        guard !resolvedImmersiveImageIDs.contains(story.id) else { return }

        if let topStoryImage = topStories.first(where: { $0.id == story.id })?.image,
           !topStoryImage.isEmpty {
            immersiveImageURLs[story.id] = topStoryImage
            resolvedImmersiveImageIDs.insert(story.id)
            return
        }

        guard let articleRepository,
              immersiveImageRequestIDs.insert(story.id).inserted
        else {
            return
        }
        defer { immersiveImageRequestIDs.remove(story.id) }

        do {
            let result = try await articleRepository.fetchDetail(id: story.id)
            try Task.checkCancellation()
            if let imageURL = Self.preferredImmersiveImageURL(from: result.value) {
                immersiveImageURLs[story.id] = imageURL
            }
            resolvedImmersiveImageIDs.insert(story.id)
        } catch {
            return
        }
    }

    static func preferredImmersiveImageURL(from detail: ArticleDetail) -> String? {
        [detail.image, detail.images.first]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }

    // MARK: - Status updates & Persistence
    func markStoryRead(_ storyID: Int) {
        guard readStoryIDs.insert(storyID).inserted else { return }
        let array = Array(readStoryIDs)
        UserDefaults.standard.set(array, forKey: readStoryIDsKey)
        if let data = try? JSONEncoder().encode(array) {
            saveBackup(data, for: readStoryIDsKey)
        }
    }

    func markStoryRead(_ story: StorySummary, date: String) {
        readStoryIDs.insert(story.id)
        let array = Array(readStoryIDs)
        UserDefaults.standard.set(array, forKey: readStoryIDsKey)
        if let data = try? JSONEncoder().encode(array) {
            saveBackup(data, for: readStoryIDsKey)
        }
        if let index = readStories.firstIndex(where: { $0.id == story.id }) {
            let old = readStories.remove(at: index)
            readStories.append(ReadStory(date: old.date, story: old.story, readAt: Date()))
        } else {
            readStories.append(ReadStory(date: date, story: story, readAt: Date()))
        }
        saveReadStories()
    }

    func isStoryRead(_ storyID: Int) -> Bool {
        readStoryIDs.contains(storyID)
    }

    func hideStory(_ story: StorySummary, date: String) {
        guard !hiddenStories.contains(where: { $0.id == story.id }) else { return }
        hiddenStories.append(HiddenStory(date: date, story: story))
        saveHiddenStories()
    }

    func restoreStory(_ storyID: Int) {
        hiddenStories.removeAll(where: { $0.id == storyID })
        saveHiddenStories()
    }

    func isStoryHidden(_ storyID: Int) -> Bool {
        hiddenStories.contains(where: { $0.id == storyID })
    }

    func toggleFavorite(_ story: StorySummary, date: String) {
        if let index = favoriteStories.firstIndex(where: { $0.id == story.id }) {
            favoriteStories.remove(at: index)
            restoreStory(story.id)
        } else {
            favoriteStories.append(FavoriteStory(date: date, story: story))
        }
        saveFavoriteStories()
    }

    func isStoryFavorited(_ storyID: Int) -> Bool {
        favoriteStories.contains(where: { $0.id == storyID })
    }

    func toggleRead(_ story: StorySummary, date: String) {
        if readStoryIDs.contains(story.id) {
            readStoryIDs.remove(story.id)
            readStories.removeAll(where: { $0.id == story.id })
        } else {
            readStoryIDs.insert(story.id)
            readStories.removeAll(where: { $0.id == story.id })
            readStories.append(ReadStory(date: date, story: story, readAt: Date()))
        }
        let array = Array(readStoryIDs)
        UserDefaults.standard.set(array, forKey: readStoryIDsKey)
        if let data = try? JSONEncoder().encode(array) {
            saveBackup(data, for: readStoryIDsKey)
        }
        saveReadStories()
    }

    private func saveHiddenStories() {
        if let data = try? JSONEncoder().encode(hiddenStories) {
            UserDefaults.standard.set(data, forKey: hiddenStoriesKey)
            saveBackup(data, for: hiddenStoriesKey)
        }
    }

    private func saveFavoriteStories() {
        if let data = try? JSONEncoder().encode(favoriteStories) {
            UserDefaults.standard.set(data, forKey: favoriteStoriesKey)
            saveBackup(data, for: favoriteStoriesKey)
        }
    }

    private func saveReadStories() {
        if let data = try? JSONEncoder().encode(readStories) {
            UserDefaults.standard.set(data, forKey: readStoriesKey)
            saveBackup(data, for: readStoriesKey)
        }
    }

    var thresholdStoryID: Int? {
        let stories = visibleSections.flatMap(\.stories)
        guard !stories.isEmpty else { return nil }
        let thresholdIndex = max(
            0,
            stories.count - Self.historyPrefetchRemainingStoryCount - 1
        )
        return stories[thresholdIndex].id
    }

    /// 用于类目归纳的样本标题：已读 + 收藏，去重后截取上限。
    /// 样本不足（<30 篇）时调用方退化为内置默认类目。
    func inductionSampleTitles(max: Int = 500) -> [String] {
        let titles = (readStories.map(\.story.title) + favoriteStories.map(\.story.title))
            .filter { !$0.isEmpty }
        let unique = Array(Set(titles))
        return Array(unique.prefix(max))
    }

    private func visibleStoryIDs(in snapshot: HomeFeedSnapshot) -> Set<Int> {
        Set(snapshot.sections.flatMap(\.stories).compactMap { story in
            guard !isStoryHidden(story.id),
                  !isStoryFavorited(story.id),
                  !isStoryRead(story.id)
            else {
                return nil
            }
            return story.id
        })
    }

    private var snapshot: HomeFeedSnapshot {
        HomeFeedSnapshot(
            sections: sections,
            topStories: topStories,
            historyCursor: historyCursor
        )
    }

    private func apply(_ value: RepositoryValue<HomeFeedSnapshot>) {
        topStories = value.value.topStories
        sections = value.value.sections
        historyCursor = value.value.historyCursor
        loadedStoryIDs = Set(sections.flatMap(\.stories).map(\.id))
        phase = sections.isEmpty && topStories.isEmpty ? .empty : .loaded(value.source)
        historyLoadState = .idle
    }
}
