import SwiftUI
import AppKit
import ImageIO

struct ChatFileCard: View {
    @ObservedObject var iris: IrisOrchestrator
    let file: ChatFileReference
    @State private var preview: NSImage?
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let preview { Image(nsImage: preview).resizable().scaledToFit().frame(maxHeight: 240).clipShape(RoundedRectangle(cornerRadius: 10)) }
            HStack(spacing: 12) {
                Image(systemName: "doc.fill").irisSymbolStyle().font(.system(size: 24)).foregroundStyle(iris.accent)
                VStack(alignment: .leading, spacing: 4) {
                    Text(file.name).font(.system(size: 13, weight: .semibold)).lineLimit(2)
                    Text("On your Mac · content stays local until you send it").font(.system(size: 10)).foregroundStyle(IrisDesign.secondary)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 16) {
                Button("Open", systemImage: "arrow.up.right.square") { iris.openChatFile(file) }
                Button("Use in question", systemImage: "paperclip") { iris.useChatFile(file) }.disabled(iris.contextBusy || iris.busy)
            }.font(.system(size: 12)).buttonStyle(.plain).foregroundStyle(iris.accent)
        }.padding(14).frame(maxWidth: .infinity, alignment: .leading).background(.black.opacity(0.2), in: RoundedRectangle(cornerRadius: 12))
        .task(id: file.id) {
            guard ["png", "jpg", "jpeg", "webp", "heic", "heif", "gif", "tif", "tiff", "bmp"].contains((file.name as NSString).pathExtension.lowercased()) else { return }
            preview = try? iris.actions.withFile(file) { url in
                guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 512, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) else { throw IrisFailure.message("No preview available.") }
                return NSImage(cgImage: image, size: .zero)
            }
        }
    }
}
