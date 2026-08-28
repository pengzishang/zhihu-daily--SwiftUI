import Foundation

/// 分类来源：远端 AI / 本地关键词兜底 / 内置默认。
enum CategorySource: String, Codable, Equatable, Sendable {
    case remote
    case local
    case `default`
}

/// 一个固定类目。id 为稳定 slug，name 用户可改。
struct ArticleCategory: Identifiable, Codable, Equatable, Hashable, Sendable {
    let id: String
    var name: String
    let isLocked: Bool
    var order: Int

    /// 兜底类目，始终存在于体系尾部，不可删除 / 改名 / 合并。
    static let other = ArticleCategory(id: "__other__", name: "其他", isLocked: true, order: Int.max)

    /// 是否为兜底类目。
    var isOther: Bool { id == ArticleCategory.other.id }

    init(id: String, name: String, isLocked: Bool = false, order: Int = 0) {
        self.id = id
        self.name = name
        self.isLocked = isLocked
        self.order = order
    }
}

/// 冻结后的类目体系。
struct CategoryTaxonomy: Codable, Equatable, Sendable {
    var categories: [ArticleCategory]
    var isFrozen: Bool
    var frozenAt: Date?
    var schemaVersion: Int

    init(categories: [ArticleCategory], isFrozen: Bool = false, frozenAt: Date? = nil, schemaVersion: Int = 1) {
        self.categories = categories
        self.isFrozen = isFrozen
        self.frozenAt = frozenAt
        self.schemaVersion = schemaVersion
    }

    /// 全部有效类目 id（含 other）。
    var allCategoryIDs: [String] { categories.map(\.id) + [ArticleCategory.other.id] }

    func category(byID id: String) -> ArticleCategory? {
        if id == ArticleCategory.other.id { return ArticleCategory.other }
        return categories.first { $0.id == id }
    }
}

/// 内置默认类目（归纳不可用时的退化方案）与本地关键词兜底表。
enum BuiltInCategoryDefaults {
    /// 10 个通用大类（不含兜底，共 11，满足 8–12 上界）。
    static let categories: [ArticleCategory] = [
        ArticleCategory(id: "tech", name: "科技", order: 0),
        ArticleCategory(id: "business", name: "商业财经", order: 1),
        ArticleCategory(id: "society", name: "社会", order: 2),
        ArticleCategory(id: "culture", name: "文化", order: 3),
        ArticleCategory(id: "science", name: "科学", order: 4),
        ArticleCategory(id: "life", name: "生活", order: 5),
        ArticleCategory(id: "health", name: "健康", order: 6),
        ArticleCategory(id: "sports", name: "体育", order: 7),
        ArticleCategory(id: "entertainment", name: "娱乐", order: 8),
        ArticleCategory(id: "education", name: "教育", order: 9)
    ]

    /// 本地关键词兜底表：关键词命中即映射该类目；都不命中归 other。
    static let keywordMap: [(categoryID: String, keywords: [String])] = [
        ("tech", ["AI", "人工智能", "芯片", "手机", "互联网", "软件", "编程", "数据"]),
        ("business", ["股票", "公司", "创业", "投资", "经济", "商业", "市场", "金融"]),
        ("society", ["社会", "新闻", "政策", "法律", "民生", "舆论", "事件"]),
        ("culture", ["书", "电影", "音乐", "艺术", "历史", "文学", "文化传统"]),
        ("science", ["物理", "化学", "生物", "数学", "宇宙", "研究", "实验", "科学"]),
        ("life", ["旅行", "美食", "家居", "穿搭", "宠物", "日常", "生活方式"]),
        ("health", ["健康", "医学", "健身", "心理", "疾病", "养生", "睡眠"]),
        ("sports", ["足球", "篮球", "奥运", "比赛", "运动员", "体育"]),
        ("entertainment", ["明星", "综艺", "电视剧", "偶像", "娱乐圈"]),
        ("education", ["高考", "大学", "考试", "教育", "学习", "学校"])
    ]
}
