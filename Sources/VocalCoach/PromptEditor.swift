import AppKit
import SwiftUI

struct PromptEditor: NSViewRepresentable {
    @Binding var text: String
    let isEditable: Bool
    let reference: VoiceContour.Traces
    let recording: VoiceContour.Traces
    let focusWords: Set<Int>
    let selection: Int?
    let onWord: (Int) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true

        let manager = NSLayoutManager()
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        context.coordinator.storage.addLayoutManager(manager)
        manager.addTextContainer(container)
        container.widthTracksTextView = true
        container.lineFragmentPadding = 0

        let editor = PracticeTextView(frame: scroll.bounds, textContainer: container)
        editor.delegate = context.coordinator
        editor.autoresizingMask = [.width]
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = false
        editor.isRichText = false
        editor.drawsBackground = false
        editor.allowsUndo = true
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.textContainerInset = NSSize(width: 24, height: 32)
        editor.setAccessibilityLabel("Practice prompt")
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 30
        editor.defaultParagraphStyle = style
        editor.font = .systemFont(ofSize: 49, weight: .medium)
        editor.textColor = .labelColor
        scroll.documentView = editor
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let editor = scroll.documentView as? PracticeTextView else { return }
        if editor.string != text {
            editor.string = text
            editor.setSelectedRange(NSRange(location: 0, length: 0))
        }
        editor.isEditable = isEditable
        if editor.reference != reference || editor.recording != recording || editor.focusWords != focusWords
            || editor.focusedWord != selection {
            editor.reference = reference
            editor.recording = recording
            editor.focusWords = focusWords
            editor.focusedWord = selection
            editor.needsDisplay = true
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: PromptEditor
        let storage = NSTextStorage()

        init(_ parent: PromptEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let editor = notification.object as? NSTextView else { return }
            parent.text = editor.string
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let editor = notification.object as? PracticeTextView, !editor.reference.isEmpty,
                  editor.selectedRange().length == 0 else { return }
            let location = editor.selectedRange().location
            let string = editor.string
            let words = PracticeSentence.words(in: string)
            if let index = words.firstIndex(where: {
                let range = NSRange($0.range, in: string)
                return location >= range.location && location <= NSMaxRange(range)
            }) {
                parent.onWord(index)
            }
        }
    }
}

private final class PracticeTextView: NSTextView {
    var focusedWord: Int?

    var reference: VoiceContour.Traces = [:]
    var recording: VoiceContour.Traces = [:]
    var focusWords: Set<Int> = []

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard !reference.isEmpty || !recording.isEmpty,
              let manager = layoutManager, let container = textContainer else { return }
        let string = string
        let origin = textContainerOrigin
        manager.ensureLayout(for: container)
        for (index, word) in PracticeSentence.words(in: string).enumerated() {
            let glyphs = manager.glyphRange(forCharacterRange: NSRange(word.range, in: string), actualCharacterRange: nil)
            guard glyphs.length > 0 else { continue }
            manager.enumerateLineFragments(forGlyphRange: glyphs) { line, _, _, lineGlyphs, _ in
                let portion = NSIntersectionRange(glyphs, lineGlyphs)
                let bounds = manager.boundingRect(forGlyphRange: portion, in: container)
                let baseline = origin.y + line.minY + manager.location(forGlyphAt: portion.location).y
                let cap = self.font?.capHeight ?? 35
                let band = NSRect(x: origin.x + bounds.minX, y: baseline - cap - 21,
                                  width: max(1, bounds.width), height: 30)
                let lineY = baseline + 6
                guard dirtyRect.intersects(band.union(NSRect(x: band.minX, y: lineY, width: band.width, height: 3))) else { return }
                let start = Double(portion.location - glyphs.location) / Double(glyphs.length)
                let end = Double(NSMaxRange(portion) - glyphs.location) / Double(glyphs.length)
                self.drawTrace(self.reference[index], in: band, start: start, end: end, color: .systemTeal, baseWidth: 2.5)
                self.drawTrace(self.recording[index], in: band, start: start, end: end, color: .systemPurple, baseWidth: 1.1)
                if self.focusWords.contains(index) || self.focusedWord == index {
                    let focus = self.focusWords.contains(index)
                    (focus ? NSColor.systemOrange : .tertiaryLabelColor).setFill()
                    NSBezierPath(roundedRect: NSRect(x: band.minX, y: lineY, width: band.width, height: 2),
                                 xRadius: 1, yRadius: 1).fill()
                }
            }
        }
    }

    private func drawTrace(_ points: [ContourPoint]?, in band: NSRect, start: Double, end: Double, color: NSColor, baseWidth: CGFloat) {
        guard let points, end > start else { return }
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSBezierPath(rect: band.insetBy(dx: 0, dy: -3)).addClip()
        color.set()
        var previous: NSPoint?
        for point in points {
            guard let pitch = point.semitones else { previous = nil; continue }
            let x = band.minX + band.width * (point.position - start) / (end - start)
            let y = band.midY - band.height * CGFloat(min(9, max(-9, pitch))) / 18
            let next = NSPoint(x: x, y: y)
            let width = baseWidth + 2.6 * CGFloat(point.emphasis)
            if let previous {
                let stroke = NSBezierPath()
                stroke.move(to: previous)
                stroke.line(to: next)
                stroke.lineWidth = width
                stroke.lineCapStyle = .round
                stroke.stroke()
            } else {
                NSBezierPath(ovalIn: NSRect(x: x - width/2, y: y - width/2, width: width, height: width)).fill()
            }
            previous = next
        }
    }
}
