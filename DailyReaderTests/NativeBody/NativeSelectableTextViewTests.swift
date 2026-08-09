import UIKit
import XCTest
@testable import DailyReader

final class NativeSelectableTextViewTests: XCTestCase {
    func testAISearchActionPassesCurrentTextSelection() {
        let view = NativeSelectableTextView()
        view.attributedText = NSAttributedString(string: "原生正文可以选中")
        view.selectedRange = NSRange(location: 2, length: 2)

        var selection = ""
        view.onAISearch = { selection = $0 }
        view.searchSelectionWithAI()

        XCTAssertEqual(selection, "正文")
    }

    func testAISearchActionIgnoresEmptySelection() {
        let view = NativeSelectableTextView()
        view.attributedText = NSAttributedString(string: "原生正文")
        view.selectedRange = NSRange(location: 0, length: 0)

        var invoked = false
        view.onAISearch = { _ in invoked = true }
        view.searchSelectionWithAI()

        XCTAssertFalse(invoked)
    }
}
