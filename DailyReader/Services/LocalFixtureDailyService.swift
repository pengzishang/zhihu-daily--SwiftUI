import Foundation

final class LocalFixtureDailyService: DailyServiceProtocol {
    private let scenario: String

    init(scenario: String) {
        self.scenario = scenario
    }

    func fetchLatest() async throws -> DailyResponse {
        if scenario == "offline_no_cache" {
            throw APIError.transport("模拟离线")
        }
        if scenario == "latest_empty" {
            return DailyResponse(date: "20260621", stories: [], topStories: [])
        }
        if scenario == "latest_without_top_stories" {
            return DailyResponse(
                date: "20260621",
                stories: [
                    StorySummary(
                        id: 1001,
                        title: "今天，先读一篇长一点的故事",
                        images: [],
                        hint: "日报阅读器",
                        url: "https://example.com/story/1001"
                    )
                ],
                topStories: []
            )
        }
        return DailyResponse(
            date: "20260621",
            stories: [
                StorySummary(id: 1001, title: "今天，先读一篇长一点的故事", images: [], hint: "日报阅读器", url: "https://example.com/story/1001"),
                StorySummary(id: 1002, title: "SwiftUI 里的温柔边界", images: [], hint: "设计与工程", url: "https://example.com/story/1002")
            ],
            topStories: [
                TopStory(id: 1001, title: "今天，先读一篇长一点的故事", image: nil, url: "https://example.com/story/1001")
            ]
        )
    }

    func fetchBefore(date: String) async throws -> DailyResponse {
        DailyResponse(
            date: "20260620",
            stories: [
                StorySummary(id: 9001, title: "昨天的好问题", images: [], hint: "历史日报", url: "https://example.com/story/9001")
            ]
        )
    }

    func fetchDetail(id: Int) async throws -> ArticleDetail {
        if scenario == "detail_empty_body" {
            return ArticleDetail(id: id, title: "文章内容暂不可用", body: "", shareURL: nil)
        }
        if scenario == "detail_missing_share" {
            return ArticleDetail(
                id: id,
                title: "无分享链接文章",
                body: "<p>这篇文章用于验证缺失分享链接时不会分享错误内容。</p>",
                shareURL: nil,
                url: nil
            )
        }
        if scenario == "detail_long_body" {
            let paragraphs = (1...40)
                .map { "<p>长正文段落 \($0)：用于验证详情页可以从头到尾完整滚动阅读。</p>" }
                .joined()
            return ArticleDetail(
                id: id,
                title: "长正文阅读验证",
                body: "\(paragraphs)<p>长正文结尾标记</p>",
                shareURL: "https://example.com/story/\(id)"
            )
        }
        if scenario == "detail_body_image" {
            return ArticleDetail(
                id: id,
                title: "图片预览验证",
                body: "<img src='data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///ywAAAAAAQABAAACAUwAOw==' alt='可预览图片'><p>图片预览结束。</p>",
                image: nil,
                shareURL: "https://example.com/story/\(id)"
            )
        }
        return ArticleDetail(
            id: id,
            title: "今天，先读一篇长一点的故事",
            body: """
            <div class='meta'>
              <img class='avatar' src='data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///ywAAAAAAQABAAACAUwAOw==' alt='枫问头像'>
              <span class='author'>枫问</span>
              <span class='bio'>写回答挣猫粮</span>
            </div>
            <a class='originUrl' href='https://www.zhihu.com/question/123456/answer/2063881339825394412' hidden>查看原回答</a>
            <p>这是一篇用于 UI 测试的日报文章。它不使用官方品牌资产，只验证阅读闭环。</p>
            """,
            image: nil,
            shareURL: "https://example.com/story/\(id)"
        )
    }

    func fetchStoryMetrics(id: Int) async throws -> DailyStoryMetrics {
        if scenario == "metrics_unavailable" {
            throw APIError.transport("模拟指标不可用")
        }
        if scenario == "metrics_partial" {
            return DailyStoryMetrics(popularity: 30, comments: nil)
        }
        return DailyStoryMetrics(
            popularity: id == 1001 ? 30 : 16,
            comments: id == 1001 ? 10 : 3,
            longComments: id == 1001 ? 4 : 1,
            shortComments: id == 1001 ? 6 : 2
        )
    }

    func fetchAnswerMetrics(answerID: Int) async throws -> OriginalAnswerMetrics {
        if scenario == "metrics_unavailable" {
            throw APIError.transport("模拟原回答指标不可用")
        }
        return OriginalAnswerMetrics(
            id: answerID,
            voteupCount: 1_848,
            commentCount: 179,
            favoriteListCount: 1_050
        )
    }

    func fetchHotList() async throws -> HotListResponse {
        if scenario == "hot_list_timeout" {
            throw APIError.transport("请求超时，请稍后重试")
        }
        if scenario == "hot_list_empty" {
            return HotListResponse(data: [])
        }
        let items = (1...50).map { i in
            HotItem(
                id: i,
                target: HotTarget(
                    id: i,
                    title: "热榜测试标题 \(i)：这是一个关于 Swift 编程语言的精选讨论问题？",
                    excerpt: "这是第 \(i) 个热榜问题的摘要内容，点击可以进入精选回答列表。",
                    thumbnail: "https://example.com/hot/\(i).jpg"
                ),
                detailText: "\(51 - i)万热度"
            )
        }
        return HotListResponse(data: items)
    }

    func fetchAnswers(questionID: Int) async throws -> AnswersResponse {
        if scenario == "answers_forbidden" {
            throw APIError.httpStatus(403)
        }
        if scenario == "answers_empty" {
            return AnswersResponse(data: [])
        }
        let list = (1...20).map { i in
            AnswerItem(
                id: questionID * 1000 + i,
                author: AnswerAuthor(
                    name: "回答作者 \(i)",
                    avatarUrl: "https://example.com/avatar/\(i).png"
                ),
                content: scenario == "answers_empty_body" ? "" : (scenario == "answers_complex_html" ? "<p>复杂排版公式: $$e^{i\\pi} + 1 = 0$$</p><pre><code>let x = 42</code></pre><p><a href='https://example.com'>链接示例</a></p>" : "<p>这是回答 \(i) 的 HTML 格式正文内容，供 UI 测试进行完整渲染验证。</p>"),
                excerpt: "这是第 \(i) 个精选回答的摘要内容，包含了作者的观点和回答预览，点赞数较多。",
                voteupCount: 10000 - i * 100
            )
        }
        return AnswersResponse(data: list)
    }
}
