import AppKit
import ApplicationServices
import Carbon

@MainActor struct InlineDraftTarget {
    let app: NSRunningApplication
    let element: AXUIElement
    let role: String
    let range: CFRange
    let selectionExposed: Bool
    let original: String?
    let selected: String
    let fieldLabel: String
    let caret: CGPoint

    nonisolated private static let excluded = ["1password", "bitwarden", "keychain", "keepass", "dashlane", "wallet",
                                   "authenticator", "protonpass", "lastpass", "terminal", "iterm", "warp"]
    nonisolated private static let sensitive = ["password", "passcode", "verification code", "one-time code", "credit card",
                                    "security code", "social security", "card number", "bank account", "recovery phrase", "api key", "address and search", "address bar", "url bar", "omnibox"]
    nonisolated private static let stringAttributes = [kAXIdentifierAttribute, kAXTitleAttribute, kAXDescriptionAttribute, kAXHelpAttribute, "AXPlaceholderValue"]

    private static var accessibilityEnabled: [pid_t: TimeInterval] = [:]
    static private(set) var lastFailure = "Select an editable text field"
    static func focused() -> InlineDraftTarget? {
        lastFailure = "Select an editable text field"
        guard AXIsProcessTrusted() else { lastFailure = "Accessibility access is unavailable for this Iris build"; return nil }
        guard !IsSecureEventInputEnabled() else { lastFailure = "macOS Secure Input is active · finish password entry and retry"; return nil }
        guard let app = NSWorkspace.shared.frontmostApplication, let id = app.bundleIdentifier?.lowercased(),
              id != Bundle.main.bundleIdentifier?.lowercased() else { lastFailure = "Focus a text field in the app you want to write in"; return nil }
        guard !excluded.contains(where: { id.contains($0) }) else { lastFailure = "Double Tap is unavailable in this protected app"; return nil }
        guard let field = focusedElement(app) else { lastFailure = "Couldn’t read the focused field · try clicking inside it again"; return nil }
        guard !protectedTree(field) else { lastFailure = "This field is protected"; return nil }
        guard let role = value(field, kAXRoleAttribute) as? String,
              [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole].contains(role) || (value(field, "AXEditable") as? Bool == true),
              value(field, kAXEnabledAttribute) as? Bool != false,
              value(field, "AXReadOnly") as? Bool != true else { return nil }
        let original = fieldText(field)
        guard let capture = InlineDraftSelection.capture(original: original, range: selection(field), selected: stringValue(field, kAXSelectedTextAttribute)) else {
            lastFailure = "This editor isn’t exposing its caret · select some text and retry"
            return nil
        }
        let range = capture.range
        let selected = stringValue(field, kAXSelectedTextAttribute).flatMap { $0.isEmpty ? nil : $0 }
            ?? original.flatMap { text in valid(range, in: text) ? (text as NSString).substring(with: NSRange(location: range.location, length: range.length)) : nil }
            ?? ""
        if range.length > 0 && selected.isEmpty { return nil }
        return .init(app: app, element: field, role: role, range: range, selectionExposed: capture.exposed, original: original,
                     selected: selected, fieldLabel: label(field), caret: caretPosition(field, range: range))
    }

    func isStillFocused() -> Bool {
        guard AXIsProcessTrusted(), !IsSecureEventInputEnabled(), !app.isTerminated, NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier,
              let current = Self.focusedElement(app), CFEqual(current, element),
              !Self.protectedTree(current),
              Self.fieldText(current) == original else { return false }
        if let live = Self.selection(current) {
            guard live.location == range.location, live.length == range.length else { return false }
        } else if selectionExposed { return false }
        if range.length > 0 {
            let liveSelection = Self.stringValue(current, kAXSelectedTextAttribute).flatMap { $0.isEmpty ? nil : $0 } ?? original.flatMap { Self.valid(range, in: $0) ? ($0 as NSString).substring(with: NSRange(location: range.location, length: range.length)) : nil }
            return liveSelection == selected
        }
        return true
    }

