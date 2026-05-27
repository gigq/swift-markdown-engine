//
//  MarkdownTextView+TextBehaviors.swift
//  MarkdownEngine
//
//  Wires up UITextView's text-input policies to match the Mac editor:
//  spell-check on, autocorrect on, quote / data-detection substitution on,
//  smart-dashes off (since Markdown's `--` and `---` shouldn't get rewritten
//  to typographic dashes), plus Writing Tools (iOS 18+) and the system
//  find interaction (iOS 16+).
//

#if os(iOS) || os(visionOS)
import UIKit

extension MarkdownTextView {
    func applyDefaultTextBehaviors() {
        // Editing ergonomics — match Mac defaults from `NativeTextViewWrapper`.
        autocorrectionType = .yes
        spellCheckingType = .yes
        smartQuotesType = .yes
        smartInsertDeleteType = .yes
        // Markdown uses `--` / `---` syntactically (en/em dash & horizontal
        // rule), so the OS auto-conversion would corrupt the source. Off.
        smartDashesType = .no
        autocapitalizationType = .sentences
        dataDetectorTypes = []  // we render links ourselves via the styler

        // Find interaction (iOS 16+). UITextView exposes a system find
        // bar when this is set; the embedder can also trigger
        // `findInteraction?.presentFindNavigator(...)` directly.
        isFindInteractionEnabled = true

        // Writing Tools (iOS 18+ / visionOS 2.4+). Match the Mac editor's `.complete`
        // behavior so the user gets in-line rewrite + the inspector panel.
        if #available(iOS 18.0, visionOS 2.4, *) {
            writingToolsBehavior = .complete
        }
    }
}
#endif
