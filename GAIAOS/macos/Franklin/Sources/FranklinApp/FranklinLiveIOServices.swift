import AVFoundation
import Foundation
import Speech
import Vision

#if canImport(FoundationModels)
import FoundationModels
#endif

@MainActor
final class FranklinSpeechLoopService {
    static let shared = FranklinSpeechLoopService()

    private let synthesizer = AVSpeechSynthesizer()
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en_US"))

    private init() {}

    func startListening() {
        SFSpeechRecognizer.requestAuthorization { _ in }
    }

    func stopListening() {}

    func speak(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = 0.45
        synthesizer.speak(utterance)
    }
}

@MainActor
final class FranklinVisionAttentionService {
    static let shared = FranklinVisionAttentionService()
    private let request = VNDetectFaceLandmarksRequest()

    private init() {}

    func start() {
        _ = request
    }

    func stop() {}
}

@MainActor
final class FranklinFoundationDialogService {
    static let shared = FranklinFoundationDialogService()
    private init() {}

    func composeReply(for prompt: String) async -> String {
#if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            do {
                let session = LanguageModelSession()
                let response = try await session.respond(to: prompt)
                return response.content
            } catch {
                return "I remain in character and await the next command."
            }
        }
#endif
        return "I remain in character and await the next command."
    }
}
