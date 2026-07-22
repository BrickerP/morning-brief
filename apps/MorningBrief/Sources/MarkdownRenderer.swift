import SwiftUI

/// A minimal block-level Markdown model. Apple's `AttributedString(markdown:)`
/// only renders *inline* styling well; block structure (headings, lists, quotes,
/// paragraph breaks) collapses. We parse blocks ourselves and let AttributedString
/// handle inline spans (bold/italic/links) inside each block.
enum MDBlock: Identifiable {
    case heading(level: Int, text: String)
    case paragraph(text: String)
    case bullet(items: [String])
    case ordered(items: [String])
    case quote(text: String)
    case rule

    var id: String {
        switch self {
        case .heading(let l, let t): "h\(l):\(t)"
        case .paragraph(let t): "p:\(t)"
        case .bullet(let items): "ul:\(items.joined(separator: "|"))"
        case .ordered(let items): "ol:\(items.joined(separator: "|"))"
        case .quote(let t): "q:\(t)"
        case .rule: "hr:\(UUID().uuidString)"
        }
    }
}

enum MarkdownParser {
    /// Parse a Markdown string into ordered blocks. Deliberately small: handles the
    /// constructs the synthesis/render layer actually emits.
    static func parse(_ markdown: String) -> [MDBlock] {
        var blocks: [MDBlock] = []
        let lines = markdown.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")

        var paragraph: [String] = []
        var bullets: [String] = []
        var ordered: [String] = []

        func flushParagraph() {
            let text = paragraph.joined(separator: " ").trimmingCharacters(in: .whitespaces)
            if !text.isEmpty { blocks.append(.paragraph(text: text)) }
            paragraph.removeAll()
        }
        func flushBullets() {
            if !bullets.isEmpty { blocks.append(.bullet(items: bullets)); bullets.removeAll() }
        }
        func flushOrdered() {
            if !ordered.isEmpty { blocks.append(.ordered(items: ordered)); ordered.removeAll() }
        }
        func flushAll() { flushParagraph(); flushBullets(); flushOrdered() }

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            if line.isEmpty { flushAll(); continue }

            // Horizontal rule
            if line == "---" || line == "***" || line == "___" {
                flushAll(); blocks.append(.rule); continue
            }

            // ATX heading
            if let hashRange = line.range(of: #"^#{1,6}\s+"#, options: .regularExpression) {
                flushAll()
                let level = line.distance(from: line.startIndex, to: hashRange.upperBound)
                    - (line[hashRange].filter { $0 == " " }.count)
                let text = String(line[hashRange.upperBound...])
                blocks.append(.heading(level: min(max(level, 1), 6), text: text))
                continue
            }

            // Blockquote
            if line.hasPrefix(">") {
                flushBullets(); flushOrdered()
                let text = String(line.dropFirst()).trimmingCharacters(in: .whitespaces)
                blocks.append(.quote(text: text))
                continue
            }

            // Unordered list
            if let r = line.range(of: #"^[-*+]\s+"#, options: .regularExpression) {
                flushParagraph(); flushOrdered()
                bullets.append(String(line[r.upperBound...]))
                continue
            }

            // Ordered list
            if let r = line.range(of: #"^\d+[.)]\s+"#, options: .regularExpression) {
                flushParagraph(); flushBullets()
                ordered.append(String(line[r.upperBound...]))
                continue
            }

            // Plain paragraph text (accumulate)
            flushBullets(); flushOrdered()
            paragraph.append(line)
        }

        flushAll()
        return blocks
    }

    /// Inline-only AttributedString (bold/italic/links). Falls back to plain text.
    static func inlineAttributed(_ text: String) -> AttributedString {
        if let a = try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            return a
        }
        return AttributedString(text)
    }
}
