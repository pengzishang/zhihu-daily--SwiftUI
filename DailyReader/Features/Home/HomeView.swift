import SwiftUI

struct HomeView: View {
    @ObservedObject var viewModel: HomeViewModel
    @EnvironmentObject private var aiCoordinator: AIChatCoordinator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(HomeInformationDensity.storageKey) private var storedDensity = HomeInformationDensity.medium.rawValue

    @State private var presentsLayoutPicker = false
    @State private var visibleStoryID: Int?

    private var density: HomeInformationDensity {
        HomeInformationDensity(storedValue: storedDensity)
    }

    var body: some View {
        GeometryReader { proxy in
            content(availableWidth: proxy.size.width)
        }
        .background(DS.paper.ignoresSafeArea())
        .navigationTitle("日报阅读器")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    aiCoordinator.openIndependentChat()
                } label: {
                    Text("知")
                        .font(DS.songBlack(16))
                        .foregroundStyle(DS.indigo)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("AI 搜索")
                .accessibilityHint("打开独立 AI 对话")
                .accessibilityIdentifier("home.aiButton")

                Button {
                    presentsLayoutPicker = true
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(DS.indigo)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("首页工具")
                .accessibilityHint("切换首页信息密度")
                .accessibilityIdentifier("home.moreButton")
            }
        }
        .sheet(isPresented: $presentsLayoutPicker) {
            HomeDensitySelectionView(selection: densityBinding)
                .padding(.horizontal, 18)
                .padding(.top, 10)
                .padding(.bottom, 22)
                .background(DS.paperElevated.ignoresSafeArea())
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
                .presentationBackground(DS.paperElevated)
                .accessibilityIdentifier("homeDensity.sheet")
        }
        .task {
            normalizeStoredDensity()
            await viewModel.load()
        }
    }

    @ViewBuilder
    private func content(availableWidth: CGFloat) -> some View {
        switch viewModel.phase {
        case .idle, .loading:
            LoadingView(message: "正在加载日报")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            ErrorStateView(message: message) {
                Task { await viewModel.refresh() }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .empty:
            ContentUnavailableView("今日暂无内容", systemImage: "newspaper", description: Text("稍后再试，或者下拉刷新。"))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loaded:
            storyFeed(availableWidth: availableWidth)
        }
    }

    private func storyFeed(availableWidth: CGFloat) -> some View {
        let usesImmersiveColumns = density == .low && availableWidth >= 700

        return ScrollView {
            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                if let bannerMessage = viewModel.bannerMessage {
                    OfflineBanner(message: bannerMessage)
                        .padding(.horizontal, horizontalPadding(for: availableWidth))
                        .padding(.vertical, 8)
                }

                if let openingStory = viewModel.topStories.first {
                    TodayStoryOpeningView(
                        story: openingStory,
                        density: density,
                        homeViewModel: viewModel
                    )
                    .padding(.horizontal, horizontalPadding(for: availableWidth))
                    .padding(.top, density == .high ? 4 : 8)
                    .padding(.bottom, density == .high ? 10 : 16)
                }

                ForEach(viewModel.visibleSections) { section in
                    Section {
                        if usesImmersiveColumns {
                            LazyVGrid(
                                columns: [
                                    GridItem(.flexible(), spacing: 20, alignment: .top),
                                    GridItem(.flexible(), spacing: 20, alignment: .top)
                                ],
                                alignment: .leading,
                                spacing: 0
                            ) {
                                storyItems(in: section)
                            }
                            .padding(.horizontal, horizontalPadding(for: availableWidth))
                        } else {
                            LazyVStack(spacing: 0) {
                                storyItems(in: section)
                            }
                            .padding(.horizontal, horizontalPadding(for: availableWidth))
                        }
                    } header: {
                        DatelineHeader(
                            date: section.date,
                            storyCount: section.stories.count,
                            isCompact: density == .high
                        )
                        .padding(.horizontal, horizontalPadding(for: availableWidth))
                        .background(DS.paper)
                    }
                }

                HistoryPaginationFooter(state: viewModel.historyLoadState) {
                    Task { await viewModel.loadMore() }
                }
                .padding(.horizontal, horizontalPadding(for: availableWidth))
            }
            .scrollTargetLayout()
        }
        .scrollPosition(id: $visibleStoryID)
        .scrollIndicators(.hidden)
        .background(DS.paper)
        .refreshable {
            await viewModel.refresh()
        }
        .accessibilityIdentifier("home.storyFeed")
    }

    @ViewBuilder
    private func storyItems(in section: DailySection) -> some View {
        ForEach(section.stories) { story in
            SwipeToHideContainer {
                viewModel.hideStory(story, date: section.date)
            } content: {
                NavigationLink {
                    ArticleDetailView(story: story, homeViewModel: viewModel, source: .daily, date: section.date)
                } label: {
                    StoryRowView(
                        story: story,
                        isRead: viewModel.isStoryRead(story.id),
                        displaysMetrics: density.displaysMetrics,
                        density: density,
                        immersiveImageURL: viewModel.immersiveImageURLs[story.id]
                    )
                }
                .buttonStyle(.plain)
            }
            .id(story.id)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(DS.hairline)
                    .frame(height: 0.7)
            }
            .task(id: density == .low ? story.id : nil) {
                guard density == .low else { return }
                await viewModel.loadImmersiveImage(for: story)
            }
            .onAppear {
                if story.id == viewModel.thresholdStoryID {
                    Task { await viewModel.loadMore() }
                }
            }
        }
    }

    private var densityBinding: Binding<HomeInformationDensity> {
        Binding(
            get: { density },
            set: { newValue in
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.20)) {
                    storedDensity = newValue.rawValue
                }
            }
        )
    }

    private func normalizeStoredDensity() {
        let normalized = HomeInformationDensity(storedValue: storedDensity).rawValue
        if storedDensity != normalized {
            storedDensity = normalized
        }
    }

    private func horizontalPadding(for width: CGFloat) -> CGFloat {
        width >= 700 ? 28 : 20
    }
}

