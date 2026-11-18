import AppKit
import UniformTypeIdentifiers
import ImageIO

/// Consume explicit file/image transfers; ordinary text and web links remain text.
enum ComposerPasteboard {
    enum Payload {case files([URL]);case data(Data,String)}
    static let types:[NSPasteboard.PasteboardType] = [.fileURL,.png,.tiff,.pdf,.init(UTType.jpeg.identifier)]
    static func read(_ board:NSPasteboard)->Payload? {
        if let urls=board.readObjects(forClasses:[NSURL.self],options:[.urlReadingFileURLsOnly:true]) as? [URL],!urls.isEmpty{return .files(urls)}
        for (type,ext) in [(NSPasteboard.PasteboardType.png,"png"),(.tiff,"tiff"),(.pdf,"pdf"),(.init(UTType.jpeg.identifier),"jpg")] {
            if let bytes=board.data(forType:type),!bytes.isEmpty{return .data(bytes,ext)}
        }
        return nil
    }
    static func accepts(_ board:NSPasteboard)->Bool {
        board.availableType(from:types) != nil || board.canReadObject(forClasses:[NSFilePromiseReceiver.self],options:nil)
    }
    static func directory()throws->URL {
        let base=try FileManager.default.url(for:.applicationSupportDirectory,in:.userDomainMask,appropriateFor:nil,create:true)
        let folder=base.appendingPathComponent("Iris/Chat Attachments/"+UUID().uuidString,isDirectory:true)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true);return folder
    }
    static func save(_ data:Data,extension ext:String,destination:URL?=nil)throws->URL {
        guard ["png","tiff","jpg","pdf"].contains(ext),!data.isEmpty,data.count <= (ext == "pdf" ? 20_000_000 : 80_000_000) else{throw IrisFailure.message("Paste an image smaller than 80 MB or a PDF smaller than 20 MB.")}
        var bytes=data,suffix=ext
        if ext != "pdf" {
            // Clipboard TIFFs from Retina displays can be much larger than their
            // equivalent PNG. Downsample before the normal attachment-size check.
            guard let source=CGImageSourceCreateWithData(data as CFData,[kCGImageSourceShouldCache:false] as CFDictionary),
                  let image=CGImageSourceCreateThumbnailAtIndex(source,0,[kCGImageSourceCreateThumbnailFromImageAlways:true,kCGImageSourceCreateThumbnailWithTransform:true,kCGImageSourceThumbnailMaxPixelSize:2048] as CFDictionary),
                  let jpeg=NSBitmapImageRep(cgImage:image).representation(using:.jpeg,properties:[.compressionFactor:0.85]),jpeg.count<=2_000_000 else{throw IrisFailure.message("This clipboard image couldn't be prepared. Try copying a smaller image.")}
            bytes=jpeg;suffix="jpg"
        }
        let folder:URL
        if let destination{folder=destination}else{folder=try directory()}
        let file=folder.appendingPathComponent("Pasted attachment."+suffix);try bytes.write(to:file,options:.atomic);return file
    }
}
