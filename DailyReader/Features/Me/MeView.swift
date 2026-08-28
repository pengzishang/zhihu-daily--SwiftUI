import SwiftUI

// MARK: - 统一「我的」页（v1.2）
// 「纸上书房」：以刊头、阅读档案和纸面内容流组织本地收藏与已读记录。

struct MeView: View {
    @ObservedObject var viewModel: HomeViewModel
    @ObservedObject var authenticationViewModel: AuthenticationViewModel
    @StateObject private var interestProfileViewModel: InterestProfileViewModel
    @State private var selectedSubTab = 0 // 0 收藏，1 已读
    @State private var searchText = ""
    @Namespace private var animation

    @MainActor
    init(
        viewModel: HomeViewModel,
        authenticationViewModel: AuthenticationViewModel,
        interestProfileViewModel: InterestProfileViewModel? = nil
    ) {
        self.viewModel = viewModel
        self.authenticationViewModel = authenticationViewModel
        let resolved = interestProfileViewModel ?? InterestProfileViewModel(
            classificationStore: ArticleClassificationStore(),
            interestStore: ReadingInterestStore(),
            taxonomyStore: CategoryTaxonomyStore()
        )
        _interestProfileViewModel = StateObject(wrappedValue: resolved)
    }

    // 正式界面暂时隐藏登录卡片；专用认证 UI 测试仍可通过 Mock 场景验证登录能力。
    private static var showsAuthenticationCard: Bool {
        ProcessInfo.processInfo.environment["MOCK_AUTH_SCENARIO"] != nil
    }

    private var trimmedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var visibleFavoriteCount: Int {
        viewModel.favoriteSections.reduce(0) { $0 + $1.stories.count }
    }

    private var visibleReadCount: Int {
        viewModel.visibleReadStories.count
    }

    private var filteredFavoriteSections: [DailySection] {
        let sections = viewModel.favoriteSections
        if trimmedSearchText.isEmpty {
            return sections
        }
        return sections.map { section in
            var sec = section
            sec.stories = section.stories.filter { story in
                story.title.localizedCaseInsensitiveContains(trimmedSearchText)
            }
            return sec
        }.filter { !$0.stories.isEmpty }
    }

    private var filteredReadStories: [ReadStory] {
        let stories = viewModel.visibleReadStories
        if trimmedSearchText.isEmpty {
            return stories
        }
        return stories.filter { readStory in
            readStory.story.title.localizedCaseInsensitiveContains(trimmedSearchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 14) {
                bookroomHeader
                // 暂时隐藏知乎账号登录入口，保留登录能力以便后续恢复。
                if Self.showsAuthenticationCard {
                    AccountCardView(viewModel: authenticationViewModel)
                }
                readingArchive
                InterestProfileCard(viewModel: interestProfileViewModel)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                    .frame(maxWidth: 720)
                segmentControl
                searchField
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
            .frame(maxWidth: 720)

            contentList
        }
        .frame(maxWidth: .infinity)
        .background(DS.paper.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .onDisappear {
            authenticationViewModel.cancel()
        }
        .onAppear {
            Task { await interestProfileViewModel.load() }
        }
    }

    // MARK: - 纸上书房首屏

    private var bookroomHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                SealChip(text: "今日")

                Text(ChineseDate.formatted(ChineseDate.todayString) ?? "今日")
                    .font(DS.songBold(16))
                    .foregroundStyle(DS.ink)

                if let weekday = ChineseDate.weekday(ChineseDate.todayString) {
                    Text(weekday)
                        .font(.system(size: 11))
                        .foregroundStyle(DS.inkSecondary)
                }

                Spacer(minLength: 8)

                Text("本地书房")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DS.inkSecondary)
            }

            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("我的书房")
                        .font(DS.songBlack(30))
                        .foregroundStyle(DS.ink)
                        .accessibilityIdentifier("me.header")

