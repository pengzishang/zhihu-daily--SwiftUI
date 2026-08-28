import SwiftUI

struct TodayStoryOpeningView: View {
    let story: TopStory
    let density: HomeInformationDensity
    @ObservedObject var homeViewModel: HomeViewModel

    @ScaledMetric(relativeTo: .title2) private var titleSize: CGFloat = 27
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var storySummary: StorySummary {
        Self.makeSummary(for: story)
    }

    static func makeSummary(for story: TopStory) -> StorySummary {
        StorySummary(
            id: story.id,
            title: story.title,
            images: story.image.map { [$0] } ?? [],
            hint: "顶部故事",
            url: story.url
        )
    }

    var body: some View {
        NavigationLink {
            ArticleDetailView(
                story: storySummary,
                homeViewModel: homeViewModel,
                source: .daily,
                date: ""
            )
        } label: {
            ZStack(alignment: .bottomLeading) {
                imageLayer
                readabilityGradient
                copyLayer
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: density.openingHeight)
            .clipShape(cardShape)
            .overlay {
                cardShape
                    .strokeBorder(DS.hairline, lineWidth: 0.7)
            }
            .contentShape(cardShape)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("今日故事：\(story.title)")
        .accessibilityHint("打开文章")
        .accessibilityIdentifier("home.todayStoryOpening")
    }

    private var cardShape: RoundedRectangle {
        RoundedRectangle(
            cornerRadius: density.openingCornerRadius,
            style: .continuous
        )
    }

    private var imageLayer: some View {
        PlaceholderImageView(
            urlString: story.image,
            targetSize: CGSize(width: 900, height: density.openingHeight * 2)
        )
        .frame(maxWidth: .infinity)
        .frame(height: density.openingHeight)
        .clipped()
        .accessibilityHidden(true)
    }

    private var readabilityGradient: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0.28),
                .init(color: Color.black.opacity(0.18), location: 0.52),
                .init(color: Color.black.opacity(0.88), location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var copyLayer: some View {
        VStack(alignment: .leading, spacing: density == .high ? 10 : 14) {
            Text("今日故事")
                .font(DS.songBold(12))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(DS.cinnabar)
                )

            Text(story.title)
                .font(DS.songBlack(scaledTitleSize))
                .foregroundStyle(.white)
                .lineSpacing(3)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : density.openingTitleLineLimit)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(density.openingContentPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var scaledTitleSize: CGFloat {
        let densityScale: CGFloat
        switch density {
        case .low:
            densityScale = 1.08
        case .medium:
            densityScale = 1
        case .high:
            densityScale = 0.84
        }
        return min(titleSize * densityScale, 44)
    }
}
