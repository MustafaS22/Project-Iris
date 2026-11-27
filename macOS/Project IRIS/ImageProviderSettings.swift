import SwiftUI

struct ImageProviderSettings: View {
    @State private var key = ""
    @State private var accountID = ""
    @State private var saved = false
    @State private var status = ""
    @AppStorage(ImageProvider.preferenceKey) private var provider = ImageProvider.openAI
    @AppStorage("IrisImageGenerationModel") private var model = "gpt-image-2.5-flare"

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Image generation").font(.headline)
            IrisPicker("Image provider", selection: $provider, options: ImageProvider.allCases.map { .init(value: $0, title: $0.title) })
            Text(saved ? "Credential saved in this Mac’s Keychain." : "Add a developer credential for the selected image provider.")
                .font(.caption).foregroundStyle(IrisDesign.secondary)

            if provider == .cloudflare {
                Text("FLUX.1 Schnell uses your Workers AI quota. Workers Free stops at the daily limit.")
                    .font(.caption).foregroundStyle(IrisDesign.secondary)
                TextField("Cloudflare Account ID", text: $accountID)
                    .textFieldStyle(IrisTextFieldStyle()).accessibilityLabel("Cloudflare Account ID")
            }

            let keyLabel = provider == .cloudflare ? "Workers AI API token" : "OpenAI API key"
            SecureField(keyLabel, text: $key).textFieldStyle(IrisTextFieldStyle()).accessibilityLabel(keyLabel)

            HStack {
                Button("Save credential") { save() }
                    .disabled(key.isEmpty || (provider == .cloudflare && accountID.isEmpty))
                Button("Remove credential") {
                    report("Credential removed.") {
                        try ImageAPIVault.delete(provider)
                        key = ""; accountID = ""; saved = false
                    }
                }.disabled(!saved)
            }

            if provider == .openAI {
                IrisPicker("Image model", selection: $model, options: ImageGenerationService.models.map { .init(value: $0, title: $0, symbol: "photo") })
                Link("OpenAI image-generation documentation", destination: URL(string: "https://developers.openai.com/api/docs/guides/image-generation")!)
            } else {
                Link("Cloudflare Workers AI setup", destination: URL(string: "https://developers.cloudflare.com/workers-ai/get-started/rest-api/")!)
            }
            if !status.isEmpty { Text(status).font(.caption).foregroundStyle(IrisDesign.secondary) }
        }
        .onAppear { refresh() }
        .onChange(of: provider) { _, _ in refresh() }
    }

    private func refresh() {
        key = ""; accountID = ""; status = ""; saved = false
        report("") {
            if provider == .cloudflare {
                let credential = try ImageAPIVault.readCloudflare()
                saved = credential != nil
                accountID = credential?.accountID ?? ""
            } else {
                saved = try ImageAPIVault.read() != nil
            }
        }
    }

    private func save() {
        report("Credential saved. Saving uses no image quota.") {
            if provider == .cloudflare {
                let credential = try CloudflareImageCredential(accountID: accountID, token: key)
                try ImageAPIVault.saveCloudflare(credential)
                accountID = credential.accountID
            } else {
                try ImageAPIVault.save(key)
            }
            key = ""; saved = true
        }
    }

    private func report(_ success: String, action: () throws -> Void) {
        do { try action(); status = success }
        catch { status = error.localizedDescription }
    }
}
