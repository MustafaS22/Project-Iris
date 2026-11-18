import Foundation
import AppKit
import Carbon
import Combine

enum IrisShortcutAction: String, CaseIterable, Codable, Identifiable {
    case notch, floatingVoice, floatingText, dismiss
    var id: String { rawValue }
    var title: String { switch self { case .notch: "Open the notch"; case .floatingVoice: "Ask floating Iris"; case .floatingText: "Type to floating Iris"; case .dismiss: "Go back or collapse" } }
    var detail: String { switch self { case .notch: "Start listening if Listen when summoned is enabled."; case .floatingVoice: "Show floating Iris and start speaking."; case .floatingText: "Open the small typing bar; Iris answers aloud."; case .dismiss: "Go back in the notch or dismiss floating text input. Only active inside Iris." } }
    var global: Bool { self != .dismiss }
    var eventID: UInt32 { switch self { case .notch: 1; case .floatingVoice: 2; case .floatingText: 3; case .dismiss: 4 } }
    var defaultChord: IrisKeyChord {
        switch self {
        case .notch: .init(keyCode: UInt32(kVK_Space), modifiers: UInt32(controlKey | optionKey), keyName: "Space")
        case .floatingVoice: .init(keyCode: UInt32(kVK_ANSI_F), modifiers: UInt32(controlKey | optionKey), keyName: "F")
        case .floatingText: .init(keyCode: UInt32(kVK_ANSI_T), modifiers: UInt32(controlKey | optionKey), keyName: "T")
        case .dismiss: .init(keyCode: UInt32(kVK_Escape), modifiers: 0, keyName: "Esc")
        }
    }
}

struct IrisKeyChord: Codable, Equatable {
    let keyCode: UInt32
    let modifiers: UInt32
    let keyName: String
    static let modifierMask = UInt32(cmdKey | shiftKey | optionKey | controlKey)
    var display: String {
        let flags: [(UInt32,String)] = [(UInt32(controlKey),"⌃"),(UInt32(optionKey),"⌥"),(UInt32(shiftKey),"⇧"),(UInt32(cmdKey),"⌘")]
        return (flags.compactMap { modifiers & $0.0 != 0 ? $0.1 : nil } + [keyName]).joined(separator: " ")
    }
    func sameKeys(as other: Self) -> Bool { keyCode == other.keyCode && modifiers == other.modifiers }
    static func carbonFlags(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var result: UInt32 = 0
        if flags.contains(.command) { result |= UInt32(cmdKey) }
        if flags.contains(.control) { result |= UInt32(controlKey) }
        if flags.contains(.option) { result |= UInt32(optionKey) }
        if flags.contains(.shift) { result |= UInt32(shiftKey) }
        return result
    }
    init(keyCode: UInt32, modifiers: UInt32, keyName: String) { self.keyCode = keyCode; self.modifiers = modifiers; self.keyName = keyName }
    init(event: NSEvent) {
        keyCode = UInt32(event.keyCode); modifiers = Self.carbonFlags(event.modifierFlags)
        let special: [UInt16:String] = [49:"Space",53:"Esc",36:"Return",48:"Tab",51:"Delete",117:"Forward Delete",123:"←",124:"→",125:"↓",126:"↑",115:"Home",119:"End",116:"Page Up",121:"Page Down",76:"Enter",122:"F1",120:"F2",99:"F3",118:"F4",96:"F5",97:"F6",98:"F7",100:"F8",101:"F9",109:"F10",103:"F11",111:"F12",105:"F13",107:"F14",113:"F15"]
        keyName = special[event.keyCode] ?? event.charactersIgnoringModifiers?.uppercased().filter { !$0.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) }.nonempty ?? "Key \(event.keyCode)"
    }
}
private extension String { var nonempty: String? { isEmpty ? nil : self } }

struct IrisShortcutError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

