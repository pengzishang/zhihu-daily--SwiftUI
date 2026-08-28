import SwiftUI
import UIKit

enum ArticleDetailSource: CaseIterable {
    case daily
    case coldPalace
    case favorites
    case read

    var enablesAutomaticReadQualification: Bool {
        self == .daily
    }
}

struct ArticleDetailView: View {
    @ObservedObject var homeViewModel: HomeViewModel
    @EnvironmentObject private var aiCoordinator: AIChatCoordinator
    let source: ArticleDetailSource
    let date: String

    @StateObject private var viewModel: ArticleDetailViewModel
    @State private var isShowingShareSheet = false
    @State private var htmlContentHeight: CGFloat = 520
    @State private var htmlReloadToken = 0
    @State private var htmlErrorMessage: String?
    @State private var isWebViewLoading = true

    @AppStorage("DailyReader.fontSize") private var fontSize: Double = 16.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedImage: IdentifiableImageURL?
    @State private var readingProgress: Double = 0
    @State private var scrollContentHeight: CGFloat = 0
    @State private var scrollOffset: CGFloat = 0
    @State private var preparedArticleText = ""
    @State private var maxReadingProgress: Double = 0
    @State private var sessionRecorder = ReadingSessionRecorder()
    @Environment(\.scenePhase) private var scenePhase

    private static let topAnchorID = "article-detail-top"
    static let readingControlVisibilityThreshold: CGFloat = 200

    @MainActor
    init(story: StorySummary, homeViewModel: HomeViewModel, source: ArticleDetailSource, date: String) {
        self.homeViewModel = homeViewModel
        self.source = source
        self.date = date
        _viewModel = StateObject(wrappedValue: AppEnvironment.makeDetailViewModel(story: story))
    }

