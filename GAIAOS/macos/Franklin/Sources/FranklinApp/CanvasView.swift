import SwiftUI
import FranklinUIKit
import AppKit

private struct FranklinMeshFallbackView: View {
    let meshLoaded: Bool

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let c = CGPoint(x: w * 0.5, y: h * 0.52)
            let head = [
                CGPoint(x: c.x, y: c.y - h * 0.28),
                CGPoint(x: c.x + w * 0.16, y: c.y - h * 0.03),
                CGPoint(x: c.x, y: c.y + h * 0.18),
                CGPoint(x: c.x - w * 0.16, y: c.y - h * 0.03),
            ]
            ZStack {
                LinearGradient(
                    colors: meshLoaded ? [Color.brown.opacity(0.35), Color.gray.opacity(0.2)] : [Color.red.opacity(0.35), Color.black.opacity(0.2)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .clipShape(RoundedRectangle(cornerRadius: 16))

                Path { p in
                    p.move(to: head[0]); p.addLines([head[1], head[2], head[3], head[0]])
                }
                .stroke(meshLoaded ? .white.opacity(0.9) : .red.opacity(0.95), lineWidth: 2)

                Circle()
                    .fill(.white.opacity(0.8))
                    .frame(width: 6, height: 6)
                    .offset(x: -16, y: -8)
                Circle()
                    .fill(.white.opacity(0.8))
                    .frame(width: 6, height: 6)
                    .offset(x: 16, y: -8)
                Capsule()
                    .fill(.white.opacity(0.7))
                    .frame(width: 30, height: 3)
                    .offset(y: 12)
            }
        }
    }
}

private struct FranklinPortraitFallbackView: View {
    let imagePath: String

    var body: some View {
        if let image = NSImage(contentsOfFile: imagePath) {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .clipShape(RoundedRectangle(cornerRadius: 18))
        } else {
            FranklinMeshFallbackView(meshLoaded: false)
        }
    }
}

