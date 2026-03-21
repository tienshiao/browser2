import Foundation

extension String {
    /// Escapes the string for safe embedding inside single-quoted JavaScript strings.
    /// Handles backslashes, single quotes, and newlines.
    var jsEscapedForSingleQuotes: String {
        replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "\\n")
    }

    /// Escapes the string for safe embedding inside JavaScript template literals (backtick strings).
    /// Handles backslashes, backticks, and `${` interpolation sequences.
    var jsEscapedForTemplateLiteral: String {
        replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "${", with: "\\${")
    }
}
