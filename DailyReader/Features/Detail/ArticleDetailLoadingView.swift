import SwiftUI

/// 文章详情载入动画（方案 A 印章呼吸 + 方案 C 墨线书写 混合）。
///
/// 设计前提：详情页在 `.loading` 阶段，封面 / 标题 / 题下信息 / 文武线已由列表数据
/// 即时渲染，本视图只接管「正文区」的载入态——朱砂方章轻轻呼吸定调品牌，
/// 其下墨线如落笔自左向右写出、朱砂墨点随锋行进。全部动效尊重系统「减弱动态效果」。
///
/// 设计预览见 `outputs/detail-loading-animations.html`（第 4 张卡：A+C 混合）。
struct ArticleDetailLoadingView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var breathe = false
    @State private var ripple1 = false
    @State private var ripple2 = false
    @State private var inkDraw = false
    @State private var dotTravel = false

    private let breatheDuration: Double = 2.4
    private let inkDuration: Double = 1.8

    var body: some View {
        VStack(spacing: 26) {
            seal
            inkLine
        }
        .padding(.vertical, 40)
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("articleDetailLoading")
        .accessibilityLabel("正在加载文章内容")
        .onAppear(perform: startAnimations)
    }

    // MARK: 方案 A — 朱砂方章呼吸 + 墨晕扩散

    private var seal: some View {
        ZStack {
            sealRing(active: ripple1, delay: 0)
            sealRing(active: ripple2, delay: breatheDuration / 2)
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(DS.cinnabar)
                .frame(width: 60, height: 60)
                .overlay(
                    Text("知")
                        .font(DS.songBlack(30))
                        .foregroundStyle(.white)
                )
                .scaleEffect(breathe ? 1 : 0.9)
                .opacity(breathe ? 1 : 0.7)
                .animation(
                    reduceMotion
                        ? nil
                        : .easeInOut(duration: breatheDuration / 2).repeatForever(autoreverses: true),
                    value: breathe
                )
        }
        .frame(width: 72, height: 72)
    }

    private func sealRing(active: Bool, delay: Double) -> some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .stroke(DS.cinnabar, lineWidth: 1.5)
            .frame(width: 72, height: 72)
            .scaleEffect(active ? 1.7 : 0.55)
            .opacity(active ? 0 : 0.45)
            .animation(
                reduceMotion
                    ? nil
                    : .easeOut(duration: breatheDuration).repeatForever(autoreverses: false).delay(delay),
                value: active
            )
    }

    // MARK: 方案 C — 墨线落笔写出 + 朱砂墨点随锋

    private var inkLine: some View {
        VStack(spacing: 14) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(DS.ink.opacity(0.82))
                        .frame(height: 1.6)
                        .scaleEffect(x: inkDraw ? 1 : 0, anchor: .leading)
                        .animation(
                            reduceMotion
                                ? nil
                                : .easeInOut(duration: inkDuration).repeatForever(autoreverses: false),
                            value: inkDraw
                        )

                    Capsule()
                        .fill(DS.inkSecondary.opacity(0.4))
                        .frame(height: 0.7)
                        .offset(y: 3)
                        .scaleEffect(x: inkDraw ? 1 : 0, anchor: .leading)
                        .animation(
                            reduceMotion
                                ? nil
                                : .easeInOut(duration: inkDuration)
                                    .repeatForever(autoreverses: false)
                                    .delay(0.12),
                            value: inkDraw
                        )

                    Circle()
                        .fill(DS.cinnabar)
                        .frame(width: 13, height: 13)
                        .offset(x: dotTravel ? geo.size.width - CGFloat(6.5) : -CGFloat(6.5))
                        .opacity(dotTravel ? 1 : 0)
                        .animation(
                            reduceMotion
                                ? nil
                                : .easeInOut(duration: inkDuration).repeatForever(autoreverses: false),
                            value: dotTravel
                        )
                }
            }
            .frame(height: 14)
            .frame(maxWidth: 260)

            VStack(spacing: 3) {
                Text("落墨成文")
                    .font(DS.songBold(14))
                    .foregroundStyle(DS.ink)
                Text("正在加载正文…")
                    .font(.footnote)
                    .foregroundStyle(DS.inkSecondary)
            }
        }
    }

    private func startAnimations() {
        if reduceMotion {
            // 静态兜底：印章满态、墨线整条画出，无位移墨点。
            breathe = true
            inkDraw = true
            return
        }
        breathe = true
        ripple1 = true
        DispatchQueue.main.asyncAfter(deadline: .now() + breatheDuration / 2) {
            ripple2 = true
        }
        inkDraw = true
        dotTravel = true
    }
}
