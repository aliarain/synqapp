//  PDFExportService.swift
//  SynqApp — exports a journal entry to a paginated PDF

import AppKit
import CoreText
import SynqCore

enum PDFExportService {

    /// Lays the whole entry out with Core Text, wrapping long paragraphs and flowing onto as many
    /// US Letter pages as needed. (Laying out one line box per paragraph silently dropped any
    /// paragraph longer than a single line.)
    static func export(entry: JournalEntry, to url: URL, font: NSFont) throws {
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)
        let textRect = pageRect.insetBy(dx: 72, dy: 72)

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = font.pointSize * 0.3
        paragraph.paragraphSpacing = font.pointSize * 0.5
        let text = NSAttributedString(string: entry.content, attributes: [
            .font: font,
            .foregroundColor: NSColor.black,
            .paragraphStyle: paragraph,
        ])

        let data = NSMutableData()
        var mediaBox = pageRect
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox, nil)
        else { throw CocoaError(.fileWriteUnknown) }

        let framesetter = CTFramesetterCreateWithAttributedString(text)
        var location = 0
        repeat {
            ctx.beginPDFPage(nil)
            let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: location, length: 0), CGPath(rect: textRect, transform: nil), nil)
            CTFrameDraw(frame, ctx)
            ctx.endPDFPage()
            let visible = CTFrameGetVisibleStringRange(frame)
            guard visible.length > 0 else { break }
            location += visible.length
        } while location < text.length
        ctx.closePDF()

        try (data as Data).write(to: url, options: .atomic)
    }
}
