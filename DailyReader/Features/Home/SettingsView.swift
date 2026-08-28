import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject var viewModel: HomeViewModel
    @EnvironmentObject private var aiCoordinator: AIChatCoordinator
    @AppStorage("DailyReader.fontSize") private var fontSize: Double = 16.0
    @AppStorage("DailyReader.listFontSize") private var listFontSize: Double = 16.0
    @AppStorage(HomeInformationDensity.storageKey) private var storedHomeDensity = HomeInformationDensity.medium.rawValue
    @AppStorage("DailyReader.useNativeBody") private var useNativeBody: Bool = false

    // 阅读状态备份 / 恢复相关状态
    @State private var exportedFileURL: URL?
    @State private var showShareSheet = false
    @State private var showImporter = false
    @State private var resultMessage: String?
    @State private var showResultAlert = false

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

                Button {
                    performExport()
                } label: {
                    Label("导出阅读状态", systemImage: "square.and.arrow.up")
                        .foregroundStyle(DS.ink)
                }
                .listRowBackground(DS.paperElevated)
                .accessibilityIdentifier("settings.exportState")

                Button {
                    showImporter = true
                } label: {
                    Label("导入阅读状态", systemImage: "square.and.arrow.down")
                        .foregroundStyle(DS.ink)
                }
                .listRowBackground(DS.paperElevated)
                .accessibilityIdentifier("settings.importState")
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
        .sheet(isPresented: $showShareSheet, onDismiss: {
            // 分享面板关闭后给个轻提示，引导用户完成保存
            showResult("已生成阅读状态备份，请在分享面板选择「存储到文件」或 AirDrop 完成保存。")
        }) {
            if let url = exportedFileURL {
                ShareSheet(items: [url as Any])
            }
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else {
                    Task { @MainActor in
                        showResult("未选择有效的备份文件。")
                    }
                    return
                }
                // 访问安全范围资源，读取完毕后停止访问
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                do {
                    let data = try Data(contentsOf: url)
                    Task { @MainActor in
                        handleImport(data: data)
                    }
                } catch {
                    Task { @MainActor in
                        showResult("读取文件失败：\(error.localizedDescription)")
                    }
                }
            case .failure(let error):
                Task { @MainActor in
                    showResult("选择文件失败：\(error.localizedDescription)")
                }
            }
        }
        .alert("操作结果", isPresented: $showResultAlert) {
            Button("好", role: .cancel) { }
        } message: {
            Text(resultMessage ?? "")
        }
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

    // MARK: - 阅读状态备份 / 恢复

    /// 导出阅读状态：组装 JSON 并写入临时文件，随后弹出分享面板。
    @MainActor private func performExport() {
        do {
            let data = try viewModel.exportState()
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd-HHmm"
            formatter.locale = Locale(identifier: "en_US_POSIX")
            let fileName = "DailyReader-State-Backup-\(formatter.string(from: Date())).json"
            let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
            try data.write(to: fileURL, options: .atomic)
            exportedFileURL = fileURL
            showShareSheet = true
        } catch {
            showResult("导出失败：\(error.localizedDescription)")
        }
    }

    /// 解析并导入备份数据，合并进当前阅读状态。
    @MainActor private func handleImport(data: Data) {
        do {
            try viewModel.importState(data)
            let readCount = viewModel.readStoryIDs.count
            let favoriteCount = viewModel.favoriteStories.count
            let hiddenCount = viewModel.hiddenStories.count
            showResult("已恢复 \(readCount) 条已读 / \(favoriteCount) 条收藏 / \(hiddenCount) 条冷宫。")
        } catch {
            showResult("导入失败：\(error.localizedDescription)")
        }
    }

    /// 弹出统一的结果提示。
    private func showResult(_ message: String) {
        resultMessage = message
        showResultAlert = true
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