    var body: some View {
        GeometryReader { _ in
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Color.clear
                            .frame(height: 1)
                            .id(Self.topAnchorID)

                if let bannerMessage = viewModel.bannerMessage {
                    OfflineBanner(message: bannerMessage)
                }

                // 1. 封面图（先用列表摘要图即时显示，详情加载后换高清图）
                if let imageURL = detailImageURL {
                    PlaceholderImageView(
                        urlString: imageURL,
                        thumbnailURLString: viewModel.story.images.first,
                        targetSize: CGSize(width: 430, height: 220)
                    )
                    .frame(height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(DS.hairline, lineWidth: 0.7)
                    )
                }

                VStack(alignment: .leading, spacing: 10) {
                    // 2. 标题（宋体特粗，像文章的「题花」）
                    Text(detailTitle)
                        .font(DS.songBlack(26))
                        .foregroundStyle(DS.ink)
                        .lineSpacing(5)
                        .lineLimit(nil)

                    // 2.5 题下信息行 + 文武线，正文自此展开
                    if metaLine != nil || ChineseDate.formatted(date) != nil {
                        HStack(spacing: 8) {
                            if let metaLine {
                                Text(metaLine)
                            }
                            if metaLine != nil, ChineseDate.formatted(date) != nil {
                                Text("·")
                            }
                            if let formattedDate = ChineseDate.formatted(date) {
                                Text(formattedDate)
                            }
                        }
                        .font(.system(size: 13))
                        .foregroundStyle(DS.inkSecondary)
                    }

                    ArticleMetricByline(
                        daily: viewModel.storyMetrics,
                        originalAnswer: viewModel.originalAnswerMetrics
                    )
                    .transition(.opacity)

                    RuleLine()
                        .padding(.bottom, 2)

                    // 3. Body loading/loaded/failed phases
                    switch viewModel.phase {
                    case .idle, .loading:
                        HStack {
                            Spacer()
                            VStack(spacing: 12) {
                                ProgressView()
                                    .tint(DS.inkSecondary)
                                Text("正在加载内容...")
                                    .font(.footnote)
                                    .foregroundStyle(DS.inkSecondary)
                            }
                            .padding(.vertical, 40)
                            Spacer()
                        }
                    case .failed(let message):
                        ErrorStateView(message: message) {
                            Task { await viewModel.reload() }
                        }
                        .frame(maxWidth: .infinity, minHeight: 240)
                    case .loaded(let detail, _):
                        if let body = detail.body, !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            if let htmlErrorMessage {
                                ErrorStateView(message: htmlErrorMessage) {
                                    self.htmlErrorMessage = nil
                                    htmlReloadToken += 1
                                    isWebViewLoading = true
                                }
                                .frame(maxWidth: .infinity, minHeight: 240)
                        } else if FeatureFlag.useNativeBody {
                            NativeBodyRenderer.bodyView(
                                html: body,
                                cssLinks: detail.css,
                                fontSize: fontSize,
                                onImageTap: { url in
                                    selectedImage = IdentifiableImageURL(url: url)
                                },
                                onLinkTap: { url in
                                    UIApplication.shared.open(url)
                                },
                                fallback: {
                                    AnyView(
                                        HTMLWebView(
                                            htmlBody: body,
                                            cssLinks: detail.css,
                                            reloadToken: htmlReloadToken,
                                            fontSize: fontSize,
                                            contentHeight: $htmlContentHeight,
                                            isLoading: $isWebViewLoading,
                                            onImageTap: { url in
                                                selectedImage = IdentifiableImageURL(url: url)
                                            },
                                            enablesAISearch: true,
                                            onAISelection: { selection in
                                                openAIChat(selectedText: selection)
                                            },
                                            onArticleTextPrepared: { text in
                                                preparedArticleText = text
                                            },
                                            onError: { message in
                                                htmlErrorMessage = message
                                                isWebViewLoading = false
                                            }
                                        )
                                        .frame(minHeight: htmlContentHeight)
                                        .accessibilityIdentifier("articleHTMLContent")
                                        .opacity(isWebViewLoading ? 0 : 1)
                                    )
                                }
                            )
                            .onAppear {
                                if preparedArticleText.isEmpty {
                                    preparedArticleText = NativeBodyRenderer.parsedBlocks(html: body)
                                        .map { NativeBodyRenderer.plainText(from: $0) } ?? ""
                                }
                            }
                        } else {
                            ZStack {
                                HTMLWebView(
                                        htmlBody: body,
                                        cssLinks: detail.css,
                                        reloadToken: htmlReloadToken,
                                        fontSize: fontSize,
                                        contentHeight: $htmlContentHeight,
                                        isLoading: $isWebViewLoading,
                                        onImageTap: { url in
                                            selectedImage = IdentifiableImageURL(url: url)
                                        },
                                        enablesAISearch: true,
                                        onAISelection: { selection in
                                            openAIChat(selectedText: selection)
                                        },
                                        onArticleTextPrepared: { text in
                                            preparedArticleText = text
                                        },
                                        onError: { message in
                                            htmlErrorMessage = message
                                            isWebViewLoading = false
                                        }
                                    )
                                    .frame(minHeight: htmlContentHeight)
                                    .accessibilityIdentifier("articleHTMLContent")
                                    .opacity(isWebViewLoading ? 0 : 1)

                                    if isImagePreviewUITestScenario {
                                        Button {
                                            selectedImage = IdentifiableImageURL(url: imagePreviewFixtureURL)
                                        } label: {
                                            Color.clear
                                                .frame(width: 56, height: 56)
                                                .contentShape(Rectangle())
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityIdentifier("articleImagePreviewTestTrigger")
                                    }

                                    if isWebViewLoading {
                                        HStack {
                                            Spacer()
                                            VStack(spacing: 12) {
                                                ProgressView()
                                                    .tint(DS.inkSecondary)
                                                Text("正在加载正文...")
                                                    .font(.footnote)
                                                    .foregroundStyle(DS.inkSecondary)
                                            }
                                            .padding(.vertical, 40)
                                            Spacer()
                                        }
                                    }
                                }
                            }
                        } else {
                            ContentUnavailableView("文章内容暂不可用", systemImage: "doc.text.magnifyingglass")
                                .frame(maxWidth: .infinity, minHeight: 240)
                        }
                    }
                }
                    }
                    .padding()
                    .background {
                        ArticleScrollObserver { offset, contentHeight, viewportHeight in
                            updateScrollMetrics(
                                offset: offset,
                                contentHeight: contentHeight,
                                viewportHeight: viewportHeight
                            )
                        }
                        .frame(width: 0, height: 0)
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    if makeArticleAIContext() != nil {
                        VStack(spacing: 10) {
                            ArticleAIButton {
                                openAIChat(selectedText: nil)
                            }
                            if shouldShowReadingControl {
                                ReadingProgressButton(progress: readingProgress) {
                                    let scroll = {
                                        proxy.scrollTo(Self.topAnchorID, anchor: .top)
                                    }
                                    if reduceMotion {
                                        scroll()
                                    } else {
                                        withAnimation(.easeOut(duration: 0.28)) {
                                            scroll()
                                        }
                                    }
                                }
                                .transition(.opacity.combined(with: .scale(scale: 0.92)))
                            }
                        }
                        .padding(.trailing, 18)
                        .padding(.bottom, 18)
                        .zIndex(10)
                    }
                }
            }
        }
        .background(DS.paper.ignoresSafeArea())
        .navigationTitle(viewModel.shareTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(action: {
                        isShowingShareSheet = true
                    }) {
                        Label("分享", systemImage: "square.and.arrow.up")
                    }
                    .disabled(viewModel.shareURL == nil)

                    if homeViewModel.isStoryFavorited(viewModel.story.id) {
                        Button(action: {
                            homeViewModel.toggleFavorite(viewModel.story, date: date)
                        }) {
                            Label("取消收藏", systemImage: "star.fill")
                        }
                    } else {
                        Button(action: {
                            homeViewModel.toggleFavorite(viewModel.story, date: date)
                        }) {
                            Label("收藏", systemImage: "star")
                        }
                    }

                    Button(action: {
                        homeViewModel.toggleRead(viewModel.story, date: date)
                    }) {
                        Label("设为未读", systemImage: "envelope.badge")
                    }
                    .disabled(!homeViewModel.isStoryRead(viewModel.story.id))

                    if source == .coldPalace {
                        Button(action: {
                            homeViewModel.restoreStory(viewModel.story.id)
                        }) {
                            Label("恢复到日报", systemImage: "arrow.uturn.backward")
                        }
                    } else {
                        Button(action: {
                            homeViewModel.hideStory(viewModel.story, date: date)
                        }) {
                            Label("不感兴趣", systemImage: "eye.slash")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("操作")
            }
        }
        .sheet(isPresented: $isShowingShareSheet) {
            if let shareURL = viewModel.shareURL {
                ShareSheet(items: [viewModel.shareTitle, shareURL])
            }
        }
        .fullScreenCover(item: $selectedImage) { item in
            FullScreenImageViewer(urlString: item.url)
        }
        .task {
            await viewModel.load()
        }
        .onChange(of: viewModel.loadedDetailID) { _, _ in
            htmlContentHeight = 520
            htmlErrorMessage = nil
            isWebViewLoading = true
            Task { await viewModel.classifyCurrentArticle() }
        }
        .onAppear {
            sessionRecorder.resume()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                sessionRecorder.resume()
            } else {
                commitSession()
            }
        }
        .onDisappear {
            commitSession()
        }
        .markReadAfterViewing(
            storyID: viewModel.story.id,
            isRead: homeViewModel.isStoryRead(viewModel.story.id),
            isEnabled: source.enablesAutomaticReadQualification
        ) {
            homeViewModel.markStoryRead(viewModel.story, date: date)
        }
    }

    private var detailImageURL: String? {
        if case .loaded(let detail, _) = viewModel.phase {
            return detail.image ?? detail.images.first ?? viewModel.story.images.first
        }
        return viewModel.story.images.first
    }

    private var detailTitle: String {
        if case .loaded(let detail, _) = viewModel.phase, !detail.title.isEmpty {
            return detail.title
        }
        return viewModel.story.title
    }

    /// 题下信息行：优先展示来源提示（如「知乎热榜」「顶部故事」）
    private var metaLine: String? {
        if let hint = viewModel.story.hint, !hint.isEmpty {
            return hint
        }
        return nil
    }

    private func makeArticleAIContext(focusedSelection: String? = nil) -> AIArticleContext? {
        guard case .loaded(let detail, _) = viewModel.phase,
              let html = detail.body,
              !html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        if preparedArticleText.isEmpty {
            return AIArticleContextBuilder.make(
                id: detail.id,
                title: detailTitle,
                html: html,
                sourceURL: detail.shareURL ?? detail.url,
                focusedSelection: focusedSelection
            )
        }
        return AIArticleContextBuilder.make(
            id: detail.id,
            title: detailTitle,
            plainText: preparedArticleText,
            sourceURL: detail.shareURL ?? detail.url,
            focusedSelection: focusedSelection
        )
    }

    private func openAIChat(selectedText: String?) {
        guard let context = makeArticleAIContext(focusedSelection: selectedText) else { return }
        aiCoordinator.openArticleChat(context: context, selectedText: selectedText)
    }

    private var isImagePreviewUITestScenario: Bool {
        ProcessInfo.processInfo.environment["MOCK_SCENARIO"] == "detail_body_image"
    }

    private var imagePreviewFixtureURL: String {
        "data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///ywAAAAAAQABAAACAUwAOw=="
    }

    private var shouldShowReadingControl: Bool {
        guard case .loaded(let detail, _) = viewModel.phase,
              detail.body?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            return false
        }
        return Self.shouldShowReadingControl(offset: scrollOffset)
    }

    static func shouldShowReadingControl(offset: CGFloat) -> Bool {
        offset > readingControlVisibilityThreshold
    }

    private func updateScrollMetrics(
        offset: CGFloat,
        contentHeight: CGFloat,
        viewportHeight: CGFloat
    ) {
        scrollOffset = offset
        scrollContentHeight = contentHeight
        readingProgress = Self.progress(
            offset: offset,
            contentHeight: contentHeight,
            viewportHeight: viewportHeight
        )
        maxReadingProgress = max(maxReadingProgress, readingProgress)
    }

    /// 提交一次阅读会话信号并重置累计器，避免重复计数。
    private func commitSession() {
        sessionRecorder.pause()
        let dwell = sessionRecorder.elapsedActiveTime
        guard dwell > 0 || maxReadingProgress > 0 else {
            sessionRecorder.reset()
            return
        }
        let isFavorited = homeViewModel.isStoryFavorited(viewModel.story.id)
        let isHidden = homeViewModel.isStoryHidden(viewModel.story.id)
        viewModel.recordReadingSession(
            maxScrollPercent: maxReadingProgress,
            dwellSeconds: dwell,
            isFavorited: isFavorited,
            isHidden: isHidden
        )
        sessionRecorder.reset()
        maxReadingProgress = 0
    }

    static func progress(offset: CGFloat, contentHeight: CGFloat, viewportHeight: CGFloat) -> Double {
        let scrollableDistance = max(contentHeight - viewportHeight, 1)
        return min(max(Double(offset / scrollableDistance), 0), 1)
    }
}

