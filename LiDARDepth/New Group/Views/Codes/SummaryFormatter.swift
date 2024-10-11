// SummaryFormatter.swift
// Minimal helpers to render backend Markdown (including code blocks) in SwiftUI and UIKit.

import Foundation
import SwiftUI
import UIKit

@MainActor
public enum SummaryFormatter {
    /// Normalizes literal "\\n" into real newlines and applies paragraph/line spacing.
    public static func formatParagraphs(_ raw: String,
                                        lineSpacing: CGFloat = 2,
                                        paragraphSpacing: CGFloat = 6) -> AttributedString {
        var normalized = raw.replacingOccurrences(of: "\\n", with: "\n")
        normalized = normalized.replacingOccurrences(of: "\r\n", with: "\n")

        var attributed = AttributedString(normalized)

        let para = NSMutableParagraphStyle()
        para.lineBreakMode = .byWordWrapping
        para.lineSpacing = lineSpacing
        para.paragraphSpacing = paragraphSpacing

        var container = AttributeContainer()
        container.paragraphStyle = para
        attributed.mergeAttributes(container)

        return attributed
    }

    /// Parses Markdown (after normalizing literal "\\n") to an AttributedString.
    /// Works with code blocks fenced by triple-backticks.
    public static func formatMarkdown(_ raw: String,
                                      lineSpacing: CGFloat = 2,
                                      paragraphSpacing: CGFloat = 6) -> AttributedString {
        let normalized = raw
            .replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\r\n", with: "\n")

        do {
            var options = AttributedString.MarkdownParsingOptions()
            options.interpretedSyntax = .full
            options.failurePolicy = .returnPartiallyParsedIfPossible

            var attributed = try AttributedString(markdown: normalized, options: options)

            let para = NSMutableParagraphStyle()
            para.lineBreakMode = .byWordWrapping
            para.lineSpacing = lineSpacing
            para.paragraphSpacing = paragraphSpacing

            var container = AttributeContainer()
            container.paragraphStyle = para
            attributed.mergeAttributes(container)

            return attributed
        } catch {
            return formatParagraphs(normalized, lineSpacing: lineSpacing, paragraphSpacing: paragraphSpacing)
        }
    }
}

// MARK: - UIKit convenience
public enum SummaryFormatterUIKit {
    /// Builds an NSAttributedString with paragraph/line spacing for UILabel/UITextView.
    public static func makeMarkdownAttributedText(_ raw: String,
                                                  font: UIFont = .preferredFont(forTextStyle: .body),
                                                  lineSpacing: CGFloat = 2,
                                                  paragraphSpacing: CGFloat = 6) -> NSAttributedString {
        let normalized = raw
            .replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\r\n", with: "\n")

        do {
            var options = AttributedString.MarkdownParsingOptions()
            options.interpretedSyntax = .full
            options.failurePolicy = .returnPartiallyParsedIfPossible

            let swiftAttributed = try AttributedString(markdown: normalized, options: options)
            let mutable = NSMutableAttributedString(attributedString: NSAttributedString(swiftAttributed))

            let fullRange = NSRange(location: 0, length: mutable.length)
            mutable.addAttribute(.font, value: font, range: fullRange)

            let para = NSMutableParagraphStyle()
            para.lineBreakMode = .byWordWrapping
            para.lineSpacing = lineSpacing
            para.paragraphSpacing = paragraphSpacing
            mutable.addAttribute(.paragraphStyle, value: para, range: fullRange)

            return mutable
        } catch {
            let para = NSMutableParagraphStyle()
            para.lineBreakMode = .byWordWrapping
            para.lineSpacing = lineSpacing
            para.paragraphSpacing = paragraphSpacing
            return NSAttributedString(string: normalized, attributes: [.font: font, .paragraphStyle: para])
        }
    }
}