                    Text("收藏的好文章，都在这里")
                        .font(.system(size: 12))
                        .foregroundStyle(DS.inkSecondary)
                }

                Spacer(minLength: 12)

                NavigationLink {
                    SettingsView(viewModel: viewModel)
                        .toolbar(.visible, for: .navigationBar)
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(DS.ink)
                        .frame(width: 44, height: 44)
                        .background(
                            Circle()
                                .fill(DS.paperElevated)
                        )
                        .overlay(
                            Circle()
                                .strokeBorder(DS.hairline, lineWidth: 0.7)
                        )
                }
                .accessibilityLabel("设置")
                .accessibilityHint("打开阅读设置")
                .accessibilityIdentifier("me.settingsButton")
            }

            RuleLine()
        }
        .padding(.top, 8)
    }

    private var readingArchive: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 0) {
                archiveMetric(
                    value: visibleFavoriteCount,
                    title: "篇收藏",
                    description: "按日期归档"
                )

                Rectangle()
                    .fill(DS.hairline)
                    .frame(width: 0.7, height: 42)
                    .padding(.horizontal, 16)

                archiveMetric(
                    value: visibleReadCount,
                    title: "篇已读",
                    description: "最近阅读优先"
                )

                Spacer(minLength: 12)
            }

            VStack(alignment: .leading, spacing: 12) {
                archiveMetric(
                    value: visibleFavoriteCount,
                    title: "篇收藏",
                    description: "按日期归档"
                )

                RuleLine()

                archiveMetric(
                    value: visibleReadCount,
                    title: "篇已读",
                    description: "最近阅读优先"
                )
            }
        }
        .padding(.vertical, 13)
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(DS.paperElevated)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(DS.hairline, lineWidth: 0.7)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("阅读档案，收藏 \(visibleFavoriteCount) 篇，已读 \(visibleReadCount) 篇")
        .accessibilityIdentifier("me.readingArchive")
    }

    private func archiveMetric(value: Int, title: String, description: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Text("\(value)")
                .font(DS.songBlack(24))
                .monospacedDigit()
                .foregroundStyle(DS.ink)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(DS.songBold(13))
                    .foregroundStyle(DS.ink)
                Text(description)
                    .font(.system(size: 10))
                    .foregroundStyle(DS.inkSecondary)
            }
        }
    }

    private var segmentControl: some View {
        HStack(spacing: 0) {
            segmentButton(title: "收藏", count: visibleFavoriteCount, index: 0)
            segmentButton(title: "已读", count: visibleReadCount, index: 1)
        }
        .padding(4)
        .background(
            Capsule()
                .fill(DS.paperElevated)
        )
        .overlay(
            Capsule()
                .strokeBorder(DS.hairline, lineWidth: 0.7)
        )
        .accessibilityElement(children: .contain)
    }

    private func segmentButton(title: String, count: Int, index: Int) -> some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                selectedSubTab = index
            }
        } label: {
            Text("\(title)  \(count)")
                .font(DS.songBold(15))
                .foregroundStyle(selectedSubTab == index ? DS.paper : DS.inkSecondary)
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .accessibilityLabel("\(title)，\(count) 篇")
        .accessibilityAddTraits(selectedSubTab == index ? .isSelected : [])
        .accessibilityIdentifier(index == 0 ? "me.segment.favorites" : "me.segment.read")
        .background {
            if selectedSubTab == index {
                Capsule()
                    .fill(DS.ink)
                    .matchedGeometryEffect(id: "activeTab", in: animation)
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(DS.inkSecondary)

            TextField("搜索我的文章", text: $searchText)
                .textFieldStyle(.plain)
                .foregroundStyle(DS.ink)
                .accessibilityIdentifier("me.searchField")

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(DS.inkSecondary)
                        .frame(width: 32, height: 32)
                }
                .accessibilityLabel("清除搜索文字")
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 6)
        .frame(minHeight: 44)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(DS.paperElevated)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(DS.hairline, lineWidth: 0.7)
        )
    }

    // MARK: - 内容列表

    @ViewBuilder
    private var contentList: some View {
        if selectedSubTab == 0 {
            favoritesList
        } else {
            readList
        }
    }

    private var favoritesList: some View {
        List {
            if viewModel.favoriteStories.isEmpty {
                ContentUnavailableView(
                    "暂无收藏内容",
                    systemImage: "star",
                    description: Text("阅读日报时，可在详情页右上角的菜单中添加收藏。")
                )
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            } else if filteredFavoriteSections.isEmpty {
                SearchEmptyView()
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            } else {
                ForEach(filteredFavoriteSections) { section in
                    Section {
                        ForEach(section.stories) { story in
                            NavigationLink {
                                ArticleDetailView(
                                    story: story,
                                    homeViewModel: viewModel,
                                    source: .favorites,
                                    date: section.date
                                )
                            } label: {
                                StoryRowView(story: story, isRead: viewModel.isStoryRead(story.id))
                            }
                            .listRowBackground(Color.clear)
                            .listRowSeparatorTint(DS.hairline)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button {
                                    viewModel.toggleFavorite(story, date: section.date)
                                } label: {
                                    Label("取消收藏", systemImage: "star.slash")
                                }
                                .tint(DS.inkSecondary)
                            }
                        }
                    } header: {
                        DatelineHeader(date: section.date, storyCount: section.stories.count)
                            .textCase(nil)
                            .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 4, trailing: 20))
                    }
                }
            }
        }
        .listStyle(.plain)
        .paperListBackground()
        .accessibilityIdentifier("me.favorites.list")
    }

    private var readList: some View {
        List {
            if viewModel.visibleReadStories.isEmpty {
                ContentUnavailableView(
                    "暂无已读文章",
                    systemImage: "checkmark.circle",
                    description: Text("阅读日报文章后，已读记录将自动呈现在这里。")
                )
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            } else if filteredReadStories.isEmpty {
                SearchEmptyView()
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            } else {
                ForEach(filteredReadStories) { readStory in
                    let story = readStory.story
                    NavigationLink {
                        ArticleDetailView(
                            story: story,
                            homeViewModel: viewModel,
                            source: .read,
                            date: readStory.date
                        )
                    } label: {
                        StoryRowView(story: story, isRead: viewModel.isStoryRead(story.id))
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparatorTint(DS.hairline)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button {
                            viewModel.toggleRead(story, date: readStory.date)
                        } label: {
                            Label("设为未读", systemImage: "envelope.badge")
                        }
                        .tint(DS.ochre)
                    }
                }
            }
        }
        .listStyle(.plain)
        .paperListBackground()
        .accessibilityIdentifier("me.read.list")
    }
}

// MARK: - 搜索无结果占位

private struct SearchEmptyView: View {
    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "magnifyingglass")
                .font(.system(size: 40))
                .foregroundStyle(DS.inkSecondary)
            Text("未找到匹配的内容，换个词试试吧")
                .font(DS.songBold(16))
                .foregroundStyle(DS.inkSecondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, minHeight: 200)
    }
}
