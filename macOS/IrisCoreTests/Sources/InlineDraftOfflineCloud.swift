import Foundation

/// The inline regression harness deliberately cannot contact a paid cloud provider.
@MainActor enum CloudModelService {
    static func models(source: KnowledgeSource) async throws -> [String] { throw IrisFailure.message("Cloud calls are disabled in the offline test harness") }
    static func answer(source: KnowledgeSource, model: String, messages: [ChatMessage], context: String, draftInstruction: String?, outputLimit: Int?) async throws -> String {
        throw IrisFailure.message("Cloud calls are disabled in the offline test harness")
    }
}
