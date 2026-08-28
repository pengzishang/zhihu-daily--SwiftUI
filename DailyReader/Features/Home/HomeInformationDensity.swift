import SwiftUI

enum HomeInformationDensity: String, CaseIterable, Identifiable {
    static let storageKey = "DailyReader.homeInformationDensity"

    case low
    case medium
    case high

    var id: String { rawValue }

    init(storedValue: String?) {
        self = storedValue.flatMap(Self.init(rawValue:)) ?? .medium
    }

    var title: String {
        switch self {
        case .low: "沉浸"
        case .medium: "标准"
        case .high: "速览"
        }
    }

    var densityLabel: String {
        switch self {
        case .low: "低密度"
        case .medium: "中密度"
        case .high: "高密度"
        }
    }

    var detail: String {
        switch self {
        case .low: "大图与完整预览"
        case .medium: "信息均衡"
        case .high: "更多标题"
        }
    }

    var accessibilityDescription: String {
        "\(title)，\(densityLabel)，\(detail)"
    }

    var displaysMetrics: Bool { self != .high }

    var openingHeight: CGFloat {
        switch self {
        case .low: 320
        case .medium: 270
        case .high: 196
        }
    }

    var openingCornerRadius: CGFloat {
        switch self {
        case .low: 14
        case .medium: 12
        case .high: 10
        }
    }

    var openingTitleLineLimit: Int {
        switch self {
        case .low, .medium: 3
        case .high: 2
        }
    }

    var openingContentPadding: CGFloat {
        switch self {
        case .low: 22
        case .medium: 20
        case .high: 16
        }
    }

    var systemImage: String {
        switch self {
        case .low: "rectangle.grid.1x2"
        case .medium: "rectangle.grid.2x2"
        case .high: "list.bullet"
        }
    }
}

struct HomeDensitySelectionView: View {
    @Binding var selection: HomeInformationDensity
    var showsTitle = true

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if showsTitle {
                VStack(alignment: .leading, spacing: 5) {
                    Text("首页布局")
                        .font(DS.songBlack(24))
                        .foregroundStyle(DS.ink)
                    Text("选择适合此刻的阅读节奏，内容与字号不会改变。")
                        .font(.footnote)
                        .foregroundStyle(DS.inkSecondary)
                }
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    ForEach(HomeInformationDensity.allCases) { density in
                        option(for: density)
                    }
                }

                VStack(spacing: 10) {
                    ForEach(HomeInformationDensity.allCases) { density in
                        option(for: density)
                    }
                }
            }

            Text("选择后立即预览并自动保存。使用大字号时优先保证可读性，因此实际单屏篇数可能减少。")
                .font(.caption)
                .foregroundStyle(DS.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityIdentifier("homeDensity.selection")
    }

    private func option(for density: HomeInformationDensity) -> some View {
        Button {
            selection = density
        } label: {
            VStack(alignment: .leading, spacing: 9) {
                HomeDensityPreview(density: density)
                    .frame(height: 62)

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(density.title)
                        .font(DS.songBold(16))
                    Spacer(minLength: 4)
                    if selection == density {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .accessibilityHidden(true)
                    }
                }

                Text("\(density.densityLabel) · \(density.detail)")
                    .font(.caption2)
                    .foregroundStyle(DS.inkSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(selection == density ? DS.indigo : DS.ink)
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 142, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(selection == density ? DS.indigo.opacity(0.10) : DS.paper)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(selection == density ? DS.indigo : DS.hairline, lineWidth: selection == density ? 1.4 : 0.7)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(density.accessibilityDescription)
        .accessibilityAddTraits(selection == density ? .isSelected : [])
        .accessibilityValue(selection == density ? "1" : "0")
        .accessibilityIdentifier("homeDensity.option.\(density.rawValue)")
    }
}

private struct HomeDensityPreview: View {
    let density: HomeInformationDensity

    var body: some View {
        ZStack {
            DS.paperElevated

            switch density {
            case .low:
                VStack(alignment: .leading, spacing: 5) {
                    DS.indigo.opacity(0.14)
                        .frame(height: 28)
                    previewLine(width: 0.82, color: DS.ink)
                    previewLine(width: 0.56, color: DS.inkSecondary)
                }
                .padding(6)
            case .medium:
                HStack(alignment: .top, spacing: 5) {
                    VStack(alignment: .leading, spacing: 5) {
                        previewLine(width: 0.9, color: DS.ink)
                        previewLine(width: 0.62, color: DS.ink)
                        previewLine(width: 0.72, color: DS.inkSecondary)
                    }
                    DS.indigo.opacity(0.14)
                        .frame(width: 24, height: 24)
                }
                .padding(7)
            case .high:
                VStack(spacing: 0) {
                    ForEach(0..<3, id: \.self) { index in
                        VStack(alignment: .leading, spacing: 4) {
                            previewLine(width: index == 1 ? 0.65 : 0.9, color: DS.ink)
                            previewLine(width: index == 2 ? 0.5 : 0.72, color: DS.inkSecondary)
                        }
                        .padding(.vertical, 4)
                        if index < 2 {
                            Rectangle().fill(DS.hairline).frame(height: 0.7)
                        }
                    }
                }
                .padding(.horizontal, 7)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .strokeBorder(DS.hairline, lineWidth: 0.7)
        )
        .accessibilityHidden(true)
    }

    private func previewLine(width: CGFloat, color: Color) -> some View {
        GeometryReader { proxy in
            Capsule()
                .fill(color.opacity(0.68))
                .frame(width: proxy.size.width * width, height: 3)
        }
        .frame(height: 3)
    }
}
