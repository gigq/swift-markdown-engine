//
//  MarkdownTextEditRequest.swift
//  MarkdownEngine
//
//  Document-scoped, selection-aware edit requests for UIKit editor hosts.
//  The resolver is platform-independent so its cursor behavior can be tested
//  without constructing a text view.
//

import Foundation

public enum MarkdownTextEdit: Equatable, Sendable {
    case wrapSelection(prefix: String, suffix: String)
    case cycleHeading(maxLevel: Int)
    case applyLineTemplate(template: String, placeholder: String)
    case indent
    case outdent
    case insertTemplate(template: String, placeholder: String?)
    case insertTemplateAtAnchor(
        template: String,
        anchor: MarkdownTextInsertionAnchor,
        replacesSelection: Bool
    )
}

public struct MarkdownTextInsertionAnchor: Equatable, Sendable {
    public let sourceText: String
    public let selectedRange: NSRange

    public init(sourceText: String, selectedRange: NSRange) {
        self.sourceText = sourceText
        self.selectedRange = selectedRange
    }
}

public enum MarkdownTextEditRequestResult: Equatable, Sendable {
    case applied
    case discardedDocumentMismatch
}

public struct MarkdownTextEditRequest: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let documentID: String
    public let edit: MarkdownTextEdit

    public init(id: UUID = UUID(), documentID: String, edit: MarkdownTextEdit) {
        self.id = id
        self.documentID = documentID
        self.edit = edit
    }
}

struct MarkdownTextEditResolution: Equatable {
    var replacementRange: NSRange
    var replacement: String
    var selectedRange: NSRange
}

enum MarkdownTextEditResolver {
    static func resolve(
        _ edit: MarkdownTextEdit,
        in text: String,
        selectedRange: NSRange
    ) -> MarkdownTextEditResolution {
        let selection = clamped(selectedRange, in: text)
        switch edit {
        case let .wrapSelection(prefix, suffix):
            return wrapSelection(in: text, range: selection, prefix: prefix, suffix: suffix)
        case let .cycleHeading(maxLevel):
            return editLines(in: text, range: selection) { line in
                headingLine(line, maxLevel: max(1, maxLevel))
            }
        case let .applyLineTemplate(template, placeholder):
            return applyLineTemplate(template, placeholder: placeholder, in: text, range: selection)
        case .indent:
            return editLines(in: text, range: selection) { line in
                LineEdit(replacement: "\t" + line, oldContentStart: 0, newContentStart: 1)
            }
        case .outdent:
            return editLines(in: text, range: selection) { line in
                let removalLength: Int
                if line.hasPrefix("\t") {
                    removalLength = 1
                } else if line.hasPrefix("  ") {
                    removalLength = 2
                } else {
                    removalLength = 0
                }
                let replacement = (line as NSString).substring(from: removalLength)
                return LineEdit(
                    replacement: replacement,
                    oldContentStart: removalLength,
                    newContentStart: 0
                )
            }
        case let .insertTemplate(template, placeholder):
            return insertTemplate(template, placeholder: placeholder, in: text, range: selection)
        case let .insertTemplateAtAnchor(template, anchor, replacesSelection):
            let insertionRange = translated(anchor: anchor, to: text)
            if replacesSelection, insertionRange.length > 0 {
                return MarkdownTextEditResolution(
                    replacementRange: insertionRange,
                    replacement: template,
                    selectedRange: NSRange(
                        location: insertionRange.location + template.utf16.count,
                        length: 0
                    )
                )
            }
            return insertTemplate(template, placeholder: nil, in: text, range: insertionRange)
        }
    }

    private static func translated(anchor: MarkdownTextInsertionAnchor, to text: String) -> NSRange {
        let source = Array(anchor.sourceText.utf16)
        let destination = Array(text.utf16)
        let sourceRange = clamped(anchor.selectedRange, in: anchor.sourceText)
        let difference = destination.difference(from: source)
        let removedOffsets = Set(difference.compactMap { change -> Int? in
            guard case let .remove(offset, _, _) = change else { return nil }
            return offset
        })
        let insertedOffsets = Set(difference.compactMap { change -> Int? in
            guard case let .insert(offset, _, _) = change else { return nil }
            return offset
        })

        func translatedBoundary(_ sourceOffset: Int) -> Int {
            var oldOffset = 0
            var newOffset = 0
            while oldOffset < sourceOffset {
                while insertedOffsets.contains(newOffset) {
                    newOffset += 1
                }
                if removedOffsets.contains(oldOffset) {
                    oldOffset += 1
                } else {
                    oldOffset += 1
                    newOffset += 1
                }
            }
            while insertedOffsets.contains(newOffset) {
                newOffset += 1
            }
            return validUTF16Boundary(min(newOffset, destination.count), in: destination)
        }

        let start = translatedBoundary(sourceRange.location)
        let end = max(start, translatedBoundary(NSMaxRange(sourceRange)))
        return NSRange(location: start, length: end - start)
    }