    func insert(_ draft: String) async -> Bool {
        guard isStillFocused() else { return false }
        let text = [kAXTextFieldRole, kAXComboBoxRole].contains(role) ? draft.split(whereSeparator: \.isNewline).joined(separator: " ") : draft
        guard !text.isEmpty else { return false }
        let expected = original.flatMap { value in
            Self.valid(range, in: value)
                ? (value as NSString).replacingCharacters(in: NSRange(location: range.location, length: range.length), with: text)
                : nil
        }
        if let expected, expected == original { return true }

        // Browser contenteditable controls often claim to support AX setters but ignore them.
        // Use one verified paste first there, never a second insertion after an unverified paste.
        let appID = app.bundleIdentifier?.lowercased() ?? ""
        if ["safari", "chrome", "chromium", "brave", "edge", "arc", "firefox", "electron", "slack", "discord", "vscode"].contains(where: appID.contains) {
            let outcome = await paste(text, expected: expected)
            if outcome != .unavailable { return outcome == .verified }
        }

        // AX success only means the app accepted the event. Some editors silently
        // ignore setters, so verify against the live field before reporting success.
        if expected != nil, Self.writable(element, kAXSelectedTextAttribute),
           AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFString) == .success {
            if await verify(expected: expected) { return true }
            guard !Task.isCancelled, isStillFocused() else { return false }
        }
        if role == kAXTextFieldRole, let expected, Self.writable(element, kAXValueAttribute),
           AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, expected as CFString) == .success {
            if await verify(expected: expected) {
                var after = CFRange(location: range.location + text.utf16.count, length: 0)
                if let caret = AXValueCreate(.cfRange, &after),
                   let current = Self.focusedElement(app), CFEqual(current, element),
                   NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier {
                    _ = AXUIElementSetAttributeValue(current, kAXSelectedTextRangeAttribute as CFString, caret)
                }
                return true
            }
            guard !Task.isCancelled, isStillFocused() else { return false }
        }
        return await paste(text, expected: expected) == .verified
    }

    private func verify(expected: String?, attempts: Int = 6) async -> Bool {
        guard let expected else { return false }
        func normalize(_ text: String) -> String {
            text.replacingOccurrences(of: "\r\n", with: "\n").precomposedStringWithCanonicalMapping
        }
        let wanted = normalize(expected)
        for index in 0..<attempts {
            if index > 0 { try? await Task.sleep(for: .milliseconds(100)) }
            guard !Task.isCancelled, NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier,
                  let current = Self.focusedElement(app), CFEqual(current, element), !Self.protected(current) else { return false }
            if let value = Self.fieldText(current), InlineDraftSelection.matchesInserted(expected: wanted, actual: normalize(value)) { return true }
        }
        return false
    }

    // Editors that don't expose an AX text setter can still receive a single paste. Never send Return.
    private enum PasteOutcome { case unavailable, verified, unverified }
    private func paste(_ text: String, expected: String?) async -> PasteOutcome {
        guard let source = CGEventSource(stateID: .privateState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: UInt16(kVK_ANSI_V), keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: UInt16(kVK_ANSI_V), keyDown: false) else { return .unavailable }
        let board = NSPasteboard.general
        let before = board.changeCount
        var saved: [NSPasteboardItem] = []
        var size = 0
        for item in board.pasteboardItems ?? [] {
            let copy = NSPasteboardItem()
            for type in item.types {
                guard let data = item.data(forType: type) else { return .unavailable }
                size += data.count
                guard size <= 64_000_000, copy.setData(data, forType: type) else { return .unavailable }
            }
            saved.append(copy)
        }
        guard before == board.changeCount, !Task.isCancelled, isStillFocused() else { return .unavailable }
        board.clearContents()
        guard board.setString(text, forType: .string) else {
            if !saved.isEmpty { board.writeObjects(saved) }
            return .unavailable
        }
        let inserted = board.changeCount
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.postToPid(app.processIdentifier)
        up.postToPid(app.processIdentifier)
        let verified = await verify(expected: expected, attempts: 16)
        // Keep the draft on the clipboard until the editor has actually consumed it.
        // Never restore over a newer clipboard change made by the user.
        if !verified, !Task.isCancelled { try? await Task.sleep(for: .milliseconds(300)) }
        if board.changeCount == inserted {
            board.clearContents()
            if !saved.isEmpty { board.writeObjects(saved) }
        }
        return verified ? .verified : .unverified
    }

    func visibleContentBounds() -> CGRect? {
        var node = element
        for _ in 0..<18 {
            if Self.value(node, kAXRoleAttribute) as? String == "AXWebArea" { return Self.frame(node) }
            guard let parent = Self.value(node, kAXParentAttribute), CFGetTypeID(parent) == AXUIElementGetTypeID() else { break }
            node = parent as! AXUIElement
        }
        return nil
    }
    func nearbyText() async -> String {
        guard isStillFocused(), let screen = NSScreen.screens.first(where: { $0.frame.contains(caret) }),
              let window = Self.value(AXUIElementCreateApplication(app.processIdentifier), kAXFocusedWindowAttribute),
              CFGetTypeID(window) == AXUIElementGetTypeID() else { return "" }
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        let screenRect = CGRect(x: screen.frame.minX, y: top - screen.frame.maxY, width: screen.frame.width, height: screen.frame.height)
        let cursor = CGPoint(x: caret.x, y: top - caret.y)
        let vicinity = CGRect(x: cursor.x - 450, y: cursor.y - 430, width: 900, height: 560).intersection(screenRect)
        // Visit the field's immediate form/thread first, then the visible window.
        var roots: [AXUIElement] = []
        var ancestor = element
        for _ in 0..<3 {
            guard let parent = Self.value(ancestor, kAXParentAttribute), CFGetTypeID(parent) == AXUIElementGetTypeID() else { break }
            ancestor = parent as! AXUIElement
            roots.append(ancestor)
        }
        roots.append(window as! AXUIElement)
        let snapshot = ContextSnapshot(roots: roots, element: element, window: window as! AXUIElement, vicinity: vicinity)
        let reader = Task.detached(priority: .userInitiated) { Self.collectNearby(snapshot) }
        return await withTaskCancellationHandler { await reader.value } onCancel: { reader.cancel() }
    }
    private struct ContextSnapshot: @unchecked Sendable {
        let roots: [AXUIElement]
        let element: AXUIElement
        let window: AXUIElement
        let vicinity: CGRect
    }
    nonisolated private static func collectNearby(_ snapshot: ContextSnapshot) -> String {
        var pending: [(AXUIElement, Int)] = snapshot.roots.reversed().map { ($0, 0) }
        var visits = 0, total = 0, lines: [(CGRect, String)] = []
        var seen = Set<String>(), visited: [AXUIElement] = []
        let deadline = ProcessInfo.processInfo.systemUptime + 0.65
        while !Task.isCancelled, !pending.isEmpty, visits < 280, total < 4_000, ProcessInfo.processInfo.systemUptime < deadline {
            let (node, depth) = pending.removeLast(); visits += 1
            guard !visited.contains(where: { CFEqual($0, node) }) else { continue }
            visited.append(node)
            _ = AXUIElementSetMessagingTimeout(node, 0.025)
            if CFEqual(node, snapshot.element) || Self.protected(node) { continue }
            let role = Self.value(node, kAXRoleAttribute) as? String ?? ""
            let editable = role == kAXTextFieldRole || role == kAXTextAreaRole || role == kAXComboBoxRole
            if editable && Self.writable(node, kAXValueAttribute) { continue }
            let textRole = [kAXStaticTextRole, "AXHeading", "AXLink", kAXRadioButtonRole, kAXCheckBoxRole].contains(role)
            if textRole || editable {
                var rect = Self.frame(node)
                if rect == nil, let parent = Self.value(node, kAXParentAttribute), CFGetTypeID(parent) == AXUIElementGetTypeID() { rect = Self.frame(parent as! AXUIElement) }
                if let rect, rect.intersects(snapshot.vicinity),
                   let value = Self.stringValue(node, kAXValueAttribute) ?? Self.stringValue(node, kAXTitleAttribute) ?? Self.stringValue(node, kAXDescriptionAttribute) {
                    let line = String(value.prefix(min(700, 4000 - total))).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !line.isEmpty, seen.insert(line).inserted { lines.append((rect, line)); total += line.count + 1 }
                }
            }
            if depth < 18, pending.count < 600,
               let children = (Self.value(node, kAXVisibleChildrenAttribute) ?? Self.value(node, kAXChildrenAttribute)) as? [AXUIElement] {
                // Newer messages and the focused form's immediate siblings tend to be last.
                pending.append(contentsOf: children.suffix(70).map { ($0, depth + 1) })
            }
        }
        let title = String((Self.value(snapshot.window, kAXTitleAttribute) as? String ?? "").prefix(200))
        let excerpt = lines.sorted { Int($0.0.minY / 8) != Int($1.0.minY / 8) ? $0.0.minY < $1.0.minY : $0.0.minX < $1.0.minX }.map(\.1).joined(separator: "\n")
        return (title.isEmpty ? "" : "Window: " + title) + (excerpt.isEmpty ? "" : "\nVisible nearby text:\n" + excerpt)
    }

    private static func label(_ field: AXUIElement) -> String {
        if let raw = value(field, kAXTitleUIElementAttribute), CFGetTypeID(raw) == AXUIElementGetTypeID() {
            let label = raw as! AXUIElement
            if let text = stringValue(label, kAXValueAttribute) ?? stringValue(label, kAXTitleAttribute), !text.isEmpty {
                return String(text.prefix(300))
            }
        }
        for attribute in ["AXPlaceholderValue", kAXTitleAttribute, kAXDescriptionAttribute] {
            if let text = stringValue(field, attribute), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return String(text.prefix(300))
            }
        }
        return ""
    }

    private static func focusedElement(_ app: NSRunningApplication) -> AXUIElement? {
        let application = AXUIElementCreateApplication(app.processIdentifier)
        _ = AXUIElementSetMessagingTimeout(application, 0.12)
        // Chromium/Electron may not publish their editor tree until an AX client opts in.
        let now = ProcessInfo.processInfo.systemUptime
        if now - (accessibilityEnabled[app.processIdentifier] ?? -10) > 2 {
            accessibilityEnabled[app.processIdentifier] = now
            _ = AXUIElementSetAttributeValue(application, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        }
        let system = AXUIElementCreateSystemWide()
        _ = AXUIElementSetMessagingTimeout(system, 0.12)
        var roots: [AXUIElement] = []
        for source in [system, application] {
            if let raw = value(source, kAXFocusedUIElementAttribute), CFGetTypeID(raw) == AXUIElementGetTypeID() {
                let element = raw as! AXUIElement
                var pid: pid_t = 0
                if AXUIElementGetPid(element, &pid) == .success, pid == app.processIdentifier { roots.append(element) }
            }
        }
        let deadline = ProcessInfo.processInfo.systemUptime + 0.4
        for root in roots where ProcessInfo.processInfo.systemUptime < deadline {
            var node = root
            for _ in 0..<4 {
                guard ProcessInfo.processInfo.systemUptime < deadline else { break }
                _ = AXUIElementSetMessagingTimeout(node, 0.12)
                let role = value(node, kAXRoleAttribute) as? String ?? ""
                if [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole].contains(role) || value(node, "AXEditable") as? Bool == true { return node }
                guard let raw = value(node, kAXFocusedUIElementAttribute), CFGetTypeID(raw) == AXUIElementGetTypeID(), !CFEqual(raw, node) else { break }
                node = raw as! AXUIElement
            }
            // Only follow descendants explicitly marked focused, never a nearby arbitrary input.
            var pending = [root], index = 0
            while index < pending.count, index < 64, ProcessInfo.processInfo.systemUptime < deadline {
                let node = pending[index]; index += 1
                _ = AXUIElementSetMessagingTimeout(node, 0.035)
                let role = value(node, kAXRoleAttribute) as? String ?? ""
                if value(node, kAXFocusedAttribute) as? Bool == true,
                   [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole].contains(role) || value(node, "AXEditable") as? Bool == true { return node }
                if let children = value(node, kAXChildrenAttribute) as? [AXUIElement] { pending.append(contentsOf: children.prefix(12)) }
            }
        }
        return nil
    }
    private static func protectedTree(_ field: AXUIElement) -> Bool {
        var node = field
        for _ in 0..<4 {
            if protected(node) { return true }
            guard let raw = value(node, kAXParentAttribute), CFGetTypeID(raw) == AXUIElementGetTypeID() else { break }
            node = raw as! AXUIElement
        }
        return false
    }
    nonisolated private static func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var result: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, attribute as CFString, &result) == .success ? result : nil
    }
    nonisolated private static func stringValue(_ element: AXUIElement, _ attribute: String) -> String? {
        let content = value(element, attribute)
        return (content as? String) ?? (content as? NSAttributedString)?.string
    }
    private static func fieldText(_ element: AXUIElement) -> String? {
        let number = value(element, kAXNumberOfCharactersAttribute) as? NSNumber
        let count = number.flatMap { CFGetTypeID($0) != CFBooleanGetTypeID() && $0.intValue >= 0 && $0.intValue <= 64_000 ? $0.intValue : nil }
        if let text = InlineDraftSelection.exposedText(value: stringValue(element, kAXValueAttribute), placeholder: stringValue(element, "AXPlaceholderValue"), characterCount: count) { return text }
        guard let count else { return nil }
        var range = CFRange(location: 0, length: count)
        guard let parameter = AXValueCreate(.cfRange, &range) else { return nil }
        for attribute in [kAXStringForRangeParameterizedAttribute, kAXAttributedStringForRangeParameterizedAttribute] {
            var result: CFTypeRef?
            if AXUIElementCopyParameterizedAttributeValue(element, attribute as CFString, parameter, &result) == .success {
                if let text = result as? String { return text }
                if let text = result as? NSAttributedString { return text.string }
            }
        }
        return nil
    }
    nonisolated private static func protected(_ element: AXUIElement) -> Bool {
        if (value(element, kAXSubroleAttribute) as? String)?.localizedCaseInsensitiveContains("secure") == true ||
            (value(element, "AXProtectedContent") as? Bool) == true { return true }
        return stringAttributes.contains { attribute in
            guard let hint = value(element, attribute) as? String else { return false }
            return sensitive.contains { hint.localizedCaseInsensitiveContains($0) }
        }
    }
    private static func selection(_ element: AXUIElement) -> CFRange? {
        func decode(_ raw: CFTypeRef?) -> CFRange? {
            guard let raw, CFGetTypeID(raw) == AXValueGetTypeID() else { return nil }
            var range = CFRange()
            return AXValueGetValue(raw as! AXValue, .cfRange, &range) ? range : nil
        }
        if let range = decode(value(element, kAXSelectedTextRangeAttribute)) { return range }
        if let ranges = value(element, "AXSelectedTextRanges") as? [AXValue], let first = ranges.first, let range = decode(first) { return range }
        // WebKit exposes rich content-editable selections as text markers instead of CFRange.
        func parameter(_ name: String, _ input: CFTypeRef) -> CFTypeRef? {
            var result: CFTypeRef?
            return AXUIElementCopyParameterizedAttributeValue(element, name as CFString, input, &result) == .success ? result : nil
        }
        if let markers = value(element, "AXSelectedTextMarkerRange"),
           let start = parameter("AXStartTextMarkerForTextMarkerRange", markers),
           let end = parameter("AXEndTextMarkerForTextMarkerRange", markers),
           let a = parameter("AXIndexForTextMarker", start) as? NSNumber,
           let b = parameter("AXIndexForTextMarker", end) as? NSNumber, a.intValue >= 0, b.intValue >= a.intValue {
            return CFRange(location: a.intValue, length: b.intValue - a.intValue)
        }
        return nil
    }
    nonisolated private static func writable(_ element: AXUIElement, _ attribute: String) -> Bool {
        var answer = DarwinBoolean(false)
        return AXUIElementIsAttributeSettable(element, attribute as CFString, &answer) == .success && answer.boolValue
    }
    private static func valid(_ range: CFRange, in text: String) -> Bool {
        let count = text.utf16.count
        return range.location >= 0 && range.length >= 0 && range.location <= count && range.length <= count - range.location
    }
    nonisolated private static func frame(_ element: AXUIElement) -> CGRect? {
        guard let origin = value(element, kAXPositionAttribute), let size = value(element, kAXSizeAttribute),
              CFGetTypeID(origin) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var p = CGPoint.zero, s = CGSize.zero
        guard AXValueGetValue(origin as! AXValue, .cgPoint, &p), AXValueGetValue(size as! AXValue, .cgSize, &s) else { return nil }
        return CGRect(origin: p, size: s)
    }
    private static func caretPosition(_ element: AXUIElement, range: CFRange) -> CGPoint {
        var caretRange = CFRange(location: range.location, length: 0)
        var raw: CFTypeRef?, rect = CGRect.zero
        if let parameter = AXValueCreate(.cfRange, &caretRange),
           AXUIElementCopyParameterizedAttributeValue(element, kAXBoundsForRangeParameterizedAttribute as CFString, parameter, &raw) == .success,
           let raw, CFGetTypeID(raw) == AXValueGetTypeID(),
           AXValueGetValue(raw as! AXValue, .cgRect, &rect), rect.height > 0 {
            let p = CGPoint(x: rect.midX, y: (NSScreen.screens.first?.frame.maxY ?? 0) - rect.midY)
            if NSScreen.screens.contains(where: { $0.frame.contains(p) }) { return p }
        }
        if let bounds = frame(element), bounds.width > 0, bounds.height > 0 {
            return CGPoint(x: bounds.minX + min(40, bounds.width / 2), y: (NSScreen.screens.first?.frame.maxY ?? 0) - bounds.minY - min(16, bounds.height / 2))
        }
        return NSEvent.mouseLocation
    }
}