@MainActor
final class ReadQualificationTimer: ObservableObject {
    static let requiredViewingDuration: TimeInterval = 10

    private let requiredDuration: TimeInterval
    private let now: () -> ContinuousClock.Instant
    private var accumulatedDuration: Duration = .zero
    private var activeSince: ContinuousClock.Instant?
    private var storyID: Int?
    private(set) var hasQualified = false

    init(
        requiredDuration: TimeInterval = requiredViewingDuration,
        now: @escaping () -> ContinuousClock.Instant = { ContinuousClock.now }
    ) {
        self.requiredDuration = requiredDuration
        self.now = now
    }

    func resume() {
        guard !hasQualified, activeSince == nil else { return }
        activeSince = now()
    }

    func prepare(for storyID: Int) {
        guard self.storyID != storyID else { return }
        self.storyID = storyID
        accumulatedDuration = .zero
        activeSince = nil
        hasQualified = false
    }

    @discardableResult
    func pause() -> Bool {
        guard !hasQualified, let activeSince else { return false }
        accumulatedDuration += activeSince.duration(to: now())
        self.activeSince = nil
        return qualifyIfNeeded()
    }

    @discardableResult
    func qualifyIfNeeded() -> Bool {
        guard !hasQualified else { return false }
        let activeDuration = activeSince.map { $0.duration(to: now()) } ?? .zero
        guard accumulatedDuration + activeDuration >= .seconds(requiredDuration) else { return false }
        hasQualified = true
        activeSince = nil
        return true
    }
}