struct CanvasView: View {
    @EnvironmentObject var model: OperatorSurfaceModel
    @State private var didInitialGuide = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            FranklinAvatarStage()
                .environmentObject(model)
            Text("Franklin Presence Canvas")
                .font(.title3.bold())
            HStack(spacing: 8) {
                Text("Franklin: \(model.franklinStatus)")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.black.opacity(0.08))
                    .clipShape(Capsule())
                Text("Facet: \(model.activeFacet.rawValue)")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.black.opacity(0.08))
                    .clipShape(Capsule())
                if let latest = model.latestReceipt(for: model.activeFacet) {
                    Text("Last \(model.activeFacet.rawValue): \(latest.terminal)")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(.black.opacity(0.08))
                        .clipShape(Capsule())
                }
            }
            HStack {
                ForEach(FranklinFacet.allCases) { facet in
                    FacetChip(label: facet.rawValue, selected: model.activeFacet == facet)
                        .onTapGesture { model.activeFacet = facet }
                }
            }
            Toggle("Apprentice Mode (Franklin teaches while operating)", isOn: $model.apprenticeModeEnabled)
                .font(.system(size: 11, weight: .semibold))
            TextField("Class-A justification (required for engage/mint/scram/characterization)...", text: $model.classAJustification)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11))
            HStack {
                TextField("Route AI command...", text: $model.routePrompt)
                    .textFieldStyle(.roundedBorder)
                Button("Dispatch") {
                    Task { await model.dispatchRoute() }
                }
                .buttonStyle(.borderedProminent)
            }
            HStack(spacing: 10) {
                Button("Greet + Guide") {
                    model.avatarGreetAndGuide()
                }
                .buttonStyle(.borderedProminent)
                Button(model.avatarAudioInputEnabled ? "Audio On" : "Audio Off") {
                    model.toggleAudioInput()
                }
                .buttonStyle(.bordered)
                Button(model.avatarVisualFocusEnabled ? "Visual On" : "Visual Off") {
                    model.toggleVisualFocus()
                }
                .buttonStyle(.bordered)
                Button(model.avatarRecordingEnabled ? "Recording Engaged" : "Recording Idle") {
                    model.toggleRecording()
                }
                .buttonStyle(.bordered)
            }
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(model.currentFacetLanguageGames()) { game in
                        AvatarLanguageGameChip(game: game) {
                            Task { await model.runLanguageGame(game.id) }
                        }
                    }
                }
            }
            Text("Avatar controls chat/audio/visual/recording. Tap a language game ID to execute through Franklin route.")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(model.lastResult)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(model.lastResult.hasPrefix("REFUSED") ? .red : .primary)
            if !model.lastGuidance.isEmpty {
                Text("Operator guidance: \(model.lastGuidance)")
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
            }
            Text("Signed chat receipts: \(model.utteranceReceipts.count)")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)
            if model.activeFacet == .lithography {
                Divider()
                Text("Lithography Conversation Column")
                    .font(.headline)
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(model.conversationColumn.suffix(10)) { line in
                            VStack(alignment: .leading, spacing: 2) {
                                Text("[\(line.speaker)][\(line.facet.rawValue)]")
                                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                Text(line.message)
                                    .font(.system(size: 10))
                            }
                            .padding(6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.black.opacity(0.04))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
                .frame(height: 120)
            }
            Divider()
            Text("Receipt Tray")
                .font(.headline)
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(model.receipts.suffix(12)) { bubble in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(bubble.terminal)
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(bubble.terminal == "REFUSED" ? .red : .green)
                            Text("Facet: \(bubble.facet.rawValue)")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(.secondary)
                            if let refusalCode = bubble.refusalCode {
                                Text(refusalCode)
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundStyle(.red)
                                    .lineLimit(1)
                            }
                            if let guidance = bubble.operatorGuidance {
                                Text(guidance)
                                    .font(.system(size: 9))
                                    .foregroundStyle(.orange)
                                    .lineLimit(2)
                            }
                            Text(bubble.summary)
                                .font(.system(size: 10))
                                .lineLimit(2)
                            if bubble.facet == .lithography || !bubble.diagnosticChain.isEmpty {
                                Button("Explain This") {
                                    model.explainReceipt(bubble)
                                }
                                .buttonStyle(.bordered)
                                .font(.system(size: 9, weight: .semibold))
                            }
                        }
                        .frame(width: 210, alignment: .leading)
                        .padding(8)
                        .background(.white.opacity(0.36))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
            .frame(height: 92)
            Spacer()
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(FranklinGlass.canvas)
                .overlay(RoundedRectangle(cornerRadius: 24).stroke(.white.opacity(0.2), lineWidth: 1))
        )
        .overlay(
            Group {
                if model.showRefusalBloom {
                    Circle()
                        .fill(Color.red.opacity(0.25))
                        .blur(radius: 20)
                        .transition(.opacity)
                }
            }
        )
        .padding(12)
        .task {
            await model.refreshStatus()
            if !didInitialGuide {
                model.avatarGreetAndGuide()
                didInitialGuide = true
            }
        }
    }
}

private struct FacetChip: View {
    let label: String
    let selected: Bool

    var body: some View {
        Text(label)
            .font(.system(size: 12, weight: .semibold, design: .monospaced))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(selected ? .white.opacity(0.45) : .white.opacity(0.25))
            .clipShape(Capsule())
    }
}

private struct AvatarLanguageGameChip: View {
    let game: AvatarLanguageGame
    let action: () -> Void

    var body: some View {
        Group {
            if game.executable {
                Button(game.id, action: action)
                    .buttonStyle(.borderedProminent)
            } else {
                Button(game.id, action: action)
                    .buttonStyle(.bordered)
                    .disabled(true)
            }
        }
        .font(.system(size: 10, weight: .semibold, design: .monospaced))
        .help("\(game.title) [\(game.scope)]")
    }
}

