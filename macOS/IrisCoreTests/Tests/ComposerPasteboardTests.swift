import XCTest
import AppKit
@testable import IrisCore
@MainActor final class ComposerPasteboardTests:XCTestCase {
    func testImageAndFileTransfersReachNativeEditorWithoutPastingGibberish()throws {
        let board=NSPasteboard.withUniqueName();defer{board.releaseGlobally()}
        let editor=MentionTextEditor.Editor(frame:.zero)
        var images=0,files:[URL]=[]
        editor.onData={data,ext in XCTAssertEqual(data,Data([1,2,3]));XCTAssertEqual(ext,"png");images += 1;return true}
        editor.onFiles={files=$0;return true}
        board.setData(Data([1,2,3]),forType:.png)
        XCTAssertTrue(editor.insertAttachments(from:board));XCTAssertEqual(images,1);XCTAssertTrue(editor.string.isEmpty)
        board.clearContents();let url=URL(fileURLWithPath:"/tmp/iris-test.pdf");board.writeObjects([url as NSURL])
        XCTAssertTrue(editor.insertAttachments(from:board));XCTAssertEqual(files,[url])
        board.clearContents();board.setString("Ordinary text and https://example.com",forType:.string)
        XCTAssertFalse(editor.insertAttachments(from:board));XCTAssertFalse(ComposerPasteboard.accepts(board))
    }
    func testClipboardPayloadSizeIsBounded(){XCTAssertThrowsError(try ComposerPasteboard.save(Data(repeating:0,count:80_000_001),extension:"png"));XCTAssertThrowsError(try ComposerPasteboard.save(Data([1]),extension:"sh"))}
    func testLargeRetinaClipboardImageIsDownsampledBeforeAttaching()throws {
        let bitmap=try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:4096,pixelsHigh:1536,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0))
        let tiff=try XCTUnwrap(bitmap.tiffRepresentation);XCTAssertGreaterThan(tiff.count,20_000_000)
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true);defer{try? FileManager.default.removeItem(at:folder)}
        let file=try ComposerPasteboard.save(tiff,extension:"tiff",destination:folder)
        let saved=try Data(contentsOf:file);XCTAssertLessThan(saved.count,2_000_000);XCTAssertEqual(file.pathExtension,"jpg")
    }

}
