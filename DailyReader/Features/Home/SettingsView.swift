import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: HomeViewModel
    @EnvironmentObject private var aiCoordinator: AIChatCoordinator
    @AppStorage("DailyReader.fontSize") private var fontSize: Double = 16.0
    @AppStorage("DailyReader.listFontSize") private var listFontSize: Double = 16.0
    @AppStorage(HomeInformationDensity.storageKey) private var storedHomeDensity = HomeInformationDensity.medium.rawValue
    @AppStorage("DailyReader.useNativeBody") private var useNativeBody: Bool = false

    var body: some View {
        List {
            Section(header: sectionHeader("阅读设置")) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("文章字体大小")
                            .foregroundStyle(DS.ink)
                        Spacer()
                        Text(fontSizeLabel)
                            .foregroundStyle(DS.inkSecondary)
                    }

                    Slider(value: $fontSize, in: 14...22, step: 2) {
                        Text("文章字体大小")
                    } minimumValueLabel: {
                        Text("A").font(.system(size: 14)).foregroundStyle(DS.inkSecondary)
                    } maximumValueLabel: {
                        Text("A").font(.system(size: 22)).foregroundStyle(DS.inkSecondary)
                    }
                }
                .padding(.vertical, 4)
                .listRowBackground(DS.paperElevated)

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("列表字体大小")
                            .foregroundStyle(DS.ink)
                        Spacer()
                        Text(listFontSizeLabel)
                            .foregroundStyle(DS.inkSecondary)
                    }

                    Slider(value: $listFontSize, in: 14...22, step: 2) {
                        Text("列表字体大小")
                    } minimumValueLabel: {
                        Text("A").font(.system(size: 14)).foregroundStyle(DS.inkSecondary)
                    } maximumValueLabel: {
                        Text("A").font(.system(size: 22)).foregroundStyle(DS.inkSecondary)
                    }
                }
                .padding(.vertical, 4)
                .listRowBackground(DS.paperElevated)

                NavigationLink {
                    HomeDensitySettingsView(selection: homeDensityBinding)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("首页信息密度")
                                .foregroundStyle(DS.ink)
                            Text("信息密度不会改变推荐内容和字体大小")
                                .font(.caption)
                                .foregroundStyle(DS.inkSecondary)
                        }
                        Spacer(minLength: 12)
                        Text(homeDensity.title)
                            .font(.subheadline)
                            .foregroundStyle(DS.indigo)
                    }
                }
                .listRowBackground(DS.paperElevated)
                .accessibilityIdentifier("settings.homeDensity")

                Toggle("原生正文渲染（实验）", isOn: $useNativeBody)
                    .foregroundStyle(DS.ink)
                    .listRowBackground(DS.paperElevated)
                    .accessibilityIdentifier("settings.useNativeBody")
            }
            .listRowSeparatorTint(DS.hairline)

            Section(header: sectionHeader("阅读管理")) {
                NavigationLink(destination: ColdPalaceView(viewModel: viewModel)) {
                    Label("冷宫", systemImage: "snowflake")
                        .foregroundStyle(DS.ink)
                }
                .listRowBackground(DS.paperElevated)
            }
            .listRowSeparatorTint(DS.hairline)

            Section(header: sectionHeader("AI 服务")) {
                NavigationLink {
                    AIConfigurationView(store: aiCoordinator.configurationStore)
                } label: {
                    HStack {
                        Label("AI 服务设置", systemImage: "text.bubble")
                            .foregroundStyle(DS.ink)
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(aiCoordinator.configurationStore.isReady ? "可用" : "未启用")
                            Text(aiCoordinator.configurationStore.enabledProviderSummary)
                        }
                        .font(.caption)
                        .foregroundStyle(aiCoordinator.configurationStore.isReady ? DS.indigo : DS.inkSecondary)
                    }
                }
                .listRowBackground(DS.paperElevated)
            }
            .listRowSeparatorTint(DS.hairline)

            Section(header: sectionHeader("关于")) {
                HStack {
                    Text("版本")
                        .foregroundStyle(DS.ink)
                    Spacer()
                    Text("1.1")
                        .foregroundStyle(DS.inkSecondary)
                }
                .listRowBackground(DS.paperElevated)
            }
            .listRowSeparatorTint(DS.hairline)
        }
        .scrollContentBackground(.hidden)
        .background(DS.paper.ignoresSafeArea())
        .navigationTitle("设置")
    }

    /// 分组节头：小号宋体，压住整组的「铅字」气质
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(DS.songBold(13))
            .foregroundStyle(DS.inkSecondary)
            .textCase(nil)
    }

    private var fontSizeLabel: String {
        label(for: fontSize)
    }

    private var listFontSizeLabel: String {
        label(for: listFontSize)
    }

    private var homeDensity: HomeInformationDensity {
        HomeInformationDensity(storedValue: storedHomeDensity)
    }

    private var homeDensityBinding: Binding<HomeInformationDensity> {
        Binding(
            get: { homeDensity },
            set: { storedHomeDensity = $0.rawValue }
        )
    }

    private func label(for size: Double) -> String {
        switch Int(size) {
        case 14: return "较小"
        case 16: return "标准"
        case 18: return "中"
        case 20: return "较大"
        case 22: return "特大"
        default: return "标准"
        }
    }
}

private struct HomeDensitySettingsView: View {
    @Binding var selection: HomeInformationDensity

    var body: some View {
        ScrollView {
            HomeDensitySelectionView(selection: $selection, showsTitle: false)
                .padding(20)
        }
        .background(DS.paper.ignoresSafeArea())
        .navigationTitle("首页信息密度")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("settings.homeDensity.screen")
    }
}