@MainActor
final class IrisShortcutStore: ObservableObject {
    @Published private(set) var bindings: [IrisShortcutAction:IrisKeyChord]
    @Published private(set) var isRecording = false
    @Published private(set) var registrationIssues: [IrisShortcutAction:String] = [:]
    private struct Saved: Codable { var values: [String:IrisKeyChord]; var disabled: [String] }
    private let defaults: UserDefaults
    private let storageKey: String
    private var references: [IrisShortcutAction:EventHotKeyRef] = [:]
    private var handler: EventHandlerRef?
    private var activated = false
    private var actionHandler: ((IrisShortcutAction) -> Void)?
    // Allows conflict/rollback tests without touching the user's global shortcuts.
    private let registrationCheck: ((IrisShortcutAction,IrisKeyChord) -> Bool)?
    init(defaults: UserDefaults = .standard, storageKey: String = "IrisCustomShortcuts.v1", registrationCheck: ((IrisShortcutAction,IrisKeyChord)->Bool)? = nil) {
        self.defaults = defaults; self.storageKey = storageKey; self.registrationCheck = registrationCheck
        var values = Dictionary(uniqueKeysWithValues: IrisShortcutAction.allCases.map { ($0,$0.defaultChord) })
        if let data = defaults.data(forKey: storageKey), let saved = try? JSONDecoder().decode(Saved.self, from: data) {
            for action in IrisShortcutAction.allCases {
                if saved.disabled.contains(action.rawValue) { values[action] = nil }
                else if let chord = saved.values[action.rawValue], (try? Self.validate(chord, for: action, among: [:])) != nil { values[action] = chord }
            }
            var seen: [IrisKeyChord] = []
            for action in IrisShortcutAction.allCases { if let chord = values[action] { if seen.contains(where: { $0.sameKeys(as: chord) }) { values[action] = nil } else { seen.append(chord) } } }
        }
        bindings = values
    }
    func label(_ action: IrisShortcutAction) -> String { bindings[action]?.display ?? "Not set" }
    static func validate(_ chord: IrisKeyChord, for action: IrisShortcutAction, among bindings: [IrisShortcutAction:IrisKeyChord]) throws {
        guard chord.keyCode < 128, !chord.keyName.isEmpty, chord.modifiers & ~IrisKeyChord.modifierMask == 0 else { throw IrisShortcutError(message: "Choose a standard key with Command, Control, Option or Shift.") }
        let modifierKeys: Set<UInt32> = [54,55,56,57,58,59,60,61,62,63]
        guard !modifierKeys.contains(chord.keyCode) else { throw IrisShortcutError(message: "Add a key to the modifiers.") }
        if action.global && chord.modifiers & UInt32(cmdKey | controlKey | optionKey) == 0 { throw IrisShortcutError(message: "Global shortcuts need Command, Control or Option so normal typing keeps working.") }
        if let other = bindings.first(where: { $0.key != action && $0.value.sameKeys(as: chord) }) { throw IrisShortcutError(message: "That shortcut is already used for “\(other.key.title)”.") }
    }
    func activate(handler action: @escaping (IrisShortcutAction)->Void) {
        guard !activated else { return }; actionHandler = action
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, pointer in
            guard let event, let pointer else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            guard GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id) == noErr else { return OSStatus(eventNotHandledErr) }
            let store = Unmanaged<IrisShortcutStore>.fromOpaque(pointer).takeUnretainedValue()
            let eventID = id.id
            Task { @MainActor in
                guard !store.isRecording, let action = IrisShortcutAction.allCases.first(where: { $0.global && $0.eventID == eventID }) else { return }
                store.actionHandler?(action)
            }
            return noErr
        }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard status == noErr else { registrationIssues[.notch] = "Global shortcuts are unavailable. You can still open Iris from the menu bar."; return }
        activated = true; registerCurrent()
    }
    private func install(_ chord: IrisKeyChord, for action: IrisShortcutAction) throws {
        if let registrationCheck, !registrationCheck(action,chord) { throw IrisShortcutError(message: "That shortcut is in use by macOS or another app. Try a different combination.") }
        guard activated, action.global else { return }
        var ref: EventHotKeyRef?
        let result = RegisterEventHotKey(chord.keyCode,chord.modifiers,EventHotKeyID(signature: OSType(0x49524953),id: action.eventID),GetApplicationEventTarget(),0,&ref)
        guard result == noErr, let ref else { throw IrisShortcutError(message: "That shortcut is in use by macOS or another app. Try a different combination.") }
        if let old = references.removeValue(forKey: action) { UnregisterEventHotKey(old) }
        references[action] = ref
    }
    private func unregisterAll() { for ref in references.values { UnregisterEventHotKey(ref) }; references.removeAll() }
    private func registerCurrent() {
        guard activated else { return }; registrationIssues = [:]
        for action in IrisShortcutAction.allCases where action.global {
            guard let chord = bindings[action] else { continue }
            do { try install(chord,for:action) } catch { registrationIssues[action] = error.localizedDescription }
        }
    }
    func beginRecording() { isRecording = true; unregisterAll() }
    func endRecording() { guard isRecording else { return }; isRecording = false; registerCurrent() }
    func set(_ chord: IrisKeyChord?, for action: IrisShortcutAction) throws {
        if let chord { try Self.validate(chord,for:action,among:bindings) }
        let recording = isRecording
        if recording { endRecording() }
        do {
            if let chord {
                if bindings[action]?.sameKeys(as: chord) != true || (activated && action.global && references[action] == nil) { try install(chord,for:action) }
                bindings[action] = chord
            } else { if let ref = references.removeValue(forKey: action) { UnregisterEventHotKey(ref) }; bindings[action] = nil }
            registrationIssues[action] = nil
            persist()
        } catch { if recording { beginRecording() }; throw error }
    }
    func restoreDefaults() throws {
        let previous = bindings
        unregisterAll(); bindings = Dictionary(uniqueKeysWithValues: IrisShortcutAction.allCases.map { ($0,$0.defaultChord) })
        do {
            for action in IrisShortcutAction.allCases where action.global { try install(action.defaultChord,for:action) }
            registrationIssues = [:]; persist()
        } catch { unregisterAll(); bindings = previous; registerCurrent(); throw error }
    }
    private func persist() {
        let saved = Saved(values: Dictionary(uniqueKeysWithValues:bindings.map { ($0.key.rawValue,$0.value) }),disabled:IrisShortcutAction.allCases.filter { bindings[$0] == nil }.map(\.rawValue))
        if let data = try? JSONEncoder().encode(saved) { defaults.set(data,forKey:storageKey) }
    }
    func matchesDismiss(_ event: NSEvent) -> Bool { !isRecording && !event.isARepeat && bindings[.dismiss]?.sameKeys(as:IrisKeyChord(event:event)) == true }
    func shutdown() { unregisterAll(); if let handler { RemoveEventHandler(handler) }; handler = nil; activated = false; actionHandler = nil }
}