    private static func validUTF16Boundary(_ offset: Int, in codeUnits: [UInt16]) -> Int {
        guard offset > 0, offset < codeUnits.count else { return offset }
        let previous = codeUnits[offset - 1]
        let next = codeUnits[offset]
        let splitsSurrogatePair = (0xD800 ... 0xDBFF).contains(previous)
            && (0xDC00 ... 0xDFFF).contains(next)
        return splitsSurrogatePair ? offset + 1 : offset
    }

    private struct LineEdit {
        var replacement: String
        var oldContentStart: Int
        var newContentStart: Int
        var preferredSelection: NSRange?
    }

    private enum ListPrefixKind {
        case bullet
        case checklist
        case ordered
    }

    private static func wrapSelection(
        in text: String,
        range: NSRange,
        prefix: String,
        suffix: String
    ) -> MarkdownTextEditResolution {
        let prefixLength = (prefix as NSString).length
        guard range.length > 0 else {
            return MarkdownTextEditResolution(
                replacementRange: range,
                replacement: prefix + suffix,
                selectedRange: NSRange(location: range.location + prefixLength, length: 0)
            )
        }

        let original = (text as NSString).substring(with: range)
        let leading = String(original.prefix(while: \.isWhitespace))
        let remainder = String(original.dropFirst(leading.count))
        let trailing = String(remainder.reversed().prefix(while: \.isWhitespace).reversed())
        let core = String(remainder.dropLast(trailing.count))
        let leadingLength = (leading as NSString).length
        let coreLength = (core as NSString).length
        return MarkdownTextEditResolution(
            replacementRange: range,
            replacement: leading + prefix + core + suffix + trailing,
            selectedRange: NSRange(
                location: range.location + leadingLength + prefixLength,
                length: coreLength
            )
        )
    }

    private static func insertTemplate(
        _ template: String,
        placeholder: String?,
        in text: String,
        range: NSRange
    ) -> MarkdownTextEditResolution {
        let templateText = template as NSString
        let placeholderRange = placeholder.map { templateText.range(of: $0) }
            .flatMap { $0.location == NSNotFound ? nil : $0 }

        if range.length > 0, let placeholderRange {
            let selectedText = (text as NSString).substring(with: range)
            let replacement = templateText.replacingCharacters(in: placeholderRange, with: selectedText)
            return MarkdownTextEditResolution(
                replacementRange: range,
                replacement: replacement,
                selectedRange: NSRange(
                    location: range.location + placeholderRange.location,
                    length: range.length
                )
            )
        }

        if range.length > 0 {
            return MarkdownTextEditResolution(
                replacementRange: NSRange(location: range.location, length: 0),
                replacement: template,
                selectedRange: NSRange(
                    location: range.location + templateText.length,
                    length: range.length
                )
            )
        }

        return MarkdownTextEditResolution(
            replacementRange: range,
            replacement: template,
            selectedRange: placeholderRange.map {
                NSRange(location: range.location + $0.location, length: $0.length)
            } ?? NSRange(location: range.location + templateText.length, length: 0)
        )
    }

    private static func applyLineTemplate(
        _ template: String,
        placeholder: String,
        in text: String,
        range: NSRange
    ) -> MarkdownTextEditResolution {
        let templateText = template as NSString
        let placeholderRange = templateText.range(of: placeholder)
        let marker = placeholderRange.location == NSNotFound
            ? template
            : templateText.substring(to: placeholderRange.location)

        return editLines(in: text, range: range) { line in
            let lineText = line as NSString
            let indentation = leadingWhitespace(in: line)
            let indentationLength = (indentation as NSString).length
            let body = lineText.substring(from: indentationLength)
            let existingPrefix = listPrefixRange(in: body)
            let existingMarker = (body as NSString).substring(with: existingPrefix)
            let oldContentStart = indentationLength + existingPrefix.length

            if body.isEmpty, placeholderRange.location != NSNotFound {
                return LineEdit(
                    replacement: indentation + template,
                    oldContentStart: indentationLength,
                    newContentStart: indentationLength + marker.utf16.count,
                    preferredSelection: NSRange(
                        location: indentationLength + placeholderRange.location,
                        length: placeholderRange.length
                    )
                )
            }

            let isRemoving = listPrefixKind(in: existingMarker) == listPrefixKind(in: marker)
            let content = (body as NSString).substring(from: existingPrefix.length)
            let replacementPrefix = isRemoving ? indentation : indentation + marker
            return LineEdit(
                replacement: replacementPrefix + content,
                oldContentStart: oldContentStart,
                newContentStart: (replacementPrefix as NSString).length
            )
        }
    }

