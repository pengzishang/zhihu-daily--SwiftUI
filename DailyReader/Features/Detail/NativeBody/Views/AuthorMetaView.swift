import SwiftUI

/// 作者块：头像 + 作者 + 简介 + 「查看原回答」入口。
struct AuthorMetaView: View {
    let meta: AuthorMetaBlock
    let fontSize: Double
    var onLinkTap: (URL) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                if let avatar = meta.avatarURL {
                    RemoteImageView(urlString: avatar, contentMode: .fill)
                        .frame(width: 42, height: 42)
                        .clipShape(Circle())
                        .overlay(Circle().strokeBorder(DS.hairline, lineWidth: 0.7))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(meta.author)
                        .font(DS.songBold(15))
                        .foregroundStyle(DS.ink)
                    if let bio = meta.bio {
                        Text(bio)
                            .font(.system(size: 12))
                            .foregroundStyle(DS.inkSecondary)
                    }
                }
                Spacer(minLength: 8)
            }

            if let origin = meta.originURL, let url = URL(string: origin) {
                Button {
                    onLinkTap(url)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.right.square")
                        Text("查看原回答")
                    }
                    .font(.system(size: 13))
                    .foregroundStyle(DS.indigo)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 12)
        .overlay(alignment: .top) { Divider().background(DS.hairline) }
        .overlay(alignment: .bottom) { Divider().background(DS.hairline) }
    }
}
