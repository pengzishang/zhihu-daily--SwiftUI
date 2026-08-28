import SwiftUI

/// 引用块：左侧髮丝线 + 淡墨文字，内部递归渲染内容块。
struct BlockquoteView: View {
    let blocks: [ArticleBlock]
    let fontSize: Double
    var onImageTap: (String) -> Void = { _ in }
    var onLinkTap: (URL) -> Void = { _ in }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Rectangle()
                .fill(DS.hairline)
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(blocks) { block in
                    BlockRenderer(
                        block: block,
                        fontSize: fontSize * 0.95,
                        onImageTap: onImageTap,
                        onLinkTap: onLinkTap
                    )
                    .foregroundStyle(DS.inkSecondary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}
