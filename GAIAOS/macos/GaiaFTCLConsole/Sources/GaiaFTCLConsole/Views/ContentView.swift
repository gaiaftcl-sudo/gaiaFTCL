import SwiftUI
import SwiftTerm

struct ContentView: View {
    @State private var selectedTab = 0
    @State private var showTestRobot = false
    @State private var showInvariants = false
    
    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $selectedTab) {
                FusionView().tabItem { Text("Fusion") }.tag(0)
                HealthView().tabItem { Text("Health") }.tag(1)
                MeshView().tabItem { Text("Mesh") }.tag(2)
                GatesView().tabItem { Text("Gates") }.tag(3)
                EvidenceView().tabItem { Text("Evidence") }.tag(4)
                InvariantsView().tabItem { Text("Invariants") }.tag(5)
            }
            .padding()
            
            Divider()
            
            TerminalViewWrapper()
                .frame(height: 200)
            
            TerminalStateBar()
        }
        .toolbar {
            ToolbarItem {
                Button(action: { showTestRobot.toggle() }) {
                    Image(systemName: "wrench.and.screwdriver")
                }
                .keyboardShortcut("t", modifiers: .command)
            }
            ToolbarItem {
                Button(action: { showInvariants.toggle() }) {
                    Image(systemName: "list.bullet.clipboard")
                }
                .keyboardShortcut("i", modifiers: .command)
            }
        }
        .sheet(isPresented: $showTestRobot) {
            TestRobotPanel()
                .frame(minWidth: 600, minHeight: 400)
        }
        .sheet(isPresented: $showInvariants) {
            InvariantsPanel()
                .frame(minWidth: 600, minHeight: 400)
        }
    }
}

// Stubs for tabs
struct FusionView: View { var body: some View { Text("Fusion Tab") } }
struct HealthView: View { var body: some View { Text("Health Tab") } }
struct MeshView: View { var body: some View { Text("Mesh Tab") } }
struct GatesView: View { var body: some View { Text("Gates Tab") } }
struct EvidenceView: View { var body: some View { Text("Evidence Tab") } }
struct InvariantsView: View { var body: some View { Text("Invariants Tab") } }

// Stub for Terminal
struct TerminalViewWrapper: NSViewRepresentable {
    func makeNSView(context: Context) -> LocalProcessTerminalView {
        let terminal = LocalProcessTerminalView(frame: .zero)
        terminal.startProcess(executable: "/bin/zsh")
        return terminal
    }
    
    func updateNSView(_ nsView: LocalProcessTerminalView, context: Context) {}
}

// Stub for State Bar
struct TerminalStateBar: View {
    var body: some View {
        HStack {
            Text("[CALORIE: 0]")
            Text("[CURE: 0]")
            Text("[REFUSED: 0]")
            Spacer()
        }
        .padding(4)
        .background(Color.gray.opacity(0.2))
    }
}

// Stubs for Panels
struct TestRobotPanel: View { var body: some View { Text("TestRobot Panel") } }

struct InvariantsPanel: View {
    var body: some View {
        HStack {
            List {
                Text("OWL-NEURO-INV1-CONSTITUTIVE")
                Text("OWL-NEURO-INV2-ESCAPEE")
                Text("OWL-NEURO-INV3-STEROID")
                Text("OWL-NEURO-CONST-001-FETAL-CLOSURE")
                Text("GFTCL-OWL-INV-001")
                Text("GFTCL-PINEAL-001")
            }
            .frame(width: 250)
            
            VStack {
                Text("Invariant Editor")
                    .font(.headline)
                TextEditor(text: .constant("{\n  \"status\": \"CURE-PROXY\"\n}"))
                    .font(.system(.body, design: .monospaced))
                Button("Run Harness") {
                    // Types gaiaftcl health invariant run-harness <id> into SwiftTerm
                }
            }
            .padding()
        }
    }
}
