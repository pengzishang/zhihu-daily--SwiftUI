import SwiftUI

// MARK: - Zhihu Hot List Views & ViewModels (v1.2)

enum HotListPhase {
    case loading
    case loaded([HotItem])
    case empty
    case failed(String)
}

struct HotListView: View {
    @StateObject private var viewModel: HotListViewModel
    @ObservedObject var homeViewModel: HomeViewModel
    @Environment(\.openURL) private var openURL
    private let makeAnswersViewModel: (Int) -> AnswersViewModel

    init(
        viewModel: @autoclosure @escaping () -> HotListViewModel,
        homeViewModel: HomeViewModel,
        makeAnswersViewModel: @escaping (Int) -> AnswersViewModel
    ) {
        self.homeViewModel = homeViewModel
        self.makeAnswersViewModel = makeAnswersViewModel
        _viewModel = StateObject(wrappedValue: viewModel())
    }

    var body: some View {
        Group {
            switch viewModel.phase {
            case .loading:
                LoadingView(message: "正在加载热榜")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(DS.paper.ignoresSafeArea())
            case .empty:
                VStack {
                    Text("今日暂无热榜内容")
                        .font(DS.songBold(17))
                        .foregroundStyle(DS.inkSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(DS.paper.ignoresSafeArea())
                .refreshable {
                    await viewModel.refresh()
                }
            case .failed(let errorMsg):
                VStack(spacing: 16) {
                    Text(errorMsg)
                        .foregroundStyle(DS.inkSecondary)
                        .multilineTextAlignment(.center)
                    Button("重试") {
                        Task {
                            await viewModel.refresh()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(DS.paper.ignoresSafeArea())
            case .loaded(let items):
                let visibleItems = items.filter { !homeViewModel.isStoryHidden($0.target.id) }
                List(visibleItems) { item in
                    Group {
                        if let url = item.target.url {
                            Button {
                                openURL(url)
                            } label: {
                                hotItemRow(item)
                            }
                        } else {
                            NavigationLink {
                                QuestionAnswersView(
                                    questionID: item.target.id,
                                    questionTitle: item.target.title,
                                    questionExcerpt: item.target.excerpt,
                                    questionThumbnail: item.target.thumbnail,
                                    answerCount: item.target.answerCount,
                                    viewModel: makeAnswersViewModel(item.target.id),
                                    homeViewModel: homeViewModel
                                )
                            } label: {
                                hotItemRow(item)
                            }
                        }
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparatorTint(DS.hairline)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            let summary = StorySummary(
                                id: item.target.id,
                                title: item.target.title,
                                images: item.target.thumbnail.map { [$0] } ?? [],
                                hint: "知乎热榜",
                                url: item.target.url?.absoluteString ?? "https://www.zhihu.com/question/\(item.target.id)"
                            )
                            homeViewModel.hideStory(summary, date: "今日热榜")
                        } label: {
                            Label("不感兴趣", systemImage: "eye.slash")
                        }
                        .tint(DS.cinnabar)
                    }
                }
                .listStyle(.plain)
                .paperListBackground()
                .accessibilityIdentifier("hotList.container")
                .refreshable {
                    await viewModel.refresh()
                }
            }
        }
        .navigationTitle("热榜")
        .task {
            await viewModel.load()
        }
    }

    private func hotItemRow(_ item: HotItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            // 排名用宋体特粗数字，老报纸榜单的味道；前三名以朱砂、赭石、藤黄点睛
            Text("\(item.id)")
                .font(DS.songBlack(item.id <= 3 ? 23 : 19))
                .foregroundStyle(rankColor(for: item.id))
                .frame(width: 34, alignment: .center)
                .accessibilityIdentifier(item.id <= 3 ? "hotList.rank.top3" : "hotList.rank.normal")

            VStack(alignment: .leading, spacing: 5) {
                Text(item.target.title)
                    .font(DS.songBold(16))
                    .foregroundStyle(homeViewModel.isStoryRead(item.target.id) ? DS.inkSecondary : DS.ink)
                    .lineLimit(2)
                    .lineSpacing(2)

                Text(item.detailText)
                    .font(.system(size: 12))
                    .foregroundStyle(DS.inkSecondary)
            }
            Spacer(minLength: 8)

            PlaceholderImageView(
                urlString: item.target.thumbnail,
                targetSize: CGSize(width: 72, height: 72)
            )
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(DS.hairline, lineWidth: 0.7)
                )
                .accessibilityIdentifier("hotList.thumbnail")
        }
        .padding(.vertical, 6)
    }

    private func rankColor(for rank: Int) -> Color {
        switch rank {
        case 1: return DS.cinnabar
        case 2: return DS.ochre
        case 3: return DS.gold
        default: return DS.inkSecondary
        }
    }
}

// MARK: - Question Answers View

enum AnswersPhase {
    case loading
    case loaded([AnswerItem])
    case empty
    case restricted
    case failed(String)
}

struct QuestionAnswersView: View {
    let questionID: Int
    let questionTitle: String
    let questionExcerpt: String?
    let questionThumbnail: String?
    let answerCount: Int?
    @StateObject private var viewModel: AnswersViewModel
    @ObservedObject var homeViewModel: HomeViewModel

    init(
        questionID: Int,
        questionTitle: String,
        questionExcerpt: String? = nil,
        questionThumbnail: String? = nil,
        answerCount: Int? = nil,
        viewModel: @autoclosure @escaping () -> AnswersViewModel,
        homeViewModel: HomeViewModel
    ) {
        self.questionID = questionID
        self.questionTitle = questionTitle
        self.questionExcerpt = questionExcerpt
        self.questionThumbnail = questionThumbnail
        self.answerCount = answerCount
        self.homeViewModel = homeViewModel
        _viewModel = StateObject(wrappedValue: viewModel())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            questionHeader

            Group {
                switch viewModel.phase {
                case .loading:
                    LoadingView(message: "正在加载回答")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .empty:
                    VStack {
                        Text("暂无精选回答")
                            .font(DS.songBold(17))
                            .foregroundStyle(DS.inkSecondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .restricted:
                    restrictedAnswersView
                case .failed(let msg):
                    VStack {
                        Text(msg)
                            .foregroundStyle(DS.inkSecondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .loaded(let answers):
                    List(answers.indices, id: \.self) { index in
                        let answer = answers[index]
                        NavigationLink {
                            AnswerDetailView(
                                answer: answer,
                                questionID: questionID,
                                questionTitle: questionTitle,
                                homeViewModel: homeViewModel
                            )
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Image(systemName: "person.crop.circle")
                                        .resizable()
                                        .frame(width: 24, height: 24)
                                        .foregroundStyle(DS.inkSecondary)
                                    Text(answer.author.name)
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundStyle(DS.ink)
                                    Spacer()
                                    Text("\(answer.voteupCount) 赞同")
                                        .font(.system(size: 12))
                                        .foregroundStyle(DS.indigo)
                                }

                                Text(answer.excerpt)
                                    .font(.system(size: 14))
                                    .foregroundStyle(DS.inkSecondary)
                                    .lineLimit(3)
                                    .lineSpacing(2)
                            }
                            .padding(.vertical, 6)
                        }
                        .listRowBackground(Color.clear)
                        .listRowSeparatorTint(DS.hairline)
                        .accessibilityIdentifier("answers.row_\(index)")
                    }
                    .listStyle(.plain)
                    .accessibilityIdentifier("answers.list")
                }
            }
        }
        .background(DS.paper.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.load()
        }
    }

    private var questionHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(questionTitle)
                .font(DS.songBold(20))
                .foregroundStyle(DS.ink)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("answers.questionTitle")

            if let questionExcerpt, !questionExcerpt.isEmpty {
                HStack(alignment: .top, spacing: 12) {
                    Text(questionExcerpt)
                        .font(.system(size: 14))
                        .foregroundStyle(DS.inkSecondary)
                        .lineLimit(4)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("answers.questionExcerpt")

                    if let questionThumbnail, !questionThumbnail.isEmpty {
                        PlaceholderImageView(
                            urlString: questionThumbnail,
                            targetSize: CGSize(width: 96, height: 64)
                        )
                            .frame(width: 96, height: 64)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(DS.hairline, lineWidth: 0.7)
                            )
                            .accessibilityIdentifier("answers.questionThumbnail")
                    }
                }
            }

            // 问题与回答之间压一道文武线，像报纸的题区分隔
            RuleLine()
        }
        .padding(.horizontal)
        .padding(.top)
        .padding(.bottom, 4)
        .background(DS.paper)
    }