struct FranklinAvatarStage: View {
    @EnvironmentObject var model: OperatorSurfaceModel
    @State private var pulse: Double = 0
    @StateObject private var avatarRuntime = FranklinAvatarSceneController()

    private var terminalColor: Color {
        model.lastResult.hasPrefix("REFUSED") ? .red : .green
    }

    private var speakingLine: String {
        model.conversationColumn.last?.message ?? "I am present. Route a command and I will answer in-facet."
    }

    private var portraitPath: String {
        let fm = FileManager.default
        var cursor = URL(fileURLWithPath: fm.currentDirectoryPath, isDirectory: true)
        for _ in 0..<10 {
            let candidate = cursor.appendingPathComponent("cells/franklin/avatar/build/reality/Franklin_preview.png")
            if fm.fileExists(atPath: candidate.path) { return candidate.path }
            cursor.deleteLastPathComponent()
        }
        return ""
    }

    var body: some View {
        HStack(spacing: 18) {
            ZStack {
                RoundedRectangle(cornerRadius: 24)
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.36), terminalColor.opacity(0.18)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                FranklinAvatarRuntimeView(controller: avatarRuntime)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .padding(12)
                FranklinPortraitFallbackView(imagePath: portraitPath)
                    .padding(12)
                    .allowsHitTesting(false)
                    .opacity(avatarRuntime.bridgeVersion == "unavailable" ? 1.0 : 0.35)
                Circle()
                    .stroke(terminalColor.opacity(0.55), lineWidth: 2)
                    .frame(width: 166, height: 166)
                    .scaleEffect(1 + (sin(pulse) * 0.02))
            }
            .frame(width: 220, height: 190)

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text("Ben Franklin Avatar")
                        .font(.headline.weight(.semibold))
                    Text(model.lastResult.hasPrefix("REFUSED") ? "REFUSAL" : "TEMPERATE")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(terminalColor.opacity(0.20))
                        .clipShape(Capsule())
                }
                Text("Facet: \(model.activeFacet.rawValue) · Lifelike AI presence linked to vQbit receipts")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
                Text("Bridge: \(avatarRuntime.bridgeVersion) · Viseme: \(avatarRuntime.activeViseme)")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
                if avatarRuntime.bridgeVersion == "unavailable" {
                    Text("REFUSED: bridge unavailable, running mesh fallback projection")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(.red)
                }
                Text("Rig: v=\(avatarRuntime.assetBinding.visemeCount) e=\(avatarRuntime.assetBinding.expressionCount) p=\(avatarRuntime.assetBinding.postureCount)")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
                if !avatarRuntime.assetBinding.passyAssetSetReady {
                    Text("REFUSED: required Passy asset set missing")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(.red)
                }
                if !avatarRuntime.assetBinding.meshLoaded {
                    Text("REFUSED: missing Passy mesh asset at \(avatarRuntime.assetBinding.meshAssetPath)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
                if !avatarRuntime.assetBinding.missingAssets.isEmpty {
                    Text(avatarRuntime.assetBinding.missingAssets.prefix(2).joined(separator: " | "))
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.red)
                        .lineLimit(3)
                }
                Text(speakingLine)
                    .font(.system(size: 13))
                    .lineLimit(4)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white.opacity(0.30))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 210)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(FranklinGlass.canvas)
                .overlay(RoundedRectangle(cornerRadius: 24).stroke(.white.opacity(0.28), lineWidth: 1))
        )
        .task {
            while true {
                pulse += 0.9
                avatarRuntime.apply(posture: postureState())
                avatarRuntime.updateSpeech(text: speakingLine)
                try? await Task.sleep(for: .milliseconds(34))
            }
        }
    }

    private func postureState() -> FranklinAvatarPosture {
        if model.lastResult.hasPrefix("REFUSED") { return .refusing }
        if model.avatarIsRecording { return .recording }
        if model.avatarIsSpeaking { return .speaking }
        if model.avatarIsListening { return .listening }
        return .idle
    }
}
