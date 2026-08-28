import SwiftUI

/// 图 + 题注，复用现有 Kingfisher 封装 `RemoteImageView`。
struct FigureView: View {
    let figure: FigureBlock
    let fontSize: Double
    var onImageTap: (String) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            RemoteImageView(urlString: figure.image.url, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(DS.hairline, lineWidth: 0.7)
                )
                .contentShape(Rectangle())
                .onTapGesture { onImageTap(figure.image.url) }

            if let caption = figure.caption {
                Text(caption)
                    .font(.system(size: fontSize * 0.8))
                    .foregroundStyle(DS.inkSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