    private var restrictedAnswersView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("知乎限制未登录访问回答列表")
                    .font(DS.songBold(17))
                    .foregroundStyle(DS.ink)
                    .accessibilityIdentifier("answers.restrictedMessage")

                if let questionExcerpt, !questionExcerpt.isEmpty {
                    Text(questionExcerpt)
                        .font(.system(size: 15))
                        .foregroundStyle(DS.inkSecondary)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("answers.restrictedExcerpt")
                }

                if let answerCount, answerCount > 0 {
                    Text("知乎显示共有 \(answerCount) 个回答，可在知乎查看完整回答列表。")
                        .font(.system(size: 14))
                        .foregroundStyle(DS.inkSecondary)
                } else {
                    Text("可在知乎查看完整回答列表。")
                        .font(.system(size: 14))
                        .foregroundStyle(DS.inkSecondary)
                }

                Link(destination: URL(string: "https://www.zhihu.com/question/\(questionID)")!) {
                    Label("在知乎查看回答", systemImage: "safari")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("answers.openInZhihu")
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DS.paper.ignoresSafeArea())
    }
}

// MARK: - Answer Detail View

struct AnswerDetailView: View {
    let answer: AnswerItem
    let questionID: Int
    let questionTitle: String
    @ObservedObject var homeViewModel: HomeViewModel
    @State private var htmlContentHeight: CGFloat = 520
    @State private var htmlReloadToken = 0
    @State private var htmlErrorMessage: String?
    @State private var isWebViewLoading = true
    @AppStorage("DailyReader.fontSize") private var fontSize: Double = 16.0

