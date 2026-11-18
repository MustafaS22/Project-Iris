import SwiftUI
import AppKit

struct AttachmentTray: View {
    @ObservedObject var iris: IrisOrchestrator
    var body: some View {
        if iris.contextBusy { HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Preparing attachments…").font(.caption) }.accessibilityLabel("Preparing attachments") }
        if !iris.attachments.isEmpty {
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(iris.attachments) { item in
                        HStack(spacing: 9) {
                            if let bytes = item.image?.data, let image = NSImage(data: bytes) {
                                Image(nsImage: image).resizable().scaledToFit().frame(width: 42, height: 42).clipShape(RoundedRectangle(cornerRadius: 5))
                            } else { Image(systemName: "doc.text").irisSymbolStyle().font(.title3).foregroundStyle(iris.accent).frame(width: 28) }
                            VStack(alignment: .leading, spacing: 3) {
                                Button(item.name) { if let file = item.file { iris.openChatFile(file) } }.buttonStyle(.plain).lineLimit(1)
                                Text(item.note ?? "Text ready to send").font(.system(size: 10)).foregroundStyle(IrisDesign.secondary).lineLimit(2)
                            }.frame(maxWidth: 220, alignment: .leading)
                            Button { iris.attachments.removeAll { $0.id == item.id } } label: { Image(systemName: "xmark.circle.fill").irisSymbolStyle().foregroundStyle(IrisDesign.secondary) }.buttonStyle(.plain).disabled(iris.busy).accessibilityLabel("Remove \(item.name)")
                        }.font(.system(size: 12)).padding(10).background(IrisDesign.control, in: RoundedRectangle(cornerRadius: 10))
                    }
                }
            }.scrollIndicators(.hidden).frame(maxHeight: 78)
        }
    }
}
