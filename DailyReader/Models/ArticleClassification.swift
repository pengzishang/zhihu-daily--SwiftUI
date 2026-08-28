import Foundation

/// 单篇文章的分类结果（本地缓存，不改动网络 Codable 结构）。
struct ArticleClassification: Codable, Equatable, Sendable {
    let articleID: Int
    var categoryID: String
    var confidence: Double
    var source: CategorySource
    var classifiedAt: Date

    init(
        articleID: Int,
        categoryID: String,
        confidence: Double,
        source: CategorySource,
        classifiedAt: Date = Date()
    ) {
        self.articleID = articleID
        self.categoryID = categoryID
        self.confidence = confidence
        self.source = source
        self.classifiedAt = classifiedAt
    }
}
