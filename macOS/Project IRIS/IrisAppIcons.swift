import Combine

import AppKit
import SwiftUI

@MainActor
final class IrisAppIcons: ObservableObject {
    static let shared = IrisAppIcons()
    private static let key = "Iris.appIcon.v1"
    @Published private(set) var selection: IrisIconChoice?
    @Published private(set) var error: String?
    private var dockImage: NSImage?

    func restoreSaved() {
        guard let saved = UserDefaults.standard.string(forKey: Self.key),
              let choice = IrisIconChoice(rawValue: saved) else { applyDockIcon(originalImage()); return }
        guard let source = NSImage(named: choice.asset), let image = Self.bitmapIcon(source) else { applyDockIcon(originalImage()); return }
        // Restore the Dock appearance without mutating the installed signed bundle at startup.
        // Finder metadata is changed only when the user explicitly chooses an icon.
        selection = choice; applyDockIcon(image)
    }

    func select(_ choice: IrisIconChoice) {
        guard let source = NSImage(named: choice.asset), let image = Self.bitmapIcon(source) else {
            error = "This icon couldn’t be loaded. Please try another icon."
            return
        }
        // Apply the owner-selected Finder custom icon without replacing executable
        // or sealed resources. Finder metadata can affect strict signature checks.
        let finderUpdated = NSWorkspace.shared.setIcon(image, forFile: Bundle.main.bundlePath, options: [])
        applyDockIcon(image)
        selection = choice
        error = finderUpdated ? nil : "The Dock icon changed, but macOS couldn’t update Finder. Install Iris in a writable Applications folder and choose the icon again."
        UserDefaults.standard.set(choice.rawValue, forKey: Self.key)
    }

    func restoreOriginal() {
        let finderUpdated = NSWorkspace.shared.setIcon(nil, forFile: Bundle.main.bundlePath, options: [])
        applyDockIcon(originalImage())
        selection = nil
        error = finderUpdated ? nil : "The Dock icon was restored, but macOS couldn’t restore Finder. Please check that Iris’s folder is writable."
        UserDefaults.standard.removeObject(forKey: Self.key)
    }
    // Decode first: do not hand a lazy asset representation to the Dock process.
    static func bitmapIcon(_ source: NSImage) -> NSImage? {
        var bounds = NSRect(x: 0, y: 0, width: 1024, height: 1024)
        guard let pixels = source.cgImage(forProposedRect: &bounds, context: nil, hints: nil),
              pixels.width > 0, pixels.height > 0 else { return nil }
        return NSImage(cgImage: pixels, size: NSSize(width: 512, height: 512))
    }

    private func originalImage() -> NSImage? {
        let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleIconFile") as? String ?? "AppIcon"
        let base = (name as NSString).deletingPathExtension
        let source = Bundle.main.url(forResource: base, withExtension: "icns").flatMap { NSImage(contentsOf: $0) } ?? NSImage(named: "AppIcon")
        return source.flatMap(Self.bitmapIcon)
    }

    private func applyDockIcon(_ image: NSImage?) {
        guard let image else { return } // Never replace a valid icon with nil/empty data.
        dockImage = image
        NSApp.applicationIconImage = image
        refreshDockIcon()
        // Launch Services can finish creating the tile after didFinishLaunching.
        DispatchQueue.main.async { [weak self] in self?.refreshDockIcon() }
    }

    func refreshDockIcon() {
        guard let image = dockImage ?? originalImage() else { return }
        // A custom NSDockTile content view can become blank when accessory mode
        // destroys/recreates the tile. Let AppKit draw its native application icon.
        dockImage = image
        NSApp.applicationIconImage = image
        NSApp.dockTile.display()
    }

    #if DEBUG
    static func validateResources() {
        do {
            let icons = IrisAppIcons.shared
            let candidates = [("original", icons.originalImage())] + IrisIconChoice.allCases.map { ($0.rawValue, NSImage(named: $0.asset).flatMap(bitmapIcon)) }
            for (name, candidate) in candidates {
                guard let image = candidate, let data = image.tiffRepresentation,
                      let bitmap = NSBitmapImageRep(data: data) else { throw IrisFailure.message("Missing icon: " + name) }
                var visible = 0
                for y in stride(from: 0, to: bitmap.pixelsHigh, by: 16) {
                    for x in stride(from: 0, to: bitmap.pixelsWide, by: 16) {
                        if (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.2 { visible += 1 }
                    }
                }
                guard visible > 100 else { throw IrisFailure.message("Blank icon: " + name) }
            }
            icons.restoreSaved(); icons.refreshDockIcon()
            guard NSApp.applicationIconImage != nil else { throw IrisFailure.message("Native Dock image unavailable") }
            NSLog("IRIS_DOCK_RESOURCES_PASS %d decoded, nonblank icons; native Dock rendering", candidates.count)
        } catch { NSLog("IRIS_DOCK_RESOURCES_FAILED %@", error.localizedDescription) }
        NSApp.terminate(nil)
    }
    #endif

}

struct IrisIconSettings: View {
    let accent: Color
    @ObservedObject private var icons = IrisAppIcons.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("App icon").font(.headline)
                    Text(icons.selection.map { "Your little \($0.title) companion." } ?? "A familiar face. A new personality.")
                        .font(.system(size: 13)).foregroundStyle(IrisDesign.secondary)
                }
                Spacer()
                Button("Use original") { icons.restoreOriginal() }
                    .buttonStyle(IrisActionStyle()).disabled(icons.selection == nil)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 138), spacing: 12)], spacing: 12) {
                ForEach(IrisIconChoice.allCases) { choice in
                    IrisIconTile(choice: choice, selected: icons.selection == choice, accent: accent) { icons.select(choice) }
                }
            }
            Text("Changes Iris in the Dock, Finder and app launchers. Your choice is remembered; launcher previews may take a moment to refresh.")
                .font(.caption).foregroundStyle(IrisDesign.secondary)
            if let error = icons.error {
                Label(error, systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(.orange)
            }
        }
    }
}

private struct IrisIconTile: View {
    let choice: IrisIconChoice
    let selected: Bool
    let accent: Color
    let action: () -> Void
    @Environment(\.irisReduceMotion) private var reduceMotion
    @State private var hovered = false
    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(choice.asset).resizable().interpolation(.high).scaledToFit().frame(width: 88, height: 88)
                Text(choice.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(.primary)
                Text(choice.detail).font(.system(size: 11)).foregroundStyle(IrisDesign.secondary).lineLimit(1)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 15).padding(.horizontal, 8)
            .background(selected ? accent.opacity(0.10) : Color.white.opacity(hovered ? 0.055 : 0.025), in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(selected ? accent.opacity(0.85) : Color.white.opacity(0.08), lineWidth: selected ? 2 : 1))
            .overlay(alignment: .topTrailing) {
                if selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(accent).font(.system(size: 17, weight: .bold)).padding(10) }
            }
            .scaleEffect(hovered && !reduceMotion ? 1.025 : 1)
        }
        .buttonStyle(.plain).onHover { hovered = $0 }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: hovered)
        .accessibilityLabel("\(choice.title) app icon, \(choice.detail)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
