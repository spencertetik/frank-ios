import SwiftUI
import MarkdownUI

private typealias FrankTheme = Theme

struct MarkdownView: View {
    let text: String
    
    var body: some View {
        Markdown(text)
            .markdownTheme(.frankChat)
            .markdownTextStyle {
                FontSize(16)
                ForegroundColor(.white)
            }
                        .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private extension MarkdownUI.Theme {
    static let frankChat: MarkdownUI.Theme = {
        let base = MarkdownUI.Theme()
            .text {
                ForegroundColor(.white)
            }
            .strong {
                FontWeight(.semibold)
            }
            .emphasis {
                FontStyle(.italic)
            }
            .link {
                ForegroundColor(FrankTheme.accent)
                UnderlineStyle(.single)
            }
            .code {
                FontFamilyVariant(.monospaced)
                FontSize(.em(0.9))
                ForegroundColor(.white)
                BackgroundColor(Color.white.opacity(0.08))
            }
            .heading1 { configuration in
                configuration.label
                    .markdownTextStyle {
                        FontWeight(.semibold)
                        FontSize(.em(1.35))
                    }
                    .markdownMargin(top: 2, bottom: 6)
            }
            .heading2 { configuration in
                configuration.label
                    .markdownTextStyle {
                        FontWeight(.semibold)
                        FontSize(.em(1.2))
                    }
                    .markdownMargin(top: 2, bottom: 6)
            }
            .heading3 { configuration in
                configuration.label
                    .markdownTextStyle {
                        FontWeight(.semibold)
                        FontSize(.em(1.1))
                    }
                    .markdownMargin(top: 2, bottom: 6)
            }
            .paragraph { configuration in
                configuration.label
                    .fixedSize(horizontal: false, vertical: true)
                    .relativeLineSpacing(.em(0.2))
                    .markdownMargin(top: 0, bottom: 8)
            }
            .listItem { configuration in
                configuration.label
                    .markdownMargin(top: .em(0.15))
            }
            .bulletedListMarker { _ in
                Circle()
                    .fill(FrankTheme.accent)
                    .frame(width: 6, height: 6)
                    .relativeFrame(minWidth: .em(1.3), alignment: .trailing)
            }
            .numberedListMarker { configuration in
                Text("\(configuration.itemNumber).")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(FrankTheme.accent)
                    .relativeFrame(minWidth: .em(1.4), alignment: .trailing)
            }
            .codeBlock { configuration in
                ScrollView(.horizontal, showsIndicators: false) {
                    configuration.label
                        .markdownTextStyle {
                            FontFamilyVariant(.monospaced)
                            FontSize(.em(0.9))
                            ForegroundColor(.white)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
                .scrollIndicators(.hidden)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .markdownMargin(top: 4, bottom: 8)
            }
            .blockquote { configuration in
                HStack(alignment: .top, spacing: 8) {
                    Rectangle()
                        .fill(FrankTheme.accent.opacity(0.6))
                        .frame(width: 3)
                    configuration.label
                        .markdownTextStyle {
                            ForegroundColor(Color.white.opacity(0.85))
                        }
                }
                .padding(12)
                .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
                .markdownMargin(top: 4, bottom: 8)
            }
            .thematicBreak {
                Divider()
                    .overlay(Color.white.opacity(0.15))
                    .markdownMargin(top: 10, bottom: 10)
            }
        return base
    }()
}
