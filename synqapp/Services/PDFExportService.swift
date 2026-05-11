
//  PDFExportService.swift
//  Spill — exports a journal entry to PDF

import AppKit

final class PDFExportService {

    static func export(entry: JournalEntry, to url: URL, fontName: String, fontSize: CGFloat) {
        let pageSize = CGSize(width: 612, height: 792) // US Letter
        let margin: CGFloat = 72
        let lineHeight: CGFloat = fontSize + 4.0

        let font = NSFont(name: fontName, size: fontSize) ?? NSFont.systemFont(ofSize: fontSize)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.black
        ]

        let text = entry.body
        let lines = text.components(separatedBy: .newlines)

        let pdfData = NSMutableData()
        guard let consumer = CGDataConsumer(data: pdfData as CFMutableData) else { return }

        var mediaBox = CGRect(origin: .zero, size: pageSize)
        guard let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return }

        let nsCtx = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nsCtx

        ctx.beginPDFPage(nil)

        var y = pageSize.height - margin
        let maxWidth = pageSize.width - margin * 2

        for line in lines {
            let str = NSAttributedString(string: line.isEmpty ? " " : line, attributes: attrs)
            let framesetter = CTFramesetterCreateWithAttributedString(str)
            let path = CGPath(rect: CGRect(x: margin, y: y - lineHeight, width: maxWidth, height: lineHeight), transform: nil)
            let frame = CTFramesetterCreateFrame(framesetter, CFRangeMake(0, 0), path, nil)
            CTFrameDraw(frame, ctx)
            y -= lineHeight
            if y < margin {
                ctx.endPDFPage()
                ctx.beginPDFPage(nil)
                y = pageSize.height - margin
            }
        }

        ctx.endPDFPage()
        ctx.closePDF()

        NSGraphicsContext.restoreGraphicsState()

        pdfData.write(to: url, atomically: true)
    }
}
