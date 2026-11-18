import SwiftUI
import AppKit

/// Plain-text editing with display-only mention styling. No hidden tokens or rich-text paste.
struct MentionTextEditor: NSViewRepresentable {
    enum Command { case submit, up, down, escape }
    @Binding var text: String
    @Binding var focused: Bool
    let accent: Color
    var compact: Bool
    var onCommand: (Command) -> Bool
    var onFiles: (([URL]) -> Bool)? = nil
    var onData: ((Data,String) -> Bool)? = nil
    var onAttachmentError: ((String) -> Void)? = nil
    private var font: NSFont { .systemFont(ofSize: compact ? 14 : 15) }

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false; scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        scroll.horizontalScrollElasticity = .none; scroll.verticalScrollElasticity = .none
        let storage = NSTextStorage()
        let layout = MentionLayoutManager()
        let container = NSTextContainer(containerSize: NSSize(width: 400, height: CGFloat.greatestFiniteMagnitude))
        storage.addLayoutManager(layout); layout.addTextContainer(container)
        let view = Editor(frame: .init(x: 0, y: 0, width: 400, height: 26), textContainer: container)
        view.isRichText = false; view.importsGraphics = false; view.allowsUndo = true
        view.drawsBackground = false; view.isVerticallyResizable = true; view.isHorizontallyResizable = false
        view.autoresizingMask = [.width]; view.textContainer?.widthTracksTextView = true
        view.textContainer?.lineFragmentPadding = 4; view.textContainerInset = .init(width: 0, height: 3)
        view.font = font; view.insertionPointColor = NSColor(accent)
        view.delegate = context.coordinator
        view.onFiles={urls in context.coordinator.parent.onFiles?(urls) ?? false}
        view.onData={data,ext in context.coordinator.parent.onData?(data,ext) ?? false}
        view.onAttachmentError={text in context.coordinator.parent.onAttachmentError?(text)}
        view.registerForDraggedTypes(ComposerPasteboard.types + NSFilePromiseReceiver.readableDraggedTypes.map{NSPasteboard.PasteboardType($0)} + [.string])
        view.setAccessibilityLabel("Message Iris. Type at to choose a source or creation tool.")
        view.focusChanged = { value in
            context.coordinator.parent.focused = value
        }
        scroll.documentView = view; return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let view = scroll.documentView as? Editor else { return }
        // Let input methods finish composing before applying an external draft update.
        if view.string != text && !view.hasMarkedText() {
            let selections = view.selectedRanges
            view.string = text
            view.selectedRanges = selections.map { value in
                let range = value.rangeValue, length = (text as NSString).length
                return NSValue(range: NSRange(location: min(range.location, length), length: min(range.length, max(0, length - range.location))))
            }
        }
        context.coordinator.style(view)
        if focused && view.window?.firstResponder !== view {
            DispatchQueue.main.async { [weak view] in
                guard let view, context.coordinator.parent.focused else { return }
                view.window?.makeFirstResponder(view)
            }
        }
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSScrollView, context: Context) -> CGSize? {
        let width = proposal.width ?? 400
        let line = ceil(font.ascender - font.descender + font.leading) + 2
        let measured = (text.isEmpty ? " " : text + "\u{200B}") as NSString
        let height = measured.boundingRect(with: .init(width: max(40, width - 12), height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: font]).height
        return .init(width: width, height: min(line * CGFloat(compact ? 3 : 5) + 6, max(line + 6, ceil(height) + 6)))
    }
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MentionTextEditor
        init(_ parent: MentionTextEditor) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? Editor else { return }
            parent.text = view.string
            if !view.hasMarkedText() { style(view) }
            view.needsDisplay = true
        }
        func style(_ view: Editor) {
            guard !view.hasMarkedText(), let storage = view.textStorage else { return }
            let font = parent.font, color = NSColor(parent.accent)
            let plain: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.labelColor]
            storage.beginEditing()
            storage.setAttributes(plain, range: NSRange(location: 0, length: storage.length))
            for range in ChatMentions.highlightedRanges(in: view.string) {
                storage.addAttributes([.font: NSFont.systemFont(ofSize: font.pointSize, weight: .medium), .foregroundColor: color, .irisMentionTint: color], range: range)
            }
            storage.endEditing()
            view.typingAttributes = plain
            view.insertionPointColor = color
            view.needsDisplay = true
        }
        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.insertNewline(_:)):
                guard NSEvent.modifierFlags.intersection([.shift, .option]).isEmpty else { return false }
                return parent.onCommand(.submit)
            case #selector(NSResponder.moveUp(_:)): return parent.onCommand(.up)
            case #selector(NSResponder.moveDown(_:)): return parent.onCommand(.down)
            case #selector(NSResponder.cancelOperation(_:)): return parent.onCommand(.escape)
            default: return false
            }
        }
    }
    final class Editor: NSTextView {
        var onFiles:(([URL])->Bool)?
        var onData:((Data,String)->Bool)?
        var onAttachmentError:((String)->Void)?
        @discardableResult func insertAttachments(from board:NSPasteboard)->Bool {
            guard let payload=ComposerPasteboard.read(board) else{return false}
            switch payload {
            case .files(let urls):return onFiles?(urls) ?? false
            case .data(let data,let ext):return onData?(data,ext) ?? false
            }
        }
        override func paste(_ sender:Any?) {
            if ComposerPasteboard.accepts(.general) {
                if !insertAttachments(from:.general){onAttachmentError?("Couldn't add that attachment. Finish the current message and try again.")}
            } else {super.paste(sender)}
        }
        override func validateUserInterfaceItem(_ item:NSValidatedUserInterfaceItem)->Bool {
            if item.action == #selector(paste(_:)),ComposerPasteboard.accepts(.general){return true}
            return super.validateUserInterfaceItem(item)
        }
        override func draggingEntered(_ sender:NSDraggingInfo)->NSDragOperation {
            ComposerPasteboard.accepts(sender.draggingPasteboard) ? .copy : super.draggingEntered(sender)
        }
        override func draggingUpdated(_ sender:NSDraggingInfo)->NSDragOperation {
            ComposerPasteboard.accepts(sender.draggingPasteboard) ? .copy : super.draggingUpdated(sender)
        }
        override func prepareForDragOperation(_ sender:NSDraggingInfo)->Bool {
            ComposerPasteboard.accepts(sender.draggingPasteboard) || super.prepareForDragOperation(sender)
        }
        override func performDragOperation(_ sender:NSDraggingInfo)->Bool {
            let board=sender.draggingPasteboard
            if insertAttachments(from:board){return true}
            if let receivers=board.readObjects(forClasses:[NSFilePromiseReceiver.self],options:nil) as? [NSFilePromiseReceiver],!receivers.isEmpty {
                let count=receivers.reduce(0){$0+max(1,$1.fileNames.count)}
                guard count<=6 else{onAttachmentError?("Drop up to six files at a time.");return false}
                do {
                    let destination=try ComposerPasteboard.directory()
                    var remaining=count,urls:[URL]=[],errors:[String]=[]
                    for receiver in receivers {
                        receiver.receivePromisedFiles(atDestination:destination,options:[:],operationQueue:.main){[weak self] url,error in
                            if let error {errors.append(error.localizedDescription)}else{urls.append(url)}
                            remaining -= 1
                            if remaining==0 {
                                if !urls.isEmpty { _=self?.onFiles?(urls) }
                                if !errors.isEmpty {self?.onAttachmentError?(errors.joined(separator:"\n"))}
                            }
                        }
                    }
                    return true
                } catch {onAttachmentError?(error.localizedDescription);return false}
            }
            if ComposerPasteboard.accepts(board){onAttachmentError?("Couldn't attach this item. Try copying the image or dropping its file from Finder.");return false}
            return super.performDragOperation(sender)
        }
        var focusChanged: ((Bool) -> Void)?
        override func becomeFirstResponder() -> Bool { let result = super.becomeFirstResponder(); if result { focusChanged?(true) }; return result }
        override func resignFirstResponder() -> Bool { let result = super.resignFirstResponder(); if result { focusChanged?(false) }; return result }
        override func draw(_ dirtyRect: NSRect) {
            super.draw(dirtyRect)
            if string.isEmpty {
                ("Message Iris, or @ a source or tool…" as NSString).draw(at: .init(x: 4, y: 3), withAttributes: [.font: font ?? NSFont.systemFont(ofSize: 15), .foregroundColor: NSColor.placeholderTextColor])
            }
        }
    }
}

private extension NSAttributedString.Key {
    static let irisMentionTint = NSAttributedString.Key("IrisMentionTint")
}

/// Draws per-line rounded chips behind the glyphs without changing the editable string.
private final class MentionLayoutManager: NSLayoutManager {
    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        if let storage = textStorage, let container = textContainers.first {
            let characters = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
            storage.enumerateAttribute(.irisMentionTint, in: characters) { value, range, _ in
                guard let tint = value as? NSColor else { return }
                let glyphs = self.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
                self.enumerateEnclosingRects(forGlyphRange: glyphs, withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0), in: container) { rect, _ in
                    let box = rect.offsetBy(dx: origin.x, dy: origin.y).insetBy(dx: -1.5, dy: 0.5)
                    let path = NSBezierPath(roundedRect: box, xRadius: 5, yRadius: 5)
                    NSGradient(starting: tint.withAlphaComponent(0.18), ending: tint.withAlphaComponent(0.09))?.draw(in: path, angle: -90)
                    tint.withAlphaComponent(0.28).setStroke(); path.lineWidth = 0.65; path.stroke()
                }
            }
        }
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
    }
}
