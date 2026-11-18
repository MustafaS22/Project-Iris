import XCTest
import ImageIO
@testable import IrisCore
final class DiagramReferenceTests: XCTestCase {
    func testComplexTopicsPreferReferencesWithoutScreenCapture() {
        for text in ["Draw d orbitals", "Explain sp2 hybridisation with a diagram", "Draw a neuron", "Explain the digestive system", "Draw a detailed diagram of a kidney"] {XCTAssertTrue(DiagramReference.wantsOnline(text),text);XCTAssertFalse(ScreenQuestionPolicy.wantsSnapshot(text),text)}
        XCTAssertFalse(DiagramReference.wantsOnline("Label this neuron on my screen"))
        XCTAssertEqual(DiagramReference.query("Draw a neuron for Mustafa"),"neuron labelled anatomy diagram")
        XCTAssertEqual(DiagramReference.query("Explain sp2 hybridisation for Jane"),"sp2 orbital hybridization diagram")
    }
    func testReferenceIDsAndRemoteImageHostsAreRestricted() throws {
        for id in ["../private","/etc/passwd","https://example.com/x","a.b","é",String(repeating:"a",count:81)] {XCTAssertFalse(DiagramReference.validID(id));XCTAssertThrowsError(try ScreenDrawing.decode("{\"figure\":\""+id+"\",\"marks\":[]}"))}
        for url in ["http://upload.wikimedia.org/a.png","https://upload.wikimedia.org.evil.example/x","file:///tmp/x","https://example.com/x"] {XCTAssertFalse(DiagramReference.trustedImageURL(URL(string:url)!))}
        XCTAssertTrue(DiagramReference.trustedImageURL(URL(string:"https://upload.wikimedia.org/a.png")!))
    }
    func testBundledSourcesLicensesAndImagesAreComplete() throws {
        let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Project IRIS")
        let records=try JSONDecoder().decode([DiagramReference].self,from:Data(contentsOf:root.appendingPathComponent("DiagramReferences.json")))
        XCTAssertEqual(Set(records.map(\.id)),DiagramReference.bundledIDs)
        for item in records {
            XCTAssertFalse(item.author.isEmpty);XCTAssertFalse(item.license.isEmpty);XCTAssertTrue(item.sourceURL.hasPrefix("https://commons.wikimedia.org/"))
            let data=try Data(contentsOf:root.appendingPathComponent("Assets.xcassets/Reference-"+item.id+".imageset/figure.png"))
            let src=try XCTUnwrap(CGImageSourceCreateWithData(data as CFData,nil))
            let properties=try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(src,0,nil) as? [String:Any])
            XCTAssertLessThanOrEqual(properties[kCGImagePropertyPixelWidth as String] as? Int ?? 9999,1800)
            XCTAssertLessThanOrEqual(properties[kCGImagePropertyPixelHeight as String] as? Int ?? 9999,1800)
        }
        for id in ["atomic-orbitals","hybridisation","hybridisation-sp2","neuron","digestive-system"] {XCTAssertEqual(DiagramLibrary.entry(id)?.drawing.figure,id)}
    }
}
