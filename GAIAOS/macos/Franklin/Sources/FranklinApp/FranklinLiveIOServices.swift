import AVFoundation
import Foundation
import Speech
import Vision

#if canImport(FoundationModels)
import FoundationModels
#endif

struct FranklinVoiceProfile: Codable {
    let personaID: String
    let locale: String
    let preferredVoiceIdentifier: String
    let fallbackVoiceIdentifier: String
    let speakingRate: Float
    let pitchMultiplier: Float

    static let `default` = FranklinVoiceProfile(
        personaID: "franklin.guide.v1",
        locale: "en_US",
        preferredVoiceIdentifier: "com.apple.ttsbundle.siri_male_en-US_compact",
        fallbackVoiceIdentifier: "com.apple.ttsbundle.Alex-compact",
        speakingRate: 0.43,
        pitchMultiplier: 0.84
    )
}

@MainActor
final class FranklinSpeechLoopService {
    static let shared = FranklinSpeechLoopService()

    private let synthesizer = AVSpeechSynthesizer()
    private let voiceProfile: FranklinVoiceProfile
    private let recognizer: SFSpeechRecognizer?

    private init() {
        voiceProfile = FranklinSpeechLoopService.loadVoiceProfile()
        recognizer = SFSpeechRecognizer(locale: Locale(identifier: voiceProfile.locale))
    }

    func startListening() {
        SFSpeechRecognizer.requestAuthorization { _ in }
    }

    func stopListening() {}

    func speak(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = voiceProfile.speakingRate
        utterance.pitchMultiplier = voiceProfile.pitchMultiplier
        if let preferred = AVSpeechSynthesisVoice(identifier: voiceProfile.preferredVoiceIdentifier) {
            utterance.voice = preferred
        } else if let fallback = AVSpeechSynthesisVoice(identifier: voiceProfile.fallbackVoiceIdentifier) {
            utterance.voice = fallback
        } else {
            utterance.voice = AVSpeechSynthesisVoice(language: voiceProfile.locale)
        }
        synthesizer.speak(utterance)
    }

    private static func loadVoiceProfile() -> FranklinVoiceProfile {
        let fm = FileManager.default
        var cursor = URL(fileURLWithPath: fm.currentDirectoryPath, isDirectory: true)
        for _ in 0..<10 {
            let profile = cursor.appendingPathComponent("cells/franklin/avatar/bundle_assets/voice/franklin_voice_profile.json")
            if let data = try? Data(contentsOf: profile),
               let decoded = try? JSONDecoder().decode(FranklinVoiceProfile.self, from: data) {
                return decoded
            }
            cursor.deleteLastPathComponent()
        }
        return .default
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
