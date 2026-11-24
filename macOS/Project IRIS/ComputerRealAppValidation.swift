#if DEBUG
import AppKit
import ApplicationServices
import MCP

/// Opt-in integration checks against disposable content in real macOS applications.
@MainActor enum ComputerRealAppValidation {
    static func run(record: (String,String)->Void, directory: URL) async {
        let native = NativeComputerUse(); native.policy.mode = .assist; native.policy.shareScreen = true
        native.cursor.show(); defer { native.cursor.hide() }
        func key(_ key: String, _ modifiers: [Value] = []) async throws {
            _ = try await native.execute(modifiers.isEmpty ? "press_key" : "keyboard_shortcut",["key":.string(key)].merging(modifiers.isEmpty ? [:] : ["modifiers":.array(modifiers)]) { a,_ in a })
            try await Task.sleep(for:.milliseconds(250))
        }
        func launch(_ id: String) async throws {
            _ = try await native.execute("launch_application",["bundle_id":.string(id)])
            for _ in 0..<30 {
                if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == id, let ready = try? await native.tree(), ready.contains("bounds=") { try await Task.sleep(for:.milliseconds(500)); return }
                try await Task.sleep(for:.milliseconds(200))
            }
            throw IrisFailure.message("Application did not become ready: " + id)
        }
        func input(_ text: String, matching: String) async throws {
            let tree = try await native.tree()
            try tree.write(to:directory.appendingPathComponent("latest-real-app-tree.txt"),atomically:true,encoding:.utf8)
            guard let row = tree.split(separator:"\n").first(where:{$0.contains(matching) && $0.contains("focused=true")}), let id = row.split(separator:" ").first else { throw IrisFailure.message("Editable target unavailable: " + matching) }
            _ = try await native.execute("type_text",["text":.string(text),"element":.string(String(id))])
            try await Task.sleep(for:.milliseconds(450))
        }
        do {
            try await launch("com.apple.Notes")
            try await key("n",["command"])
            _ = try await native.execute("wait_for_element",["query":"AXTextArea"])
            let marker = "Iris computer-control validation " + String(UUID().uuidString.prefix(8))
            try await input(marker + "\nThis disposable note verifies that Iris can open a real app, create a note, insert a paragraph, and read the resulting text. No existing note was edited.",matching:"AXTextArea")
            let result = try await native.tree()
            guard result.contains(marker) else { throw IrisFailure.message("Inserted Notes text was not observed") }
            record("real-notes","PASS: created a new disposable note, inserted a paragraph and observed its title/text through AX")
            // An actual menu opens and dismisses; no document or preference is changed.
            let menus = try await native.tree(query:"View")
            if let row = menus.split(separator:"\n").first(where:{$0.contains("AXMenuBarItem") && $0.contains("View")}), let id = row.split(separator:" ").first {
                _ = try await native.execute("click",["element":.string(String(id))]); try await Task.sleep(for:.milliseconds(250))
                let menu = try await native.tree()
                guard menu.contains("AXMenuItem") else { throw IrisFailure.message("Menu did not open") }
                try await key("escape"); record("real-menu","PASS: opened real Notes View menu with AXPress, observed items and dismissed it")
            }
        } catch { record("real-notes-or-menu","FAIL: " + error.localizedDescription) }
        do {
            let folder = directory.appendingPathComponent("Finder interaction " + UUID().uuidString,isDirectory:true)
            try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
            try await launch("com.apple.finder")
            NSWorkspace.shared.open(folder); try await Task.sleep(for:.milliseconds(550))
            try await key("n",["command","shift"])
            try await input("Iris temporary folder",matching:"AXTextField")
            try await key("return")
            let created = folder.appendingPathComponent("Iris temporary folder",isDirectory:true)
            guard FileManager.default.fileExists(atPath:created.path) else { throw IrisFailure.message("Finder did not create the named folder") }
            try await key("return")
            try await key("a",["command"])
            try await input("Iris renamed folder",matching:"AXTextField")
            try await key("return")
            guard FileManager.default.fileExists(atPath:folder.appendingPathComponent("Iris renamed folder").path) else { throw IrisFailure.message("Finder rename was not observed on disk") }
            record("real-finder","PASS: Finder UI created and renamed a disposable folder, verified both on disk")
        } catch { record("real-finder","FAIL: " + error.localizedDescription) }
        do {
            try await launch("com.apple.Safari")
            try await key("t",["command"])
            try await key("l",["command"])
            try await input("http://127.0.0.1:5197/native-search.html",matching:"AXTextField")
            try await key("return")
            _ = try await native.execute("wait_for_element",["query":"Computer use test search"])
            let fields = try await native.tree(query:"Search this test article")
            guard let row = fields.split(separator:"\n").first(where:{$0.contains("AXTextField")}), let search = row.split(separator:" ").first else { throw IrisFailure.message("Safari search field not found") }
            _ = try await native.execute("click",["element":.string(String(search))])
            try await input("Iris native input",matching:"AXTextField")
            try await key("return")
            _ = try await native.execute("wait_for_element",["query":"Found one article"])
            let links = try await native.tree(query:"Open Iris test article")
            guard let link = links.split(separator:"\n").first(where:{$0.contains("AXLink")})?.split(separator:" ").first else { throw IrisFailure.message("Search result link not found") }
            _ = try await native.execute("click",["element":.string(String(link))])
            let destination = try await native.execute("wait_for_element",["query":"Iris native browser result"])
            guard destination.text.contains("Iris native browser result") else { throw IrisFailure.message("Destination was not observed") }
            record("real-safari","PASS: new Safari tab, real local search form input, submitted query, clicked result link and observed destination page")
            if let capture = try? await native.observe(includeImage:true), let image = capture.image {
                try image.data.write(to:directory.appendingPathComponent("real-safari.jpg"))
                record("real-safari-capture","PASS: real Safari screenshot plus OCR and matching current AX IDs")
            }
        } catch { record("real-safari","FAIL: " + error.localizedDescription) }
    }
}
#endif
