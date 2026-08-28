import Foundation

/// 后台 AI 分类服务：复用既有 `OpenAICompatibleChatService`（OpenAI 兼容 Endpoint+API Key）。
///
/// 进文章（详情加载 / 刷新）时异步调用；先查本地缓存命中由调用方去重。
/// 离线 / 无 Key / 调用失败 → 本地关键词兜底或归「其他」；
/// AI 返回不在集合内或低置信度 → 一律归「其他」。全程仅发送标题+正文用于分类本身。
@MainActor
final class ArticleClassificationService {
    private let chatService: AIChatServicing
    private let configurationStore: AIConfigurationStore
    /// 低置信度阈值（规格要求为 static let，固定 0.5）。
    static let confidenceThreshold: Double = 0.5

    init(
        chatService: AIChatServicing = OpenAICompatibleChatService(),
        configurationStore: AIConfigurationStore
    ) {
        self.chatService = chatService
        self.configurationStore = configurationStore
    }

    /// 对单篇做分类：先判断可用，再走 AI，失败 / 越界 / 低置信度归 other。
    func classify(articleID: Int, title: String, text: String, taxonomy: CategoryTaxonomy) async -> ArticleClassification {
        guard configurationStore.isReady else {
            return localFallback(articleID: articleID, title: title, text: text)
        }
        let providers = configurationStore.runtimeProviders()
        guard let provider = providers.first else {
            return localFallback(articleID: articleID, title: title, text: text)
        }
        do {
            let prompt = Self.prompt(title: title, text: text, taxonomy: taxonomy)
            let messages: [AIChatMessage] = [AIChatMessage(role: .user, content: prompt)]
            var accumulated = ""
            for try await event in chatService.streamReply(
                configuration: provider.configuration,
                apiKey: provider.apiKey,
                messages: messages,
                articleContext: nil
            ) {
                if case .text(let delta) = event { accumulated += delta }
            }
            if let parsed = parse(accumulated, taxonomy: taxonomy, articleID: articleID) {
                return parsed
            }
        } catch {
            // 离线 / 超时 / 解析失败 → 本地兜底。
        }
        return localFallback(articleID: articleID, title: title, text: text)
    }

    // MARK: - prompt / 解析 / 兜底

    private static func prompt(title: String, text: String, taxonomy: CategoryTaxonomy) -> String {
        let names = (taxonomy.categories.map(\.name) + ["其他"]).joined(separator: "、")
        return """
        从下列固定类目中选择最契合的一篇，只返回一个 JSON：
        {"category": "<必须严格是下列名称之一>", "confidence": <0到1的小数>}
        固定类目：\(names)
        规则：若都不合适或不确定，category 必须为"其他"。
        标题：\(title)
        正文：\(text.prefix(6000))
        """
    }

    /// 解析 AI 返回的 JSON；越界类目或低置信度一律归「其他」。
    func parse(_ raw: String, taxonomy: CategoryTaxonomy, articleID: Int) -> ArticleClassification? {
        guard let data = raw.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let name = json["category"] as? String,
              let confidence = json["confidence"] as? Double else {
            return nil
        }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let matched = taxonomy.categories.first {
            $0.name.trimmingCharacters(in: .whitespacesAndNewlines)
                .caseInsensitiveCompare(trimmedName) == .orderedSame
        }
        let categoryID = matched?.id ?? ArticleCategory.other.id
        if categoryID == ArticleCategory.other.id || confidence < Self.confidenceThreshold {
            return ArticleClassification(
                articleID: articleID,
                categoryID: ArticleCategory.other.id,
                confidence: confidence,
                source: .remote
            )
        }
        return ArticleClassification(
            articleID: articleID,
            categoryID: categoryID,
            confidence: confidence,
            source: .remote
        )
    }

    /// 本地关键词兜底：命中关键词表映射该类目；都不命中归「其他」。
    func localFallback(articleID: Int, title: String, text: String) -> ArticleClassification {
        let haystack = (title + " " + text).lowercased()
        for entry in BuiltInCategoryDefaults.keywordMap {
            if entry.keywords.contains(where: { haystack.contains($0.lowercased()) }) {
                return ArticleClassification(
                    articleID: articleID,
                    categoryID: entry.categoryID,
                    confidence: 0.4,
                    source: .local
                )
            }
        }
        return ArticleClassification(
            articleID: articleID,
            categoryID: ArticleCategory.other.id,
            confidence: 0,
            source: .local
        )
    }
}
