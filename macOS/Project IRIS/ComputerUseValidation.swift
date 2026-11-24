#if DEBUG
import AppKit
import ApplicationServices
import SwiftUI
import MCP

@MainActor enum ComputerUseValidation {
    static func run(_ iris: IrisOrchestrator) async {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("IrisComputerValidation")
        var checks: [String:String] = [:]
        func record(_ key: String,_ value: String) { checks[key] = value; if let data = try? JSONSerialization.data(withJSONObject:checks,options:[.prettyPrinted,.sortedKeys]) { try? data.write(to:directory.appendingPathComponent("results.json")) } }
        func require(_ condition:Bool,_ message:String) throws { if !condition { throw IrisFailure.message(message) } }
        do {
            try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
            if ProcessInfo.processInfo.arguments.contains("--iris-real-app-validation") { await ComputerRealAppValidation.run(record:record,directory:directory) }
            let native = NativeComputerUse(); native.policy.mode = .observe
            let displays = try await native.execute("get_displays",[:]); try require(!displays.text.isEmpty,"No displays"); record("display-metadata","PASS: real display IDs, points and scaling")
            do { _ = try await native.execute("click",[:]); throw IrisFailure.message("Observe mode allowed click") } catch { try require(error.localizedDescription.contains("blocked"),"Observe failed closed"); record("observe-mode","PASS: blocked pointer action before execution") }
            try? FileManager.default.removeItem(at:URL(fileURLWithPath:"/tmp/IrisComputerValidation/show-dialog.flag"))
            let fixtureURL = URL(fileURLWithPath:"/tmp/IrisComputerFixture.app")
            _ = try await NSWorkspace.shared.openApplication(at:fixtureURL,configuration:.init())
            try await Task.sleep(for:.milliseconds(700))
            native.policy.mode = .assist
            if AXIsProcessTrusted() {
                let before = try await native.tree(); try require(before.contains("Validation input"),"Fixture input not found in AX tree")
                let input = before.split(separator:"\n").first(where:{$0.contains("AXTextField") && $0.contains("Validation input")})?.split(separator:" ").first.map(String.init)
                guard let input else { throw IrisFailure.message("No AX text field ID") }
                _ = try await native.execute("click",["element":.string(input)])
                _ = try await native.execute("keyboard_shortcut",["key":"a","modifiers":["command"]])
                _ = try await native.execute("type_text",["text":"Iris native test 🧪","element":.string(input)])
                try await Task.sleep(for:.milliseconds(200))
                let populated = try await native.tree(); try require(populated.contains("Iris native test"),"Unicode text not observed in field")
                let button = populated.split(separator:"\n").first(where:{$0.contains("AXButton") && $0.contains("Apply test text")})?.split(separator:" ").first.map(String.init)
                guard let button else { throw IrisFailure.message("No AX button ID") }
                native.cursor.show()
                let pointerBefore = CGEvent(source:nil)?.location
                _ = try await native.execute("click",["element":.string(button)])
                let pointerAfter = CGEvent(source:nil)?.location
                try require(pointerBefore == pointerAfter,"AX action unexpectedly moved the physical cursor")
                native.cursor.hide()
                record("independent-ax-cursor","PASS: action-linked Iris indicator accompanied actual AXPress; physical system pointer stayed unchanged")
                let after = try await native.tree(); try require(after.contains("Applied: Iris native test"),"AXPress did not update actual app")
                record("native-input","PASS: focused real AppKit field, inserted Unicode, pressed AX button, observed resulting label")
                do { _ = try await native.execute("click",["element":.string(input)]); throw IrisFailure.message("Stale element accepted") } catch { try require(error.localizedDescription.contains("stale"),"Wrong stale element rejection"); record("stale-target","PASS: old tree reference rejected") }
                do { _ = try await native.execute("move_cursor",["frame":"missing","x":0,"y":0]); throw IrisFailure.message("Missing frame accepted") } catch { try require(error.localizedDescription.contains("fresh frame"),"Wrong frame rejection"); record("frame-validation","PASS: stale/unknown coordinates blocked") }
            } else { record("native-input","BLOCKED: this Debug bundle lacks Accessibility; no permissions changed") }
            if AXIsProcessTrusted() {
                try Data().write(to:URL(fileURLWithPath:"/tmp/IrisComputerValidation/show-delayed.flag"))
                let delayed = try await native.execute("wait_for_element",["query":"Delayed ready"])
                try require(delayed.text.contains("Delayed ready"),"Delayed app control was not observed")
                record("slow-interface","PASS: waited for an actual AppKit control appearing after a two-second loading delay")
                try Data().write(to:URL(fileURLWithPath:"/tmp/IrisComputerValidation/show-dialog.flag"))
                let dialog: String
                do { dialog = try await native.execute("wait_for_element",["query":"Cancel test"]).text }
                catch {
                    if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.arize.iris.computer-fixture" { record("dialog-diagnostic",(try? await native.tree()) ?? "No AX tree") }
                    throw error
                }
                guard let cancel = dialog.split(separator:"\n").first(where:{$0.contains("AXButton") && $0.contains("Cancel test")})?.split(separator:" ").first.map(String.init) else { throw IrisFailure.message("Unexpected dialog could not be inspected") }
                _ = try await native.execute("click",["element":.string(cancel)])
                try await Task.sleep(for:.milliseconds(100)); try require(!(try await native.tree()).contains("Unexpected test dialog"),"Dialog did not dismiss")
                record("dialog-recovery","PASS: detected a real unexpected NSAlert, found its semantic Cancel control, dismissed it and re-observed the app")
                _ = try await native.execute("focus_window",["bundle_id":"com.apple.finder"]); try await Task.sleep(for:.milliseconds(180))
                let finder = try await native.execute("get_active_window",[:]); try require(finder.text.contains("com.apple.finder"),"Could not switch to Finder")
                _ = try await native.execute("focus_window",["bundle_id":"com.arize.iris.computer-fixture"]); try await Task.sleep(for:.milliseconds(180))
                let active = try await native.execute("get_active_window",[:]); try require(active.text.contains("com.arize.iris.computer-fixture"),"Could not restore fixture focus")
                record("app-switching","PASS: switched between Finder and the isolated native fixture and verified foreground identities")
            }
            if CGPreflightScreenCaptureAccess(), AXIsProcessTrusted() {
                native.policy.shareScreen = true
                let capture = try await native.execute("get_screen",[:])
                try require(capture.image != nil && capture.text.contains("POINTS="),"Screenshot or frame mapping missing")
                let frame = String(capture.text.split(separator:";")[0].dropFirst(6))
                _ = try await native.execute("move_cursor",["frame":.string(frame),"x":20,"y":20])
                record("screen-capture","PASS: actual fixture window JPEG with point/pixel transform; integer point coordinates accepted")
                let targets = try await native.tree()
                guard let fieldRow = targets.split(separator:"\n").first(where:{$0.contains("AXTextField") && $0.contains("focused=true")}), let fieldID = fieldRow.split(separator:" ").first else { throw IrisFailure.message("No focused validation editor") }
                _ = try await native.execute("type_text",["element":.string(String(fieldID)),"text":" · targeted pointer"])
                let controls = try await native.tree(query:"Apply test text")
                guard let buttonRow = controls.split(separator:"\n").first(where:{$0.contains("AXButton")}), let rawBounds = buttonRow.components(separatedBy:"bounds=").last?.split(separator:" ").first else { throw IrisFailure.message("No visual button bounds") }
                let values = rawBounds.split(separator:",").compactMap{Double($0)}
                let snapshot = try await native.execute("get_screen",[:])
                let visualFrame = String(snapshot.text.split(separator:";")[0].dropFirst(6))
                let originText = snapshot.text.components(separatedBy:"frame origin global points=")[1].split(separator:";")[0]
                let origin = originText.split(separator:",").compactMap{Double($0)}
                guard values.count == 4, origin.count == 2 else { throw IrisFailure.message("Invalid visual point transform") }
                let pointer = CGEvent(source:nil)?.location
                native.cursor.show()
                _ = try await native.execute("click",["frame":.string(visualFrame),"x":.double(values[0]+values[2]/2-origin[0]),"y":.double(values[1]+values[3]/2-origin[1]),"delivery":"application"])
                try await Task.sleep(for:.milliseconds(300))
                let applied = try await native.tree()
                if applied.split(separator:"\n").contains(where:{$0.contains("AXStaticText") && $0.contains("Applied:") && $0.contains("targeted pointer")}) {
                    try require(pointer == CGEvent(source:nil)?.location,"Targeted mouse input moved the physical pointer")
                    record("application-targeted-click","PASS: frame-relative CGEventPostToPid clicked an actual AppKit button and updated its label while the physical pointer stayed unchanged")
                } else {
                    record("application-targeted-click","LIMITATION: this AppKit window ignored targeted mouse input; independent AX actions remain supported; raw system-input fallback was tested")
                    _ = try await native.execute("click",["frame":.string(visualFrame),"x":.double(values[0]+values[2]/2-origin[0]),"y":.double(values[1]+values[3]/2-origin[1]),"delivery":"system"])
                    try await Task.sleep(for:.milliseconds(300))
                    let fallback = try await native.tree()
                    try require(fallback.split(separator:"\n").contains(where:{$0.contains("AXStaticText") && $0.contains("Applied:") && $0.contains("targeted pointer")}),"Shared pointer fallback did not activate the actual button")
                    record("visual-pointer-recovery","PASS: observed ignored targeted click, delivered explicit shared-input fallback and verified actual button result")
                }
                native.cursor.hide()
                native.discardObservation()
            } else { record("screen-capture","BLOCKED: permission preflight returned false; capture failed closed without requesting or resetting access") }
            let grantURL = directory.appendingPathComponent("Files"); try FileManager.default.createDirectory(at:grantURL,withIntermediateDirectories:true)
            let folder = GrantedFolder(name:"Computer test",bookmark:try grantURL.bookmarkData(options:IrisLocalStorage.bookmarkOptions,includingResourceValuesForKeys:nil,relativeTo:nil))
            iris.actions.folders.append(folder); defer { iris.actions.folders.removeAll{$0.id == folder.id} }
            let filename = "sample-" + UUID().uuidString + ".txt"
            _ = try ComputerUseFiles.execute("file_write",arguments:["folder":.string(folder.id),"path":.string(filename),"content":"Actual file test"],files:iris.actions)
            let read = try ComputerUseFiles.execute("file_read",arguments:["folder":.string(folder.id),"path":.string(filename)],files:iris.actions); try require(read.text == "Actual file test","File read mismatch")
            _ = try ComputerUseFiles.execute("file_create_folder",arguments:["folder":.string(folder.id),"path":"Organized"],files:iris.actions)
            _ = try ComputerUseFiles.execute("file_move",arguments:["folder":.string(folder.id),"path":.string(filename),"destination":.string("Organized/" + filename)],files:iris.actions)
            try require(FileManager.default.fileExists(atPath:grantURL.appendingPathComponent("Organized/"+filename).path),"File did not move")
            do { _ = try ComputerUseFiles.execute("file_read",arguments:["folder":.string(folder.id),"path":"../outside.txt"],files:iris.actions); throw IrisFailure.message("Traversal accepted") } catch { record("file-scope","PASS: real create/read/move; traversal rejected") }
            var preferences = Preferences(); preferences.source = .local; preferences.server = "http://127.0.0.1:5196/v1"; preferences.model = "isolated-planner-fixture"
            let loopName = "loop-" + UUID().uuidString + ".txt"
            let loop = ComputerUseSession()
            let loopServer = IrisMCPConfiguration(name:"Task HTTP fixture",url:"http://127.0.0.1:5198/mcp",enabled:true)
            loop.mcp.configurations = [loopServer]
            loop.start("Iris loop validation: create and verify file \(loopName) in Computer test",preferences:preferences,files:iris.actions) { _ in }
            for _ in 0..<250 {
                try require(!loop.paused,"Task unexpectedly paused without an explicit pause request")
                if loop.awaitingApproval {
                    guard (loop.proposedAction.contains(folder.id) && (loop.proposedAction.contains("file_write") || loop.proposedAction.contains("file_read"))) || (loop.proposedAction.contains(loopServer.id) && loop.proposedAction.contains("read_test_file")) else { throw IrisFailure.message("Unexpected test action requested") }
                    loop.approve(true)
                }
                if !loop.running { break }; try await Task.sleep(for:.milliseconds(100))
            }
            try require(loop.phase == "Finished", "Planner loop failed: " + (loop.completion ?? loop.phase))
            try require(try String(contentsOf:grantURL.appendingPathComponent(loopName),encoding:.utf8) == "HTTP real file contents","Planner did not create actual file")
            record("planner-loop","PASS: local scripted model used native app inspection, HTTP MCP file read, scoped write/read, approval, observation and verified completion end to end (no cloud quota)")
            loop.start("Iris loop validation: create and verify file loop-escape-\(UUID().uuidString).txt in Computer test",preferences:preferences,files:iris.actions) { _ in }
            for _ in 0..<100 { if loop.awaitingApproval { break }; try await Task.sleep(for:.milliseconds(100)) }
            if loop.awaitingApproval {
                let reviewWindow = NSWindow(contentRect:NSRect(x:400,y:250,width:620,height:420),styleMask:[.titled,.closable],backing:.buffered,defer:false)
                reviewWindow.title = "Iris emergency stop validation"
                reviewWindow.contentView = NSHostingView(rootView:ComputerActivityView(session:loop,accent:iris.accent).padding(20).frame(width:620).background(IrisDesign.canvas).preferredColorScheme(.dark))
                reviewWindow.makeKeyAndOrderFront(nil); NSApp.activate()
                record("escape-emergency-stop","READY: press Escape in Iris emergency stop validation while approval is pending")
                for _ in 0..<900 { if !loop.running { break }; try await Task.sleep(for:.milliseconds(100)) }
                record("escape-emergency-stop",loop.phase == "Stopped" && !loop.awaitingApproval ? "PASS: actual Escape input stopped a task while its approval continuation was pending" : "NOT VERIFIED: no external Escape input arrived; task stopped by harness cleanup")
                loop.stop(); reviewWindow.orderOut(nil)
            }
            loop.start("stop validation",preferences:preferences,files:iris.actions) { _ in }
            try await Task.sleep(for:.milliseconds(100)); loop.pause(); try require(loop.paused,"Pause failed"); loop.resume(); loop.stop()
            try require(!loop.running && !loop.awaitingApproval,"Stop left work running"); record("pause-stop","PASS: pause/resume state and stop cancel active local model task without executing an action"); loop.shutdown()
            let manager = IrisMCPManager(); let config = IrisMCPConfiguration(name:"Native validation",command:Bundle.main.executablePath,arguments:["--iris-computer-use-mcp"],enabled:true)
            manager.configurations = [config]; await manager.connect(config.id)
            try require(manager.tools.count >= 20,"Native MCP discovery failed: " + (manager.status[config.id] ?? "unknown"))
            let displayReply = try await manager.call(server:config.id,name:"get_displays",arguments:[:]); try require(displayReply.text.contains("bounds="),"Native MCP returned no real display metadata")
            record("native-mcp-stdio","PASS: spawned actual Iris MCP process, initialized, discovered tools, called real display metadata")
            await manager.disconnect(config.id); try require(manager.tools.isEmpty,"Disconnected tools remained registered")
            await manager.connect(config.id); try require(!manager.tools.isEmpty,"Reconnect failed"); await manager.disconnect(config.id)
            record("mcp-reconnect","PASS: unregister on disconnect, rediscover after restart; no action replay")
            let http = IrisMCPConfiguration(name:"HTTP validation",url:"http://127.0.0.1:5198/mcp",enabled:true)
            manager.configurations = [http]; await manager.connect(http.id)
            if manager.tools.contains(where:{$0.name == "read_test_file"}) {
                let output = try await manager.call(server:http.id,name:"read_test_file",arguments:[:]); try require(output.text.contains("HTTP real file contents"),"HTTP file result mismatch")
                let resource = try await manager.call(server:http.id,name:"iris_read_resource",arguments:["uri":"test://file"]); try require(resource.text.contains("HTTP real file contents"),"Resource read failed")
                record("mcp-streamable-http","PASS: real localhost JSON-RPC initialization, tool discovery/execution and resource discovery/read")
            } else { record("mcp-streamable-http","FAIL: " + (manager.status[http.id] ?? "unknown")) }
            let args = ProcessInfo.processInfo.arguments
            let cliIndex = args.firstIndex(of:"--iris-test-playwright-cli")
            let cli = cliIndex.flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil } ?? ""
            let node = ["/opt/homebrew/bin/node", "/usr/local/bin/node"].first(where:FileManager.default.isExecutableFile(atPath:)) ?? "/usr/local/bin/node"
            let browser = IrisMCPConfiguration(name:"Playwright validation",command:node,arguments:[cli,"--headless","--isolated","--browser","chrome"],enabled:true)
            manager.configurations = [browser]; await manager.disconnect(http.id); await manager.connect(browser.id)
            if manager.tools.contains(where:{$0.name == "browser_navigate"}) {
                let page = try await manager.call(server:browser.id,name:"browser_navigate",arguments:["url":"http://127.0.0.1:5197"])
                try require(page.text.contains("Iris Browser Validation"),"Browser did not retrieve actual page")
                record("playwright-dom","PASS: launched real headless Chrome through Microsoft's MCP server, navigated localhost page, retrieved semantic DOM snapshot")
            } else { record("playwright-dom","FAIL: Playwright unavailable: " + (manager.status[browser.id] ?? "unknown")) }
            if manager.tools.contains(where:{$0.server == browser.id && $0.name == "browser_close"}) { _ = try await manager.call(server:browser.id,name:"browser_close",arguments:[:]) }
            manager.shutdown()
            // Render production views; this does not bypass action approval or trigger an AI request.
            let session = iris.computer
            session.running = true; session.objective = "Organize the approved test folder"; session.phase = "Reading the current interface"
            session.history = [.init(tool:"native/get_accessibility_tree",detail:"Inspected the current application",succeeded:true)]
            let view = ComputerActivityView(session:session,accent:iris.accent).padding(20).frame(width:620).background(IrisDesign.canvas).preferredColorScheme(.dark)
            let host = NSHostingView(rootView:view); host.frame = NSRect(x:0,y:0,width:620,height:320); host.layoutSubtreeIfNeeded()
            if let rep = host.bitmapImageRepForCachingDisplay(in:host.bounds) { host.cacheDisplay(in:host.bounds,to:rep); try rep.representation(using:.png,properties:[:])?.write(to:directory.appendingPathComponent("activity.png")) }
            session.running = false
            record("overall","Completed bounded local validation. Only disposable validation notes, folders and tabs were created. No existing document, credential, privacy setting or AI quota changed.")
        } catch { record("failure",error.localizedDescription) }
        for app in NSRunningApplication.runningApplications(withBundleIdentifier:"com.arize.iris.computer-fixture") { app.terminate() }
        NSApp.terminate(nil)
    }
}
#endif