struct MarkReadAfterViewingModifier: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var timer = ReadQualificationTimer()

    let storyID: Int
    let isRead: Bool
    let isEnabled: Bool
    let markRead: () -> Void

    func body(content: Content) -> some View {
        content
            .task(
                id: ReadQualificationTaskID(
                    storyID: storyID,
                    isRead: isRead,
                    isEnabled: isEnabled,
                    scenePhase: scenePhase
                )
            ) {
                timer.prepare(for: storyID)
                guard isEnabled, !isRead, scenePhase == .active else {
                    pauseAndMarkIfQualified()
                    return
                }

                timer.resume()
                do {
                    while !Task.isCancelled {
                        if timer.qualifyIfNeeded() {
                            markRead()
                            return
                        }
                        try await Task.sleep(for: .milliseconds(100))
                    }
                } catch {
                    pauseAndMarkIfQualified()
                }
            }
            .onDisappear {
                pauseAndMarkIfQualified()
            }
    }

    private func pauseAndMarkIfQualified() {
        if timer.pause() {
            markRead()
        }
    }
}

private struct ReadQualificationTaskID: Equatable {
    let storyID: Int
    let isRead: Bool
    let isEnabled: Bool
    let scenePhase: ScenePhase
}

extension View {
    func markReadAfterViewing(
        storyID: Int,
        isRead: Bool,
        isEnabled: Bool = true,
        markRead: @escaping () -> Void
    ) -> some View {
        modifier(
            MarkReadAfterViewingModifier(
                storyID: storyID,
                isRead: isRead,
                isEnabled: isEnabled,
                markRead: markRead
            )
        )
    }
}

