import AppKit
let app = NSApplication.shared
app.setActivationPolicy(.regular)
let window = NSWindow(contentRect:NSRect(x:350,y:200,width:560,height:320),styleMask:[.titled,.closable,.resizable],backing:.buffered,defer:false)
window.title = "Iris Computer Use Test"
let field = NSTextField(frame:NSRect(x:30,y:210,width:480,height:30)); field.placeholderString = "Validation input"; field.setAccessibilityIdentifier("iris-test-input"); field.setAccessibilityLabel("Validation input")
let output = NSTextField(labelWithString:"Not applied"); output.frame = NSRect(x:30,y:80,width:480,height:70); output.setAccessibilityLabel("Validation result")
final class Handler: NSObject { let field:NSTextField; let output:NSTextField; init(_ field:NSTextField,_ output:NSTextField) {self.field=field;self.output=output}; @objc func apply(_ sender:Any?) { output.stringValue="Applied: " + field.stringValue } }
let handler = Handler(field,output)
let button = NSButton(title:"Apply test text",target:handler,action:#selector(Handler.apply)); button.frame = NSRect(x:30,y:150,width:180,height:35)
window.contentView?.addSubview(field); window.contentView?.addSubview(button); window.contentView?.addSubview(output)
Timer.scheduledTimer(withTimeInterval:0.1,repeats:true) { _ in
 let delayed = URL(fileURLWithPath:"/tmp/IrisComputerValidation/show-delayed.flag")
 if FileManager.default.fileExists(atPath:delayed.path) {
  try? FileManager.default.removeItem(at:delayed)
  DispatchQueue.main.asyncAfter(deadline:.now()+2) {
   let ready = NSButton(title:"Delayed ready",target:nil,action:nil); ready.frame = NSRect(x:260,y:150,width:180,height:35); window.contentView?.addSubview(ready)
  }
 }
 let marker=URL(fileURLWithPath:"/tmp/IrisComputerValidation/show-dialog.flag")
 if FileManager.default.fileExists(atPath:marker.path) { try? FileManager.default.removeItem(at:marker); let alert=NSAlert(); alert.messageText="Unexpected test dialog"; alert.informativeText="Isolated native recovery test"; alert.addButton(withTitle:"Cancel test"); alert.runModal() }
}
window.makeKeyAndOrderFront(nil); window.makeFirstResponder(field); app.activate(); app.run()
