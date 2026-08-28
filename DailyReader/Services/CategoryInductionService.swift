import Foundation

/// 首次类目归纳服务：用样本标题让 AI 提出 8–12 个不重叠大类。
///
/// 无 Key / 失败 / 样本不足时返回 nil，调用方退化为内置默认类目。
@MainActor
final class CategoryInductionService {
    private let chatService: AIChatServicing
    private let configurationStore: AIConfigurationStore

    init(
        chatService: AIChatServicing = OpenAICompatibleChatService(),
        configurationStore: AIConfigurationStore
    ) {
        self.chatService = chatService
        self.configurationStore = configurationStore
    }

    /// 用样本标题归纳 8–12 个不重叠类目名；无 Key / 失败返回 nil（触发默认类目）。
    func induce(titles: [String], range: ClosedRange<Int> = 8...12) async -> [String]? {
        guard configurationStore.isReady, !titles.isEmpty else { return nil }
        let providers = configurationStore.runtimeProviders()
        guard let provider = providers.first else { return nil }
        let sample = titles.prefix(500).joined(separator: "\n- ")
        let prompt = """
        你是内容分类专家。下面是一批文章标题，请归纳出 \(range.lowerBound)...\(range.upperBound) 个
        互不重叠、覆盖全面的中文大类（每个 2–6 字）。只返回一个 JSON 数组，如 ["科技","商业财经",...]。
        不要包含"其他"。标题样本：
        - \(sample)
        """
        do {
            var acc = ""
            for try await event in chatService.streamReply(
                configuration: provider.configuration,
                apiKey: provider.apiKey,
                messages: [AIChatMessage(role: .user, content: prompt)],
                articleContext: nil
            ) {
                if case .text(let delta) = event { acc += delta }
            }
            guard let data = acc.data(using: .utf8),
                  let arr = try? JSONSerialization.jsonObject(with: data) as? [String] else { return nil }
            let cleaned = arr.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            guard !cleaned.isEmpty else { return nil }
            let trimmed = Array(cleaned.prefix(range.upperBound))
            return trimmed.count >= range.lowerBound ? trimmed : nil
        } catch {
            return nil
        }
    }
}