    private static func headingLine(_ line: String, maxLevel: Int) -> LineEdit {
        let indentation = leadingWhitespace(in: line)
        let indentationLength = (indentation as NSString).length
        let body = (line as NSString).substring(from: indentationLength)
        let headingRange = headingPrefixRange(in: body)
        let currentLevel: Int
        if headingRange.length > 0 {
            let prefix = (body as NSString).substring(with: headingRange)
            currentLevel = prefix.prefix(while: { $0 == "#" }).count
        } else {
            currentLevel = 0
        }
        let nextLevel = currentLevel >= maxLevel ? 0 : currentLevel + 1
        let newMarker = nextLevel == 0 ? "" : String(repeating: "#", count: nextLevel) + " "
        let content = (body as NSString).substring(from: headingRange.length)
        return LineEdit(
            replacement: indentation + newMarker + content,
            oldContentStart: indentationLength + headingRange.length,
            newContentStart: indentationLength + (newMarker as NSString).length
        )
    }

    private static func editLines(
        in text: String,
        range: NSRange,
        transform: (String) -> LineEdit
    ) -> MarkdownTextEditResolution {
        let textValue = text as NSString
        let lineRange = textValue.lineRange(for: range)
        let block = textValue.substring(with: lineRange)
        let hasTrailingNewline = block.hasSuffix("\n")
        var lines = block.components(separatedBy: "\n")
        if hasTrailingNewline, lines.last == "" {
            lines.removeLast()
        }
        if lines.isEmpty {
            lines = [""]
        }

        let edits = lines.map(transform)
        var replacement = edits.map(\.replacement).joined(separator: "\n")
        if hasTrailingNewline {
            replacement += "\n"
        }

        let newSelection: NSRange
        if range.length == 0, let firstEdit = edits.first {
            if let preferred = firstEdit.preferredSelection {
                newSelection = NSRange(
                    location: lineRange.location + preferred.location,
                    length: preferred.length
                )
            } else {
                let oldOffset = range.location - lineRange.location
                let contentOffset = max(0, oldOffset - firstEdit.oldContentStart)
                let newLineLength = (firstEdit.replacement as NSString).length
                newSelection = NSRange(
                    location: lineRange.location + min(
                        firstEdit.newContentStart + contentOffset,
                        newLineLength
                    ),
                    length: 0
                )
            }
        } else {
            let selectedLength = (replacement as NSString).length - (hasTrailingNewline ? 1 : 0)
            newSelection = NSRange(location: lineRange.location, length: max(0, selectedLength))
        }

        return MarkdownTextEditResolution(
            replacementRange: lineRange,
            replacement: replacement,
            selectedRange: newSelection
        )
    }

    private static func leadingWhitespace(in string: String) -> String {
        String(string.prefix { $0 == " " || $0 == "\t" })
    }

    private static func headingPrefixRange(in string: String) -> NSRange {
        firstMatchRange(pattern: #"^#{1,6}[ \t]+"#, in: string)
    }

    private static func listPrefixRange(in string: String) -> NSRange {
        firstMatchRange(pattern: #"^(?:[-+*•]|[0-9]+\.)[ \t]+(?:\[[ xX]\][ \t]+)?"#, in: string)
    }

    private static func listPrefixKind(in marker: String) -> ListPrefixKind? {
        guard !marker.isEmpty else { return nil }
        if marker.range(of: #"\[[ xX]\]"#, options: .regularExpression) != nil {
            return .checklist
        }
        if marker.range(of: #"^[0-9]+\."#, options: .regularExpression) != nil {
            return .ordered
        }
        return .bullet
    }

    private static func firstMatchRange(pattern: String, in string: String) -> NSRange {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                in: string,
                range: NSRange(location: 0, length: (string as NSString).length)
              ) else {
            return NSRange(location: 0, length: 0)
        }
        return match.range
    }

    private static func clamped(_ range: NSRange, in text: String) -> NSRange {
        let length = (text as NSString).length
        let location = min(max(0, range.location), length)
        return NSRange(
            location: location,
            length: min(max(0, range.length), length - location)
        )
    }
}
