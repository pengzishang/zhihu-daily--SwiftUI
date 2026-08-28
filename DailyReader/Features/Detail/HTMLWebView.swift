import SwiftUI
import WebKit

struct HTMLWebView: UIViewRepresentable {
    let htmlBody: String
    let cssLinks: [String]
    let reloadToken: Int
    let fontSize: Double
    @Binding var contentHeight: CGFloat
    @Binding var isLoading: Bool
    let onImageTap: (String) -> Void
    let enablesAISearch: Bool
    let onAISelection: (String) -> Void
    let onArticleTextPrepared: (String) -> Void
    let onError: (String) -> Void

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let controller = WKUserContentController()
        controller.add(context.coordinator, name: "imageClicked")
        controller.add(context.coordinator, name: "aiSelection")
        controller.add(context.coordinator, name: "articleTextPrepared")
        controller.add(context.coordinator, name: "contentHeightChanged")
        configuration.userContentController = controller

        let webView = AISelectableWebView(frame: .zero, configuration: configuration)
        webView.showsAISearchAction = enablesAISearch
        webView.onAISearch = { [weak coordinator = context.coordinator, weak webView] in
            coordinator?.requestAISelection(from: webView)
        }
        webView.accessibilityIdentifier = "articleHTMLContent"
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.navigationDelegate = context.coordinator
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        (webView as? AISelectableWebView)?.showsAISearchAction = enablesAISearch
        let html = wrappedHTML
        let nextContentKey = ContentKey(
            reloadToken: reloadToken,
            fontSize: fontSize,
            htmlBodyHash: htmlBody.hashValue,
            cssLinksHash: cssLinks.hashValue,
            colorScheme: UITraitCollection.current.userInterfaceStyle.rawValue
        )
        guard context.coordinator.loadedContentKey != nextContentKey else {
            context.coordinator.updateHeight(for: webView)
            return
        }
        context.coordinator.loadedContentKey = nextContentKey
        webView.loadHTMLString(html, baseURL: nil)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        // 移除 WKScriptMessageHandler，避免 WKWebView ↔ Coordinator 循环持有泄漏。
        let controller = uiView.configuration.userContentController
        for name in ["imageClicked", "aiSelection", "articleTextPrepared", "contentHeightChanged"] {
            controller.removeScriptMessageHandler(forName: name)
        }
    }

    private var wrappedHTML: String {
        let css = cssLinks.map { "<link rel=\"stylesheet\" href=\"\($0)\">" }.joined(separator: "\n")
        return """
        <!doctype html>
        <html>
        <head>
          <meta name="viewport" content="width=device-width, initial-scale=1.0">
          \(css)
          <style>
            body { font: -apple-system-body; color: \(textColor); background: transparent; line-height: 1.65; padding: 0; margin: 0; font-size: \(fontSize)px !important; -webkit-user-select: text !important; user-select: text !important; }
            body * { -webkit-user-select: text !important; user-select: text !important; }
            img { max-width: 100%; height: auto; border-radius: 10px; }
            .content img, .content-inner img {
              display: block !important;
              width: 100% !important;
              height: auto !important;
              border-radius: 10px !important;
              margin: 14px 0 !important;
            }
            .avatar, .author img, .meta img, .origin-source img, .source img {
              width: 42px !important;
              height: 42px !important;
              max-width: 42px !important;
              max-height: 42px !important;
              object-fit: cover;
              border-radius: 50% !important;
              vertical-align: middle;
              margin: 0 !important;
              border: 1px solid \(mutedColor)38 !important;
              grid-column: 1 !important;
              grid-row: 1 / span 2 !important;
              align-self: center !important;
            }
            body > img:first-child, body > p:first-child img:first-child {
              max-width: 96px !important;
              max-height: 96px !important;
              object-fit: cover;
              border-radius: 14px;
              vertical-align: middle;
            }
            .meta {
              display: grid !important;
              grid-template-columns: 42px minmax(0, 1fr) !important;
              grid-template-rows: auto auto !important;
              column-gap: 12px !important;
              row-gap: 2px !important;
              align-items: center !important;
              width: 100% !important;
              box-sizing: border-box !important;
              background: transparent !important;
              padding: 12px 0 !important;
              border-radius: 0 !important;
              margin: 0 0 18px 0 !important;
              border-top: 1px solid \(mutedColor)2E !important;
              border-bottom: 1px solid \(mutedColor)2E !important;
            }
            .meta .author, .meta > .author {
              grid-column: 2 !important;
              grid-row: 1 !important;
            }
            .meta .bio, .meta > .bio {
              grid-column: 2 !important;
              grid-row: 2 !important;
            }
            .author {
              font-family: "STSongti-SC-Bold", "Songti SC", serif !important;
              font-size: 15px !important;
              font-weight: 700 !important;
              line-height: 1.25 !important;
              color: \(textColor) !important;
            }
            .bio {
              font-size: 12px !important;
              line-height: 1.4 !important;
              color: \(mutedColor) !important;
            }
            p.drop-cap::first-letter {
              float: left;
              font-family: "STSongti-SC-Black", "Songti SC", serif;
              font-size: calc(\(fontSize)px * 3.35);
              font-weight: 900;
              line-height: 0.82;
              color: \(dropCapColor);
              padding: 0.10em 0.10em 0 0;
            }
            a { color: \(linkColor); }
            a.discussion-pill {
              display: flex !important;
              align-items: center !important;
              justify-content: center !important;
              box-sizing: border-box !important;
              width: calc(100% - 16px) !important;
              min-height: 44px !important;
              padding: 12px 16px !important;
              margin: 20px 8px 8px 8px !important;
              border-radius: 10px !important;
              background: \(linkColor)21 !important;
              color: \(linkColor) !important;
              font-weight: 600 !important;
              text-decoration: none !important;
            }
            a.discussion-pill:active {
              background: \(linkColor)3D !important;
            }
            blockquote {
              border-left: 3px solid \(mutedColor)66 !important;
              color: \(mutedColor) !important;
              padding-left: 12px !important;
              margin-left: 8px !important;
              margin-right: 0 !important;
              margin-top: 10px !important;
              margin-bottom: 10px !important;
            }
          </style>
        </head>
        <body>
          \(htmlBody)
          <script>
            document.querySelectorAll('a').forEach(function(link) {
              if ((link.textContent || '').trim().indexOf('查看知乎讨论') !== -1) {
                link.classList.add('discussion-pill');
              }
            });
            var firstParagraph = Array.from(document.querySelectorAll('p')).find(function(paragraph) {
              return !paragraph.closest('.meta') && (paragraph.textContent || '').trim().length > 0;
            });
            if (firstParagraph) {
              var firstText = (firstParagraph.textContent || '').trim();
              var firstToken = firstText.charAt(0).toUpperCase();
              var isQuestionAnswer = firstToken === 'Q' || firstToken === '问' || firstText.indexOf('Q:') === 0 || firstText.indexOf('Q：') === 0;
              if (!isQuestionAnswer) {
                firstParagraph.classList.add('drop-cap');
              }
            }
            document.querySelectorAll('img').forEach(function(img) {
              if (img.classList.contains('avatar') || img.closest('.avatar') || img.closest('.author') || img.closest('.source')) {
                return;
              }
              img.style.cursor = 'pointer';
              img.addEventListener('click', function() {
                window.webkit.messageHandlers.imageClicked.postMessage(img.src);
              });
            });
            var articleText = (document.body.innerText || '').replace(/\\s+/g, ' ').trim();
            window.webkit.messageHandlers.articleTextPrepared.postMessage(articleText);
            function reportContentHeight() {
              var height = Math.max(document.body.scrollHeight, document.documentElement.scrollHeight, document.body.offsetHeight, document.documentElement.offsetHeight);
              window.webkit.messageHandlers.contentHeightChanged.postMessage(height);
            }
            window.addEventListener('load', reportContentHeight);
            if (window.ResizeObserver) {
              new ResizeObserver(reportContentHeight).observe(document.body);
            }
            reportContentHeight();
          </script>
        </body>
        </html>
        """
    }

    /// 正文墨色（随深浅色即时解析；外观切换时 ContentKey 变化会触发重载）
    private var textColor: String {
        DS.inkUI.resolvedColor(with: UITraitCollection.current).hexString
    }

    /// 链接靛蓝（蓝黑墨水）
    private var linkColor: String {
        DS.indigoUI.resolvedColor(with: UITraitCollection.current).hexString
    }

    /// 首字朱砂色，与「今日刊」主题的印章强调色保持一致
    private var dropCapColor: String {
        DS.cinnabarUI.resolvedColor(with: UITraitCollection.current).hexString
    }

    /// 辅助淡墨（引用、作者简介、题注）
    private var mutedColor: String {
        DS.inkSecondaryUI.resolvedColor(with: UITraitCollection.current).hexString
    }

    struct ContentKey: Equatable {
        let reloadToken: Int
        let fontSize: Double
        let htmlBodyHash: Int
        let cssLinksHash: Int
        let colorScheme: Int
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: HTMLWebView
        var loadedContentKey: ContentKey?

        init(parent: HTMLWebView) {
            self.parent = parent
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            switch message.name {
            case "imageClicked":
                if let imageURL = message.body as? String { parent.onImageTap(imageURL) }
            case "aiSelection":
                if let selection = message.body as? String {
                    let normalized = selection.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !normalized.isEmpty { parent.onAISelection(normalized) }
                }
            case "articleTextPrepared":
                if let text = message.body as? String { parent.onArticleTextPrepared(text) }
            default:
                break
            }
        }

        func requestAISelection(from webView: WKWebView?) {
            webView?.evaluateJavaScript("window.getSelection ? window.getSelection().toString() : ''") { [weak self] value, _ in
                guard let selection = value as? String else { return }
                let normalized = selection.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !normalized.isEmpty else { return }
                DispatchQueue.main.async {
                    self?.parent.onAISelection(normalized)
                }
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            updateHeight(for: webView)
            DispatchQueue.main.async { [weak self] in
                self?.parent.isLoading = false
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            parent.onError("文章内容加载失败，请重试")
            DispatchQueue.main.async { [weak self] in
                self?.parent.isLoading = false
            }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            parent.onError("文章内容加载失败，请重试")
            DispatchQueue.main.async { [weak self] in
                self?.parent.isLoading = false
            }
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            parent.onError("文章内容加载失败，请重试")
            DispatchQueue.main.async { [weak self] in
                self?.parent.isLoading = false
            }
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard
                navigationAction.navigationType == .linkActivated,
                let url = navigationAction.request.url,
                ["http", "https"].contains(url.scheme?.lowercased())
            else {
                decisionHandler(.allow)
                return
            }

            UIApplication.shared.open(url)
            decisionHandler(.cancel)
        }

        func updateHeight(for webView: WKWebView) {
            webView.evaluateJavaScript(
                "Math.max(document.body.scrollHeight, document.documentElement.scrollHeight, document.body.offsetHeight, document.documentElement.offsetHeight);"
            ) { [weak self] result, _ in
                guard let self else { return }
                let measuredHeight: CGFloat
                if let value = result as? CGFloat {
                    measuredHeight = value
                } else if let value = result as? Double {
                    measuredHeight = CGFloat(value)
                } else if let value = result as? Int {
                    measuredHeight = CGFloat(value)
                } else {
                    measuredHeight = 0
                }

                let nextHeight = max(measuredHeight, 520)
                DispatchQueue.main.async {
                    if abs(self.parent.contentHeight - nextHeight) > 1 {
                        self.parent.contentHeight = nextHeight
                    }
                }
            }
        }
    }
}

private final class AISelectableWebView: WKWebView {
    var showsAISearchAction = false
    var onAISearch: (() -> Void)?

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if action == #selector(searchSelectionWithAI) {
            return showsAISearchAction
        }
        return super.canPerformAction(action, withSender: sender)
    }

    override func buildMenu(with builder: UIMenuBuilder) {
        super.buildMenu(with: builder)
        guard showsAISearchAction else { return }
        let action = UIAction(title: "AI 搜索", image: UIImage(systemName: "text.bubble")) { [weak self] _ in
            self?.onAISearch?()
        }
        let menu = UIMenu(title: "", options: .displayInline, children: [action])
        builder.insertSibling(menu, afterMenu: .lookup)
    }

    @objc private func searchSelectionWithAI() {
        onAISearch?()
    }
}

private extension UIColor {
    var hexString: String {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        getRed(&red, green: &green, blue: &blue, alpha: nil)
        return String(format: "#%02X%02X%02X", Int(red * 255), Int(green * 255), Int(blue * 255))
    }
}
