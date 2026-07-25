import Foundation

/// Pastebot-style text filters: applied to an entry's plain text on demand and
/// pasted as plain text, leaving the stored entry untouched.
enum TextTransform: String, CaseIterable, Identifiable {
    case uppercased
    case lowercased
    case removeLineBreaks
    case collapseWhitespace
    case urlDecoded

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .uppercased: return "transform_uppercase"
        case .lowercased: return "transform_lowercase"
        case .removeLineBreaks: return "transform_remove_linebreaks"
        case .collapseWhitespace: return "transform_collapse_whitespace"
        case .urlDecoded: return "transform_url_decode"
        }
    }

    func apply(to text: String) -> String {
        switch self {
        case .uppercased:
            return text.uppercased()
        case .lowercased:
            return text.lowercased()
        case .removeLineBreaks:
            // CRLF must become a single space, so match it as one sequence.
            return text.replacingOccurrences(
                of: "\r\n|[\r\n\u{2028}\u{2029}]",
                with: " ",
                options: .regularExpression
            )
        case .collapseWhitespace:
            let collapsed = text
                .components(separatedBy: .whitespacesAndNewlines)
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            return collapsed
        case .urlDecoded:
            return text.removingPercentEncoding ?? text
        }
    }
}
