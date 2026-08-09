import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject var viewModel: HomeViewModel
    @AppStorage("DailyReader.fontSize") private var fontSize: Double = 16.0
    @AppStorage("DailyReader.listFontSize") private var listFontSize: Double = 16.0

    // 阅读状态备份 / 恢复相关状态
    @State private var exportedFileURL: URL?
    @State private var showShareSheet = false
    @State private var showImporter = false
    @State private var resultMessage: String?
    @State private var showResultAlert = false

    var body: some View {
        List {
            Section(header: Text("阅读设置")) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("文章字体大小")
                        Spacer()
                        Text(fontSizeLabel)
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $fontSize, in: 14...22, step: 2) { Text("文章字体大小") }
                        minimumValueLabel: { Text("A").font(.system(size: 14)) }
                        maximumValueLabel: { Text("A").font(.system(size: 22)) }
                }
                .padding(.vertical, 4)

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("列表字体大小")
                        Spacer()
                        Text(listFontSizeLabel)
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $listFontSize, in: 14...22, step: 2) { Text("列表字体大小") }
                        minimumValueLabel: { Text("A").font(.system(size: 14)) }
                        maximumValueLabel: { Text("A").font(.system(size: 22)) }
                }
                .padding(.vertical, 4)
            }

            Section(header: Text("阅读管理")) {
                NavigationLink(destination: ColdPalaceView(viewModel: viewModel)) {
                    Label("冷宫", systemImage: "snowflake")
                }

                Button {
                    performExport()
                } label: {
                    Label("导出阅读状态", systemImage: "square.and.arrow.up")
                }

                Button {
                    showImporter = true
                } label: {
                    Label("导入阅读状态", systemImage: "square.and.arrow.down")
                }
            }

            Section(header: Text("关于")) {
                HStack {
                    Text("版本")
                    Spacer()
                    Text("1.1")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("设置")
        .sheet(isPresented: $showShareSheet, onDismiss: {
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

    private var fontSizeLabel: String { label(for: fontSize) }
    private var listFontSizeLabel: String { label(for: listFontSize) }

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
