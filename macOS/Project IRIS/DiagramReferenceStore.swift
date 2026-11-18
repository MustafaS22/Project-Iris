import AppKit
import CryptoKit

/// Image loading is restricted to a bundled catalog or app-owned cache, never model file paths.
@MainActor enum DiagramReferenceStore {
    static let bundled: [DiagramReference] = {
        guard let url=Bundle.main.url(forResource:"DiagramReferences",withExtension:"json"),let data=try? Data(contentsOf:url) else{return []}
        return (try? JSONDecoder().decode([DiagramReference].self,from:data)) ?? []
    }()
    private static var fetched: [String:DiagramReference] = [:]
    private static var images: [String:NSImage] = [:]
    private static var queries: [String:String] = [:]
    private static var folder: URL { FileManager.default.urls(for:.cachesDirectory,in:.userDomainMask)[0].appendingPathComponent("com.projectiris.diagram-references",isDirectory:true) }
    static func reference(_ id:String)->DiagramReference? {
        guard DiagramReference.validID(id) else{return nil}
        if let r=bundled.first(where:{$0.id==id}) ?? fetched[id] {return r}
        guard let data=try? Data(contentsOf:folder.appendingPathComponent(id+".json")),let r=try? JSONDecoder().decode(DiagramReference.self,from:data),r.id==id else{return nil}
        fetched[id]=r;return r
    }
    static func image(_ id:String)->NSImage? {
        guard DiagramReference.validID(id),reference(id) != nil else{return nil}
        if let image=images[id]{return image}
        let image=NSImage(named:"Reference-"+id) ?? NSImage(contentsOf:folder.appendingPathComponent(id+".png"))
        if let image {if images.count>24{images.removeAll()};images[id]=image};return image
    }
    static func modelImage(_ id:String) throws -> ModelImage {
        guard let image=image(id),let tiff=image.tiffRepresentation,let rep=NSBitmapImageRep(data:tiff),let data=rep.representation(using:.jpeg,properties:[.compressionFactor:0.82]) else{throw IrisFailure.message("The reference diagram couldn't be opened.")}
        return ModelImage(data:data,mimeType:"image/jpeg")
    }
    static func search(_ prompt:String) async throws -> DiagramReference {
        let query=DiagramReference.query(prompt)
        if let id=queries[query],let r=reference(id),image(id) != nil{return r}
        var parts=URLComponents(string:"https://commons.wikimedia.org/w/api.php")!
        parts.queryItems=["action":"query","format":"json","generator":"search","gsrsearch":query,"gsrnamespace":"6","gsrlimit":"5","prop":"imageinfo","iiprop":"url|extmetadata","iiurlwidth":"1600"].map{URLQueryItem(name:$0.key,value:$0.value)}
        var req=URLRequest(url:parts.url!);req.timeoutInterval=15;req.setValue("Iris/2.0 diagram reference viewer",forHTTPHeaderField:"User-Agent")
        let (data,response)=try await URLSession.shared.data(for:req)
        guard (response as? HTTPURLResponse)?.statusCode==200,data.count<1_000_000,let root=try JSONSerialization.jsonObject(with:data) as? [String:Any],let pages=(root["query"] as? [String:Any])?["pages"] as? [String:[String:Any]] else{throw IrisFailure.message("The online diagram source is unavailable or rate-limited. Try a saved reference or try again later.")}
        let ordered=pages.values.sorted{($0["index"] as? Int ?? 999)<($1["index"] as? Int ?? 999)}
        for page in ordered {
            guard let info=(page["imageinfo"] as? [[String:Any]])?.first,let meta=info["extmetadata"] as? [String:[String:Any]] else{continue}
            func value(_ key:String)->String{ Self.clean(meta[key]?["value"] as? String ?? "") }
            let license=value("LicenseShortName")
            guard license.hasPrefix("CC BY") || ["CC0","Public domain"].contains(license),let url=URL(string:info["thumburl"] as? String ?? info["url"] as? String ?? ""),DiagramReference.trustedImageURL(url),let source=info["descriptionurl"] as? String,URL(string:source)?.host=="commons.wikimedia.org" else{continue}
            let id="web-"+SHA256.hash(data:Data(url.absoluteString.utf8)).map{String(format:"%02x",$0)}.joined()
            if let cached=reference(id),image(id) != nil{queries[query]=id;return cached}
            var imageReq=URLRequest(url:url);imageReq.timeoutInterval=20
            let (bytes,res)=try await URLSession.shared.data(for:imageReq)
            try Task.checkCancellation()
            guard (res as? HTTPURLResponse)?.statusCode==200,bytes.count<12_000_000,let image=NSImage(data:bytes),image.size.width>=200,image.size.height>=100,image.size.width<=6000,image.size.height<=6000,image.size.width*image.size.height<=16_000_000 else{continue}
            let r=DiagramReference(id:id,title:Self.clean(page["title"] as? String ?? "Reference diagram").replacingOccurrences(of:"File:",with:""),author:value("Artist"),license:license,licenseURL:value("LicenseUrl"),sourceURL:source,imageURL:url.absoluteString,changes:"Displayed from Wikimedia thumbnail; content unchanged.")
            try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
            guard let tiff=image.tiffRepresentation,let rep=NSBitmapImageRep(data:tiff),let png=rep.representation(using:.png,properties:[:]) else{continue}
            try png.write(to:folder.appendingPathComponent(id+".png"),options:.atomic);try JSONEncoder().encode(r).write(to:folder.appendingPathComponent(id+".json"),options:.atomic)
            fetched[id]=r;images[id]=image;queries[query]=id;return r
        }
        throw IrisFailure.message("I couldn't find a reusable diagram matching that topic. Try a more specific topic, or attach the diagram you want explained.")
    }
    private static func clean(_ text:String)->String {
        String(text.replacingOccurrences(of:"<[^>]+>",with:" ",options:.regularExpression).replacingOccurrences(of:"&amp;",with:"&").replacingOccurrences(of:"&quot;",with:"\"").replacingOccurrences(of:"&#39;",with:"'").split(whereSeparator:{$0.isWhitespace}).joined(separator:" ").prefix(600))
    }
}