private struct ArticleScrollObserver: UIViewRepresentable {
    let onChange: (_ offset: CGFloat, _ contentHeight: CGFloat, _ viewportHeight: CGFloat) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onChange: onChange)
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        context.coordinator.attach(toAncestorOf: view)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onChange = onChange
        context.coordinator.attach(toAncestorOf: uiView)
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.stopObserving()
    }

    final class Coordinator: NSObject {
        var onChange: (_ offset: CGFloat, _ contentHeight: CGFloat, _ viewportHeight: CGFloat) -> Void
        private weak var scrollView: UIScrollView?
        private var observations: [NSKeyValueObservation] = []
        private var attachmentAttempts = 0

        init(onChange: @escaping (_ offset: CGFloat, _ contentHeight: CGFloat, _ viewportHeight: CGFloat) -> Void) {
            self.onChange = onChange
        }

        func attach(toAncestorOf view: UIView) {
            guard scrollView == nil else {
                publishMetrics()
                return
            }

            if let scrollView = sequence(first: view.superview, next: { $0?.superview })
                .compactMap({ $0 as? UIScrollView })
                .first {
                observe(scrollView)
                return
            }

            guard attachmentAttempts < 8 else { return }
            attachmentAttempts += 1
            DispatchQueue.main.async { [weak self, weak view] in
                guard let self, let view else { return }
                self.attach(toAncestorOf: view)
            }
        }

        func stopObserving() {
            observations.removeAll()
            scrollView = nil
        }

        private func observe(_ scrollView: UIScrollView) {
            self.scrollView = scrollView
            observations = [
                scrollView.observe(\.contentOffset, options: [.initial, .new]) { [weak self] _, _ in
                    self?.publishMetrics()
                },
                scrollView.observe(\.contentSize, options: [.initial, .new]) { [weak self] _, _ in
                    self?.publishMetrics()
                },
                scrollView.observe(\.bounds, options: [.initial, .new]) { [weak self] _, _ in
                    self?.publishMetrics()
                }
            ]
        }

        private func publishMetrics() {
            guard let scrollView else { return }
            let offset = max(0, scrollView.contentOffset.y + scrollView.adjustedContentInset.top)
            let contentHeight = scrollView.contentSize.height
            let viewportHeight = scrollView.bounds.height
            DispatchQueue.main.async { [weak self] in
                self?.onChange(offset, contentHeight, viewportHeight)
            }
        }
    }
}

private struct ArticleAIButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("知")
                .font(DS.songBlack(18))
                .foregroundStyle(DS.indigo)
                .frame(width: 50, height: 50)
                .background(Circle().fill(DS.paperElevated))
                .overlay(Circle().stroke(DS.indigo, lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("articleAIButton")
        .accessibilityLabel("就当前文章询问 AI")
        .accessibilityHint("打开带有当前文章上下文的对话")
    }
}

private struct ReadingProgressButton: View {
    let progress: Double
    let action: () -> Void

    private var percentage: Int {
        Int((progress * 100).rounded())
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(DS.paperElevated)
                Circle()
                    .stroke(DS.inkSecondary.opacity(0.38), lineWidth: 1)
                Circle()
                    .trim(from: 0, to: max(progress, 0.025))
                    .stroke(
                        DS.indigo,
                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))

                VStack(spacing: -1) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 11, weight: .semibold))
                    Text("\(percentage)%")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                }
                .foregroundStyle(DS.indigo)
            }
            .frame(width: 54, height: 54)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("articleReadingProgressButton")
        .accessibilityLabel("回到文章顶部")
        .accessibilityValue("已阅读百分之\(percentage)")
        .accessibilityHint("轻点返回文章开头")
    }
}

