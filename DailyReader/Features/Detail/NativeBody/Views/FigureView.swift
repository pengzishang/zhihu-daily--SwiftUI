import SwiftUI

/// 图 + 题注，复用现有 Kingfisher 封装 `RemoteImageView`。
struct FigureView: View {
    let figure: FigureBlock
    let fontSize: Double
    var onImageTap: (String) -> Void = { _ in }
    var onAISearch: (String) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            RemoteImageView(urlString: figure.image.url, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .contentShape(Rectangle())
                .onTapGesture { onImageTap(figure.image.url) }

            if let caption = figure.caption {
                NativeSelectableAttributedText(
                    text: captionAttributedText(caption),
                    baseFont: .systemFont(ofSize: fontSize * 0.8),
                    textColor: DS.inkSecondaryUI,
                    lineSpacing: fontSize * 0.3,
                    emphasis: nil,
                    onLinkTap: { _ in },
                    onAISearch: onAISearch
                )
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func captionAttributedText(_ caption: String) -> AttributedString {
        var attributed = AttributedString(caption)
        attributed.font = .system(size: fontSize * 0.8)
        attributed.foregroundColor = DS.inkSecondary
        return attributed
    }
}