private struct SwipeToHideContainer<Content: View>: View {
    let hide: () -> Void
    let content: Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var offset: CGFloat = 0
    @State private var dragging: Bool = false

    init(hide: @escaping () -> Void, @ViewBuilder content: () -> Content) {
        self.hide = hide
        self.content = content()
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            Button(role: .destructive, action: performHide) {
                Label("不感兴趣", systemImage: "eye.slash")
                    .labelStyle(.iconOnly)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 92)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("不感兴趣")

            content
                .background(DS.paper)
                .offset(x: offset)
                .contentShape(Rectangle())
                .allowsHitTesting(!dragging)
        }
        .clipped()
        .contentShape(Rectangle())
        .highPriorityGesture(
            DragGesture(minimumDistance: 18)
                .onChanged { value in
                    guard abs(value.translation.width) > abs(value.translation.height) else { return }
                    dragging = true
                    offset = min(0, max(-132, value.translation.width))
                }
                .onEnded { value in
                    guard abs(value.translation.width) > abs(value.translation.height) else { return }
                    dragging = false
                    if value.translation.width < -118 {
                        performHide()
                    } else {
                        setOffset(value.translation.width < -48 ? -92 : 0)
                    }
                }
        )
    }

    private func performHide() {
        setOffset(-160)
        if reduceMotion {
            hide()
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
                hide()
            }
        }
    }

    private func setOffset(_ value: CGFloat) {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
            offset = value
        }
    }
}

private struct HistoryPaginationFooter: View {
    let state: HistoryLoadState
    let loadMore: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            switch state {
            case .idle:
                Color.clear
                    .frame(height: 1)
            case .loading:
                HStack(spacing: 10) {
                    ProgressView()
                        .tint(DS.inkSecondary)
                    Text("正在加载更早日报")
                        .font(.system(size: 13))
                        .foregroundStyle(DS.inkSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            case .failed(let message):
                VStack(spacing: 10) {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(DS.inkSecondary)
                    Button("重试加载历史", action: loadMore)
                        .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 12)
        .accessibilityIdentifier("historyPaginationFooter")
    }
}
