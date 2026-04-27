import SwiftUI
import FranklinUIKit

struct CanvasView: View {
    @EnvironmentObject var model: OperatorSurfaceModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
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
                    Text(facet.rawValue)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(model.activeFacet == facet ? .white.opacity(0.45) : .white.opacity(0.25))
                        .clipShape(Capsule())
                        .onTapGesture {
                            model.activeFacet = facet
                        }
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
        .task { await model.refreshStatus() }
    }
}
