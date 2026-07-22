import SwiftUI

/// Renders parsed Markdown blocks as native SwiftUI views (headings, paragraphs,
/// lists, quotes, rules) with tappable links. This replaces the single
/// `AttributedString(markdown:.full)` Text, which could not lay out block
/// structure. Inline styling still flows through AttributedString per block.
struct MarkdownView: View {
    let markdown: String
    @Environment(\.openURL) private var openURL

    private var blocks: [MDBlock] { MarkdownParser.parse(markdown) }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            // Positional identity: stable across re-renders (unlike a random id) and
            // unique even when two blocks share content (e.g. multiple rules).
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func blockView(_ block: MDBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            Text(MarkdownParser.inlineAttributed(text))
                .font(headingFont(level))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, level <= 2 ? DS.Space.xs : 0)

        case .paragraph(let text):
            Text(MarkdownParser.inlineAttributed(text))
                .font(DS.Typo.body)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

        case .bullet(let items):
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                ForEach(items.indices, id: \.self) { i in
                    listRow(marker: "•", text: items[i])
                }
            }

        case .ordered(let items):
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                ForEach(items.indices, id: \.self) { i in
                    listRow(marker: "\(i + 1).", text: items[i])
                }
            }

        case .quote(let text):
            HStack(alignment: .top, spacing: DS.Space.sm) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(DS.Palette.quoteBar)
                    .frame(width: 3)
                Text(MarkdownParser.inlineAttributed(text))
                    .font(DS.Typo.quote)
                    .foregroundStyle(DS.Palette.subtle)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(DS.Space.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.sm).fill(DS.Palette.quoteFill)
            )

        case .rule:
            Divider().padding(.vertical, DS.Space.xs)
        }
    }

    private func listRow(marker: String, text: String) -> some View {
        HStack(alignment: .top, spacing: DS.Space.sm) {
            Text(marker)
                .font(DS.Typo.body)
                .foregroundStyle(DS.Palette.bullet)
                .frame(minWidth: 14, alignment: .trailing)
            Text(MarkdownParser.inlineAttributed(text))
                .font(DS.Typo.body)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: DS.Typo.h1
        case 2: DS.Typo.h2
        default: DS.Typo.h3
        }
    }
}
