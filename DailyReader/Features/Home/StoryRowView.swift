import SwiftUI

struct StoryRowView: View {
    let story: StorySummary
    let isRead: Bool
    let displaysMetrics: Bool
    let density: HomeInformationDensity
    let immersiveImageURL: String?

    @StateObject private var metricsViewModel: StoryMetricsViewModel
    @StateObject private var categoryViewModel: StoryCategoryViewModel
    @AppStorage("DailyReader.listFontSize") private var listFontSize: Double = 16.0

    @MainActor
    init(
        story: StorySummary,
        isRead: Bool,
        displaysMetrics: Bool = false,
        density: HomeInformationDensity = .medium,
        immersiveImageURL: String? = nil
    ) {
        self.story = story
        self.isRead = isRead
        self.displaysMetrics = displaysMetrics
        self.density = density
        self.immersiveImageURL = immersiveImageURL
        _metricsViewModel = StateObject(
            wrappedValue: AppEnvironment.makeStoryMetricsViewModel(storyID: story.id)
        )
        _categoryViewModel = StateObject(
            wrappedValue: AppEnvironment.makeStoryCategoryViewModel(storyID: story.id)
        )
    }

    var body: some View {
        Group {
            switch density {
            case .low:
                immersiveLayout
            case .medium:
                standardLayout
            case .high:
                compactLayout
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier("storyRow-\(story.id)")
        .accessibilityValue(density.title)
        .task(id: metricsTaskID) {
            guard metricsTaskID != nil else { return }
            await metricsViewModel.load()
        }
        .task {
            await categoryViewModel.load()
        }
    }

    private var immersiveLayout: some View {
        VStack(alignment: .leading, spacing: 0) {
            storyMedia(cornerRadius: 10)
                .aspectRatio(16 / 9, contentMode: .fit)

            title(lineLimit: 3, size: listFontSize + 4, lineSpacing: 4)
                .padding(.top, 14)

            if let categoryName = categoryViewModel.categoryName {
                StoryCategoryTag(categoryName: categoryName, isOther: categoryViewModel.isOtherCategory)
                    .padding(.top, 6)
            }

            hint(lineLimit: 2, size: max(12, listFontSize - 3), lineSpacing: 3)
                .padding(.top, hasHint ? 8 : 0)

            Spacer(minLength: 0)

            metricLine
                .padding(.top, hasMetrics ? 10 : 0)
        }
        .padding(.vertical, 10)
    }

    private var standardLayout: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 0) {
                if let categoryName = categoryViewModel.categoryName {
                    StoryCategoryTag(categoryName: categoryName, isOther: categoryViewModel.isOtherCategory)
                        .padding(.bottom, 6)
                }

                title(lineLimit: 3, size: listFontSize + 1, lineSpacing: 3)

                hint(lineLimit: 1, size: max(11, listFontSize - 4), lineSpacing: 0)
                    .padding(.top, hasHint ? 8 : 0)

                metricLine
                    .padding(.top, hasMetrics ? 7 : 0)
            }

            Spacer(minLength: 8)

            storyMedia(cornerRadius: 9)
                .frame(width: 72, height: 72)
        }
        .padding(.vertical, 8)
    }

    private var compactLayout: some View {
        title(lineLimit: 2, size: listFontSize, lineSpacing: 2)
            .padding(.vertical, 3)
            .frame(minHeight: 44, alignment: .leading)
    }

    private func title(lineLimit: Int, size: Double, lineSpacing: CGFloat) -> some View {
        Text(story.title)
            .font(DS.songBold(size))
            .foregroundStyle(isRead ? DS.inkSecondary : DS.ink)
            .lineLimit(lineLimit)
            .lineSpacing(lineSpacing)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func hint(lineLimit: Int, size: Double, lineSpacing: CGFloat) -> some View {
        if let hint = story.hint, !hint.isEmpty {
            Text(hint)
                .font(.system(size: size))
                .foregroundStyle(DS.inkSecondary)
                .lineLimit(lineLimit)
                .lineSpacing(lineSpacing)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var metricLine: some View {
        if hasMetrics, let metrics = metricsViewModel.metrics {
            StoryMetricLine(metrics: metrics)
                .transition(.opacity)
        }
    }

    private func storyMedia(cornerRadius: CGFloat) -> some View {
        GeometryReader { proxy in
            ZStack {
                HomeEditorialPlaceholder()

                if density == .low,
                   immersiveImageURL?.isEmpty == false || story.images.first?.isEmpty == false {
                    PlaceholderImageView(
                        urlString: immersiveImageURL ?? story.images.first,
                        thumbnailURLString: story.images.first,
                        targetSize: proxy.size
                    )
                } else if let image = story.images.first, !image.isEmpty {
                    RemoteImageView(
                        urlString: image,
                        targetSize: proxy.size,
                        placeholder: AnyView(Color.clear),
                        failure: AnyView(Color.clear)
                    )
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(DS.hairline, lineWidth: 0.7)
        )
        .opacity(isRead ? 0.62 : 1)
        .accessibilityHidden(true)
    }

    private var hasHint: Bool {
        story.hint?.isEmpty == false
    }

    private var hasMetrics: Bool {
        displaysMetrics && density.displaysMetrics && metricsViewModel.metrics?.hasVisibleValues == true
    }

    private var metricsTaskID: String? {
        guard displaysMetrics && density.displaysMetrics else { return nil }
        return "\(story.id)-\(density.rawValue)"
    }

    private var accessibilityLabel: String {
        let status = isRead ? "已读" : "未读"
        let hint = hasHint && density != .high ? "，\(story.hint ?? "")" : ""
        return "\(status)，\(story.title)\(hint)"
    }
}

struct HomeEditorialPlaceholder: View {
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                DS.paperElevated

                Canvas { context, size in
                    let lineColor = DS.hairline
                    let horizontalStep: CGFloat = max(16, size.height / 6)
                    var y: CGFloat = horizontalStep
                    while y < size.height {
                        context.fill(
                            Path(CGRect(x: 0, y: y, width: size.width, height: 0.7)),
                            with: .color(lineColor)
                        )
                        y += horizontalStep
                    }

                    context.fill(
                        Path(CGRect(x: size.width * 0.5, y: 0, width: 0.7, height: size.height)),
                        with: .color(lineColor)
                    )
                }

                VStack(spacing: max(5, proxy.size.height * 0.05)) {
                    RuleLine()
                        .frame(maxWidth: proxy.size.width * 0.56)
                    Text("拾遗")
                        .font(DS.songBlack(min(42, max(24, proxy.size.height * 0.22))))
                        .tracking(8)
                        .foregroundStyle(DS.inkSecondary.opacity(0.24))
                        .padding(.leading, 8)
                    RuleLine()
                        .frame(maxWidth: proxy.size.width * 0.56)
                }
            }
        }
        .accessibilityLabel("文章无配图，显示抽象报刊版纹")
    }
}
