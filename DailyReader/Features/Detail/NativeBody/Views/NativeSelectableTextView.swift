import SwiftUI
import UIKit

final class NativeSelectableTextView: UITextView {
    var onAISearch: (String) -> Void = { _ in }

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if action == #selector(searchSelectionWithAI) {
            return !selectedText.isEmpty
        }
        return super.canPerformAction(action, withSender: sender)
    }

    override func buildMenu(with builder: UIMenuBuilder) {
        super.buildMenu(with: builder)
        let action = UIAction(title: "AI 搜索", image: UIImage(systemName: "text.bubble")) { [weak self] _ in
            self?.searchSelectionWithAI()
        }
        let menu = UIMenu(title: "", options: .displayInline, children: [action])
        builder.insertSibling(menu, afterMenu: .lookup)
    }

    @objc func searchSelectionWithAI() {
        let selection = selectedText
        guard !selection.isEmpty else { return }
        onAISearch(selection)
    }

    private var selectedText: String {
        guard selectedRange.length > 0,
              let text = attributedText?.attributedSubstring(from: selectedRange).string else {
            return ""
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct NativeSelectableAttributedText: UIViewRepresentable {
    let text: AttributedString
    let baseFont: UIFont
    let textColor: UIColor
    let lineSpacing: CGFloat
    let emphasis: NativeTextEmphasis?
    let onLinkTap: (URL) -> Void
    let onAISearch: (String) -> Void

    func makeUIView(context: Context) -> NativeSelectableTextView {
        let view = NativeSelectableTextView(frame: .zero, textContainer: nil)
        view.backgroundColor = .clear
        view.isEditable = false
        view.isScrollEnabled = false
        view.isSelectable = true
        view.dataDetectorTypes = []
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.adjustsFontForContentSizeCategory = false
        view.accessibilityIdentifier = "articleNativeSelectableText"
        view.delegate = context.coordinator
        view.onAISearch = onAISearch
        update(view, coordinator: context.coordinator)
        return view
    }

    func updateUIView(_ view: NativeSelectableTextView, context: Context) {
        view.onAISearch = onAISearch
        context.coordinator.onLinkTap = onLinkTap
        update(view, coordinator: context.coordinator)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: NativeSelectableTextView, context: Context) -> CGSize? {
        guard let width = proposal.width else { return nil }
        return uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onLinkTap: onLinkTap)
    }

    private func update(_ view: NativeSelectableTextView, coordinator: Coordinator) {
        let signature = RenderSignature(text: text, baseFont: baseFont, lineSpacing: lineSpacing, emphasis: emphasis)
        guard coordinator.renderSignature != signature else { return }

        let rendered = NSMutableAttributedString(attributedString: NSAttributedString(text))
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = lineSpacing
        rendered.addAttribute(.paragraphStyle, value: paragraphStyle, range: NSRange(location: 0, length: rendered.length))
        if let emphasis {
            rendered.addAttributes(
                [.font: emphasis.font, .foregroundColor: emphasis.color],
                range: emphasis.range
            )
        }
        view.font = baseFont
        view.textColor = textColor
        view.attributedText = rendered
        coordinator.renderSignature = signature
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var onLinkTap: (URL) -> Void
        fileprivate var renderSignature: RenderSignature?

        init(onLinkTap: @escaping (URL) -> Void) {
            self.onLinkTap = onLinkTap
        }

        func textView(
            _ textView: UITextView,
            primaryActionFor textItem: UITextItem,
            defaultAction: UIAction
        ) -> UIAction? {
            let range = textItem.range
            guard range.location != NSNotFound,
                  let url = textView.attributedText.attribute(.link, at: range.location, effectiveRange: nil) as? URL else {
                return defaultAction
            }
            return UIAction { [onLinkTap] _ in
                onLinkTap(url)
            }
        }
    }

    fileprivate struct RenderSignature: Equatable {
        let text: AttributedString
        let fontName: String
        let fontSize: CGFloat
        let lineSpacing: CGFloat
        let emphasis: EmphasisSignature?

        init(text: AttributedString, baseFont: UIFont, lineSpacing: CGFloat, emphasis: NativeTextEmphasis?) {
            self.text = text
            fontName = baseFont.fontName
            fontSize = baseFont.pointSize
            self.lineSpacing = lineSpacing
            self.emphasis = emphasis.map(EmphasisSignature.init)
        }
    }

    fileprivate struct EmphasisSignature: Equatable {
        let location: Int
        let length: Int
        let fontName: String
        let fontSize: CGFloat

        init(_ emphasis: NativeTextEmphasis) {
            location = emphasis.range.location
            length = emphasis.range.length
            fontName = emphasis.font.fontName
            fontSize = emphasis.font.pointSize
        }
    }
}

struct NativeTextEmphasis {
    let range: NSRange
    let font: UIFont
    let color: UIColor
}
