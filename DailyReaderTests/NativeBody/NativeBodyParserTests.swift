import XCTest
@testable import DailyReader

/// 原生正文解析器的回归与容错测试。
/// 覆盖：全量样例块序列、authorMeta 必须在 </div> 后停止（关键回归）、
/// LinkCard 嵌套标题提取、HTML 实体解码、脏 HTML 容错、纯文本展平、空输入。
final class NativeBodyParserTests: XCTestCase {

    private func kindName(_ b: ArticleBlock) -> String {
        switch b {
        case .paragraph: return "paragraph"
        case .heading: return "heading"
        case .image: return "image"
        case .figure: return "figure"
        case .blockquote: return "blockquote"
        case .divider: return "divider"
        case .authorMeta: return "authorMeta"
        case .linkCard: return "linkCard"
        case .code: return "code"
        case .discussionPill: return "discussionPill"
        case .rawText: return "rawText"
        }
    }

    /// 全量样例：p/h2/p/img/figure/blockquote/hr/meta/LinkCard/讨论药丸/code/script
    /// 「script」应被剥离，不计入块。
    func testFullSampleParsesAllBlocksInOrder() {
        let html = """
        <p>开头<strong>加粗</strong>与<em>斜体</em>以及上标<sup>注1</sup>。</p>
        <h2>小标题</h2>
        <p>含<a href="https://www.zhihu.com/question/1">内部链接</a>和<a class="external" href="https://example.com">外部</a>。</p>
        <img class="content-image" src="https://img.example.com/a.jpg" />
        <figure><img class="content-image" src="https://img.example.com/b.jpg" /><figcaption>图注</figcaption></figure>
        <blockquote><p>引用<strong>粗</strong></p></blockquote>
        <hr/>
        <div class="meta">
          <span class="author">张三</span>
          <span class="bio">答主</span>
          <img class="avatar" src="https://img.example.com/avatar.jpg" />
        </div>
        <div class="RichText-LinkCardContainer"><a class="LinkCard new" href="https://www.zhihu.com/ring/99" target="_blank"><span class="LinkCard-contents"><span class="LinkCard-title">扯点好笑的</span></span></a></div>
        <p><a class="internal" href="https://www.zhihu.com/question/9">查看知乎讨论</a></p>
        <pre><code>let x = 1
          print(x)</code></pre>
        <script>var lazy = function(){};</script>
        """
        let blocks = try! XCTUnwrap(NativeBodyRenderer.parsedBlocks(html: html))
        let types = blocks.map(kindName)
        XCTAssertEqual(types, [
            "paragraph", "heading", "paragraph", "image", "figure",
            "blockquote", "divider", "authorMeta", "linkCard",
            "discussionPill", "code"
        ])
    }

    /// 关键回归：authorMeta 命中 </div> 后必须停止，不能继续吞掉后续内容。
    func testAuthorMetaStopsAtDivClose() {
        let html = """
        <div class="meta"><span class="author">张三</span><span class="bio">答主</span><img class="avatar" src="https://x/a.jpg"/></div>
        <p>后续段落</p>
        """
        let blocks = try! XCTUnwrap(NativeBodyRenderer.parsedBlocks(html: html))
        XCTAssertEqual(blocks.count, 2)
        guard case .authorMeta(_, let m) = blocks[0] else { return XCTFail("第一个应是 authorMeta") }
        XCTAssertEqual(m.author, "张三")
        XCTAssertEqual(m.bio, "答主")
        guard case .paragraph = blocks[1] else { return XCTFail("第二个应是 paragraph") }
    }

    /// LinkCard 标题嵌套在 LinkCard-contents 内，必须正确提取。
    func testLinkCardTitleExtractedFromNestedContents() {
        let html = "<div class=\"RichText-LinkCardContainer\"><a class=\"LinkCard new\" href=\"https://www.zhihu.com/ring/99\"><span class=\"LinkCard-contents\"><span class=\"LinkCard-title\">扯点好笑的</span></span></a></div>"
        let blocks = try! XCTUnwrap(NativeBodyRenderer.parsedBlocks(html: html))
        guard case .linkCard(_, let card) = blocks[0] else { return XCTFail() }
        XCTAssertEqual(card.title, "扯点好笑的")
        XCTAssertEqual(card.url, "https://www.zhihu.com/ring/99")
    }

    func testHtmlEntityDecoding() {
        let html = "<p>AT&amp;T &lt;html&gt; &quot;引号&quot; &apos;撇&apos; &#39;</p>"
        let blocks = try! XCTUnwrap(NativeBodyRenderer.parsedBlocks(html: html))
        guard case .paragraph(_, let nodes, _) = blocks[0],
              case .text(let t) = nodes[0] else { return XCTFail() }
        XCTAssertEqual(t, "AT&T <html> \"引号\" '撇' '")
    }

    /// 脏 HTML（标签不闭合、属性无引号、缺少 >）必须容错且不崩溃。
    func testMalformedHtmlDoesNotCrash() {
        let html = "<p>未闭合<strong>粗体<div><img src=x><a href=https://y.com>链接"
        let blocks = NativeBodyRenderer.parsedBlocks(html: html)
        XCTAssertNotNil(blocks)
    }

    func testPlainTextFlattensBlocks() {
        let html = "<p>你好</p><h2>标题</h2>"
        let blocks = try! XCTUnwrap(NativeBodyRenderer.parsedBlocks(html: html))
        let text = NativeBodyRenderer.plainText(from: blocks)
        XCTAssertTrue(text.contains("你好"))
        XCTAssertTrue(text.contains("标题"))
    }

    func testEmptyHtmlReturnsNil() {
        XCTAssertNil(NativeBodyRenderer.parsedBlocks(html: "   \n  "))
    }

    /// 双重开关默认关闭，保证零回归（走 WebView）。
    func testFeatureFlagDefaultsToOff() {
        // 重置，避免其他用例污染
        UserDefaults.standard.removeObject(forKey: "DailyReader.useNativeBody")
        XCTAssertFalse(FeatureFlag.useNativeBody)
    }
}
