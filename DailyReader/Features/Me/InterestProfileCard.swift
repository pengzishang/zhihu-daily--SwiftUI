import SwiftUI

/// 兴趣画像卡：横向条形榜，按类目指数降序排列，展示百分比；
/// 「其他」置底并弱化；成员 < 3 篇标「样本不足」。
struct InterestProfileCard: View {
    @ObservedObject var viewModel: InterestProfileViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("兴趣画像")
                    .font(DS.songBold(17))
                    .foregroundStyle(DS.ink)
                Spacer(minLength: 8)
                Text("基于你的本地阅读行为")
                    .font(.system(size: 11))
                    .foregroundStyle(DS.inkSecondary)
            }

            if viewModel.isReady, !viewModel.isEmpty {
                bars
            } else {
                emptyState
            }
        }
        .padding(.vertical, 13)
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(DS.paperElevated)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(DS.hairline, lineWidth: 0.7)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("兴趣画像")
    }

    private var bars: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(viewModel.entries) { entry in
                row(entry)
            }
        }
    }

    private func row(_ entry: CategoryInterestIndex) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(entry.category.name)
                    .font(DS.songBold(13))
                    .foregroundStyle(entry.category.isOther ? DS.inkSecondary.opacity(0.7) : DS.ink)
                    .lineLimit(1)
                Spacer(minLength: 6)
                if entry.isLowSample {
                    Text("样本不足")
                        .font(.system(size: 10))
                        .foregroundStyle(DS.inkSecondary)
                }
                Text("\(Int((entry.score * 100).rounded()))%")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(entry.category.isOther ? DS.inkSecondary.opacity(0.7) : DS.ink)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(DS.hairline)
                    Capsule()
                        .fill(entry.category.isOther ? DS.inkSecondary.opacity(0.4) : DS.indigo)
                        .frame(width: max(proxy.size.width * CGFloat(entry.score), entry.category.isOther ? 0 : 4))
                }
                .frame(height: 6)
            }
            .frame(height: 6)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(entry.category.name)，兴趣指数百分之\(Int((entry.score * 100).rounded()))"
            + (entry.isLowSample ? "，样本不足" : "")
        )
    }

    private var emptyState: some View {
        Text("阅读一段时间后，这里会显示你的兴趣分布")
            .font(.system(size: 13))
            .foregroundStyle(DS.inkSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
    }
}