    init(answer: AnswerItem, questionID: Int, questionTitle: String, homeViewModel: HomeViewModel) {
        self.answer = answer
        self.questionID = questionID
        self.questionTitle = questionTitle
        self.homeViewModel = homeViewModel
    }

    var body: some View {
        Group {
            if answer.content.isEmpty {
                VStack {
                    Text("回答正文加载失败或暂无内容")
                        .font(DS.songBold(17))
                        .foregroundStyle(DS.inkSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                if let htmlErrorMessage {
                    ErrorStateView(message: htmlErrorMessage) {
                        self.htmlErrorMessage = nil
                        htmlReloadToken += 1
                        isWebViewLoading = true
                    }
                    .frame(maxWidth: .infinity, minHeight: 240)
                } else if FeatureFlag.useNativeBody {
                    NativeBodyRenderer.bodyView(
                        html: answer.content,
                        cssLinks: [],
                        fontSize: fontSize,
                        onImageTap: { _ in },
                        onLinkTap: { url in UIApplication.shared.open(url) },
                        fallback: {
                            AnyView(
                                HTMLWebView(
                                    htmlBody: answer.content,
                                    cssLinks: [],
                                    reloadToken: htmlReloadToken,
                                    fontSize: fontSize,
                                    contentHeight: $htmlContentHeight,
                                    isLoading: $isWebViewLoading,
                                    onImageTap: { _ in },
                                    enablesAISearch: false,
                                    onAISelection: { _ in },
                                    onArticleTextPrepared: { _ in },
                                    onError: { message in
                                        htmlErrorMessage = message
                                        isWebViewLoading = false
                                    }
                                )
                            )
                        }
                    )
                } else {
                    ZStack {
                        HTMLWebView(
                            htmlBody: answer.content,
                            cssLinks: [],
                            reloadToken: htmlReloadToken,
                            fontSize: fontSize,
                            contentHeight: $htmlContentHeight,
                            isLoading: $isWebViewLoading,
                            onImageTap: { _ in },
                            enablesAISearch: false,
                            onAISelection: { _ in },
                            onArticleTextPrepared: { _ in },
                            onError: { message in
                                htmlErrorMessage = message
                                isWebViewLoading = false
                            }
                        )
                        .frame(minHeight: htmlContentHeight)
                        .accessibilityIdentifier("answerDetail.webView")
                        .opacity(isWebViewLoading ? 0 : 1)

                        if isWebViewLoading {
                            VStack(spacing: 12) {
                                ProgressView()
                                    .tint(DS.inkSecondary)
                                Text("正在加载正文...")
                                    .font(.footnote)
                                    .foregroundStyle(DS.inkSecondary)
                            }
                        }
                    }
                }
            }
        }
        .background(DS.paper.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .markReadAfterViewing(
            storyID: questionID,
            isRead: homeViewModel.isStoryRead(questionID)
        ) {
            let summary = StorySummary(
                id: questionID,
                title: questionTitle,
                images: [],
                hint: "知乎热榜",
                url: "https://www.zhihu.com/question/\(questionID)"
            )
            homeViewModel.markStoryRead(summary, date: "今日热榜")
        }
    }
}