struct IdentifiableImageURL: Identifiable {
    var id: String { url }
    let url: String
}

struct ZoomableScrollView<Content: View>: UIViewRepresentable {
    private var content: Content
    private var onSingleTap: (() -> Void)?

    init(onSingleTap: (() -> Void)? = nil, @ViewBuilder content: () -> Content) {
        self.onSingleTap = onSingleTap
        self.content = content()
    }

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.delegate = context.coordinator
        scrollView.maximumZoomScale = 5.0
        scrollView.minimumZoomScale = 1.0
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .never

        // Add double tap gesture
        let doubleTapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleDoubleTap(_:)))
        doubleTapGesture.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTapGesture)

        let singleTapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleSingleTap(_:)))
        singleTapGesture.numberOfTapsRequired = 1
        singleTapGesture.require(toFail: doubleTapGesture)
        scrollView.addGestureRecognizer(singleTapGesture)

        let hostingController = UIHostingController(rootView: content)
        hostingController.view.backgroundColor = .clear
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(hostingController.view)

        NSLayoutConstraint.activate([
            hostingController.view.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            hostingController.view.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            hostingController.view.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            hostingController.view.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor)
        ])

        context.coordinator.hostingController = hostingController
        return scrollView
    }

    func updateUIView(_ uiView: UIScrollView, context: Context) {
        context.coordinator.onSingleTap = onSingleTap
        context.coordinator.hostingController?.rootView = content
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onSingleTap: onSingleTap)
    }

    class Coordinator: NSObject, UIScrollViewDelegate {
        var hostingController: UIHostingController<Content>?
        var onSingleTap: (() -> Void)?

        init(onSingleTap: (() -> Void)? = nil) {
            self.onSingleTap = onSingleTap
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            return hostingController?.view
        }

        @objc func handleSingleTap(_ gesture: UITapGestureRecognizer) {
            onSingleTap?()
        }

        @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            guard let scrollView = gesture.view as? UIScrollView else { return }
            if scrollView.zoomScale > scrollView.minimumZoomScale {
                scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
            } else {
                let point = gesture.location(in: hostingController?.view)
                let zoomRect = calculateZoomRect(for: scrollView, at: point, with: 3.0)
                scrollView.zoom(to: zoomRect, animated: true)
            }
        }

        private func calculateZoomRect(for scrollView: UIScrollView, at point: CGPoint, with scale: CGFloat) -> CGRect {
            let size = CGSize(
                width: scrollView.frame.size.width / scale,
                height: scrollView.frame.size.height / scale
            )
            let origin = CGPoint(
                x: point.x - size.width / 2,
                y: point.y - size.height / 2
            )
            return CGRect(origin: origin, size: size)
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            // Center the image view as it zooms
            guard let subView = hostingController?.view else { return }
            let offsetX = max((scrollView.bounds.size.width - scrollView.contentSize.width) * 0.5, 0.0)
            let offsetY = max((scrollView.bounds.size.height - scrollView.contentSize.height) * 0.5, 0.0)
            subView.center = CGPoint(x: scrollView.contentSize.width * 0.5 + offsetX, y: scrollView.contentSize.height * 0.5 + offsetY)
        }
    }
}

struct FullScreenImageViewer: View {
    let urlString: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            ZoomableScrollView(onSingleTap: {
                dismiss()
            }) {
                RemoteImageView(
                    urlString: urlString,
                    contentMode: .fit,
                    placeholder: AnyView(
                        ProgressView()
                            .tint(.white)
                    ),
                    failure: AnyView(
                        VStack(spacing: 12) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.largeTitle)
                                .foregroundStyle(.secondary)
                            Text("图片加载失败")
                                .foregroundStyle(.secondary)
                        }
                    )
                )
            }
            .ignoresSafeArea()
            .accessibilityIdentifier("fullScreenImageViewer.background")

            Button(action: {
                dismiss()
            }) {
                Image(systemName: "xmark")
                    .font(.title3.bold())
                    .foregroundStyle(.white)
                    .padding(12)
                    .background(Color.black.opacity(0.6))
                    .clipShape(Circle())
            }
            .padding(.top, 16)
            .padding(.trailing, 16)
            .accessibilityIdentifier("fullScreenImageViewer.closeButton")
        }
    }
}
