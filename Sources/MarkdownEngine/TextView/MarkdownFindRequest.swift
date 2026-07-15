import Foundation

/// A one-shot request for the native find interface hosted by a Markdown
/// editor. Set a wrapper's request binding to a new value for each action; the
/// wrapper performs it against its text view and clears the binding.
public struct MarkdownFindRequest: Equatable, Identifiable, Sendable {
    public enum Action: Equatable, Sendable {
        case present(showingReplace: Bool)
        case nextMatch
        case previousMatch
    }

    public let id: UUID
    public let documentID: String
    public let action: Action

    public init(id: UUID = UUID(), documentID: String, action: Action) {
        self.id = id
        self.documentID = documentID
        self.action = action
    }
}
