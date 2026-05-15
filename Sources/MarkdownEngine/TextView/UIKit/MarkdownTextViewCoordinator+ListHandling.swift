//
//  MarkdownTextViewCoordinator+ListHandling.swift
//  MarkdownEngine
//
//  Port of the Mac `MarkdownLists.handleInsertion` newline / tab logic to
//  UITextView via `textView(_:shouldChangeTextIn:replacementText:)`. Covers
//  the high-value ergonomics: list continuation on Enter, list outdent when
//  Enter is pressed on an empty list item, and Tab to indent inside a list.
//
//  Deferred (port later if needed): auto-pair `[`/`(`/`{`, wiki-link `[[`
//  autocomplete, `->` → `→` arrow, `---` HR expansion, code-fence completion,
//  and the space-to-bullet conversion for `-` / `N.`.
//

#if os(iOS) || os(visionOS)
import UIKit

extension MarkdownTextViewCoordinator {

    public func textView(
        _ textView: UITextView,
        shouldChangeTextIn range: NSRange,
        replacementText text: String
    ) -> Bool {
        guard let mdTextView = textView as? MarkdownTextView,
              !mdTextView.isPerformingProgrammaticEdit else { return true }

        let nsText = (textView.text ?? "") as NSString
        let safeLoc = min(range.location, nsText.length)
        let isInCodeBlock = (textView.text ?? "").contains("`")
            && MarkdownDetection.isInsideCodeBlock(location: safeLoc, in: textView.text ?? "")
        let listsEnabled = configuration.lists.helpersEnabled

        if text == "\n" {
            return handleNewline(in: textView, mdTextView: mdTextView, range: range, isInCodeBlock: isInCodeBlock, listsEnabled: listsEnabled)
        }
        if text == "\t" && !isInCodeBlock && listsEnabled {
            return handleTab(in: textView, mdTextView: mdTextView, range: range)
        }
        return true
    }

    // MARK: - Newline (list continuation / outdent)

