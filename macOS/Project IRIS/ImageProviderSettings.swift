import SwiftUI

struct ImageProviderSettings: View {
    @State private var key = ""
    @State private var saved = false
    @State private var status = ""
    @AppStorage("IrisImageGenerationModel") private var model = "gpt-image-2.5-flare"
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Image generation").font(.headline)
            Text(saved ? "API key saved in this Mac's Keychain." : "Add an OpenAI developer API key. Iris never uses your ChatGPT OAuth token for image generation.").font(.caption).foregroundStyle(IrisDesign.secondary)
            SecureField("OpenAI API key", text: $key).textFieldStyle(IrisTextFieldStyle())
            HStack {
                Button("Save key") { do { try ImageAPIVault.save(key); key = ""; saved = true; status = "Key saved. It wasn't tested or charged." } catch { status = error.localizedDescription } }.disabled(key.isEmpty)
                Button("Remove key") { do { try ImageAPIVault.delete(); saved = false; key = ""; status = "Key removed." } catch { status = error.localizedDescription } }.disabled(!saved)
            }
            IrisPicker("Image model", selection: $model, options: ImageGenerationService.models.map { .init(value: $0, title: $0, symbol: "photo") })
            Link("OpenAI image-generation documentation", destination: URL(string: "https://developers.openai.com/api/docs/guides/image-generation")!)
            if !status.isEmpty { Text(status).font(.caption).foregroundStyle(IrisDesign.secondary) }
        }.onAppear { saved = (try? ImageAPIVault.read()) != nil }
    }
}
