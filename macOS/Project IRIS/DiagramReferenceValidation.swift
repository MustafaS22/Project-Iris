#if DEBUG
import AppKit
import SwiftUI
@MainActor enum DiagramReferenceValidation {
    static func run() {
        let output=FileManager.default.temporaryDirectory.appendingPathComponent("IrisReferenceValidation",isDirectory:true)
        do {
            try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
            guard DiagramReferenceStore.bundled.count==16 else{throw IrisFailure.message("Reference manifest missing from bundle")}
            for id in ["neuron","digestive-system","atomic-orbitals","hybridisation-sp2"] {
                guard let entry=DiagramLibrary.entry(id),DiagramReferenceStore.image(id) != nil else{throw IrisFailure.message("Missing bundled figure "+id)}
                let drawing=entry.drawing
                let renderer=ImageRenderer(content:IrisDrawingView(drawing:drawing,accent:.cyan,visibleMarkCount:drawing.presentationSteps.first?.upperBound,previewElapsed:100).frame(width:1280,height:900).background(Color(red:0.15,green:0.17,blue:0.16)))
                renderer.scale=1
                guard let data=renderer.nsImage?.tiffRepresentation,let rep=NSBitmapImageRep(data:data),let png=rep.representation(using:.png,properties:[:]) else{throw IrisFailure.message("Render failed "+id)}
                try png.write(to:output.appendingPathComponent(id+".png"))
            }
            try Data("PASS: 16 bundled reference figures; four complex reference canvases rendered without account or network access.".utf8).write(to:output.appendingPathComponent("result.txt"))
        } catch {try? Data(("FAIL: "+error.localizedDescription).utf8).write(to:output.appendingPathComponent("result.txt"))}
        NSApp.terminate(nil)
    }
}
#endif