    private func handleNewline(
        in textView: UITextView,
        mdTextView: MarkdownTextView,
        range: NSRange,
        isInCodeBlock: Bool,
        listsEnabled: Bool
    ) -> Bool {
        guard listsEnabled, !isInCodeBlock else { return true }
        let nsText = (textView.text ?? "") as NSString
        let safeLoc = min(range.location, nsText.length)
        let currentLineRange = nsText.lineRange(for: NSRange(location: safeLoc, length: 0))
        let listLine = nsText.substring(with: currentLineRange)

        guard let match = MarkdownLists.listRegex.firstMatch(
            in: listLine,
            range: NSRange(location: 0, length: listLine.utf16.count)
        ) else {
            return true
        }

        let contentStart = match.range.location + match.range.length
        let contentLength = listLine.utf16.count - contentStart
        let contentRangeLocal = NSRange(location: contentStart, length: contentLength)
        let contentText = (listLine as NSString)
            .substring(with: contentRangeLocal)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if contentText.isEmpty {
            // Outdent: remove the marker, drop to a blank line.
            let removalLengthRaw = match.range.location + match.range.length
            let lineEnd = currentLineRange.location + currentLineRange.length
            let hasNewline = currentLineRange.length > 0
                && nsText.substring(with: NSRange(location: lineEnd - 1, length: 1)) == "\n"
            let maxBodyLen = hasNewline ? currentLineRange.length - 1 : currentLineRange.length
            let removalLength = min(removalLengthRaw, maxBodyLen)
            let removalRange = NSRange(location: currentLineRange.location, length: removalLength)
            performEdit(textView: mdTextView, replace: removalRange, with: "")
            mdTextView.selectedRange = NSRange(location: currentLineRange.location, length: 0)
            return false
        }

        let leadingWhitespace: String
        if let wsMatch = MarkdownLists.leadingWhitespaceRegex.firstMatch(
            in: listLine,
            range: NSRange(location: 0, length: listLine.utf16.count)
        ) {
            leadingWhitespace = (listLine as NSString).substring(with: wsMatch.range)
        } else {
            leadingWhitespace = ""
        }
        let markerRaw = (listLine as NSString).substring(with: match.range(at: 1))
        let marker = markerRaw.trimmingCharacters(in: .whitespaces)
        let hasCheckbox = marker.range(of: #"\[[ xX]\]"#, options: .regularExpression) != nil

        let newListItem: String
        if match.range(at: 2).location != NSNotFound,
           let number = Int((listLine as NSString).substring(with: match.range(at: 2))) {
            if hasCheckbox {
                newListItem = "\n" + leadingWhitespace + "\(number + 1). [ ] "
            } else {
                newListItem = "\n" + leadingWhitespace + "\(number + 1). "
            }
        } else {
            let prefixIndent = leadingWhitespace.isEmpty ? "  " : leadingWhitespace
            if hasCheckbox {
                let bulletChar = marker.contains("•") ? "•" : "-"
                newListItem = "\n" + prefixIndent + "\(bulletChar) [ ] "
            } else {
                newListItem = "\n" + prefixIndent + marker + " "
            }
        }
        performEdit(textView: mdTextView, replace: range, with: newListItem)
        return false
    }

    // MARK: - Tab (list indent)

    private func handleTab(
        in textView: UITextView,
        mdTextView: MarkdownTextView,
        range: NSRange
    ) -> Bool {
        let nsText = (textView.text ?? "") as NSString
        let safeLoc = min(range.location, nsText.length)
        let currentLineRange = nsText.lineRange(for: NSRange(location: safeLoc, length: 0))
        let currentLine = nsText.substring(with: currentLineRange)

        let inFullList = MarkdownLists.listRegex.firstMatch(
            in: currentLine,
            range: NSRange(location: 0, length: currentLine.utf16.count)
        ) != nil
        let inDashNoSpace = MarkdownLists.dashNoSpaceRegex.firstMatch(
            in: currentLine,
            range: NSRange(location: 0, length: currentLine.utf16.count)
        ) != nil

        guard inFullList || inDashNoSpace else { return true }

        if let wsMatch = MarkdownLists.leadingWhitespaceRegex.firstMatch(
            in: currentLine,
            range: NSRange(location: 0, length: currentLine.utf16.count)
        ) {
            let ws = (currentLine as NSString).substring(with: wsMatch.range)
            let level = MarkdownLists.indentLevel(from: ws)
            if level >= configuration.lists.maximumNestingLevel { return false }
        }

        performEdit(
            textView: mdTextView,
            replace: NSRange(location: currentLineRange.location, length: 0),
            with: "\t"
        )
        mdTextView.selectedRange = NSRange(location: safeLoc + 1, length: 0)
        return false
    }

    // MARK: - Programmatic edit helper

    /// UITextView analogue of Mac's `MarkdownLists.performEdit`. Mutates the
    /// storage directly so the change applies in-place (UITextView's
    /// `shouldChangeTextIn` returning false would otherwise discard it),
    /// then drives the standard change cycle so styling updates fire.
    func performEdit(
        textView: MarkdownTextView,
        replace range: NSRange,
        with string: String
    ) {
        textView.isPerformingProgrammaticEdit = true
        let storage = textView.textStorage
        let safeLoc = min(range.location, storage.length)
        let safeLen = min(range.length, storage.length - safeLoc)
        let safeRange = NSRange(location: safeLoc, length: safeLen)
        storage.replaceCharacters(in: safeRange, with: string)
        let newCaret = safeLoc + (string as NSString).length
        textView.selectedRange = NSRange(location: min(newCaret, storage.length), length: 0)
        textView.isPerformingProgrammaticEdit = false

        // Fire the change cycle so binding + restyle stay in sync.
        textViewDidChange(textView)
    }
}
#endif
