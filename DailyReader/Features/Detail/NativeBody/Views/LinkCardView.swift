import SwiftUI

/// 知乎富链接卡：标题 + 描述 + 可选缩略图，整体可点。
struct LinkCardView: View {
    let card: LinkCardBlock
    let fontSize: Double
    var onLinkTap: (URL) -> Void = { _ in }

    var body: some View {
        Button {
            if let url = URL(string: card.url) { onLinkTap(url) }
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(card.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(DS.ink)
                        .lineLimit(2)
                    if let description = card.description {
                        Text(description)
                            .font(.system(size: 13))
                            .foregroundStyle(DS.inkSecondary)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 8)

                if let imageURL = card.imageURL {
                    RemoteImageView(urlString: imageURL, contentMode: .fill)
                        .frame(width: 56, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
            .padding(12)
            .background(DS.paperElevated)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(DS.hairline, lineWidth: 0.7)
            )
        }
        .buttonStyle(.plain)
    }
}
