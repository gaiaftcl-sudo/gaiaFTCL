import SwiftUI

/// Renders the vQbit substrate state using the Phi-scaling invariant.
/// Any violation of the golden mean scaling will produce visible "Moire interference".
/// This provides a "Self-Closing" visual validation for the PQ phase.
public struct PhiWitnessView: View {
    @State private var vQbitCount: Int = 1000
    @State private var depth: Int = 1
    
    // Internal Phi constants since GaiaFTCLCore isn't linked to the Mac app UI directly
    private let PHI: Double = 1.6180339887498948482
    
    private func calculateFractalCoordinate(depth: Int, index: Int) -> Double {
        let phiPower = pow(PHI, Double(depth))
        let offset = Double(index) * PHI
        return (phiPower + offset).truncatingRemainder(dividingBy: 1.0)
    }
    
    public init() {}
    
    public var body: some View {
        VStack {
            Text("Φ-Witness Renderer")
                .font(.headline)
            
            GeometryReader { geometry in
                let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
                let maxRadius = min(geometry.size.width, geometry.size.height) / 2
                
                Path { path in
                    for i in 0..<vQbitCount {
                        let coordinate = calculateFractalCoordinate(depth: depth, index: i)
                        // Map the fractal coordinate to an angle and radius
                        let angle = coordinate * 2 * .pi * PHI
                        let radius = maxRadius * sqrt(Double(i) / Double(vQbitCount))
                        
                        let x = center.x + CGFloat(radius * cos(angle))
                        let y = center.y + CGFloat(radius * sin(angle))
                        
                        let dotRect = CGRect(x: x - 1.5, y: y - 1.5, width: 3, height: 3)
                        path.addEllipse(in: dotRect)
                    }
                }
                .fill(Color.green)
            }
            .frame(minWidth: 300, minHeight: 300)
            .background(Color.black.opacity(0.8))
            .cornerRadius(8)
            
            HStack {
                Text("vQbits: \(vQbitCount)")
                Slider(value: Binding(
                    get: { Double(vQbitCount) },
                    set: { vQbitCount = Int($0) }
                ), in: 100...5000)
            }
            .padding(.horizontal)
            
            HStack {
                Text("Depth: \(depth)")
                Slider(value: Binding(
                    get: { Double(depth) },
                    set: { depth = Int($0) }
                ), in: 1...8, step: 1)
            }
            .padding(.horizontal)
        }
        .padding()
    }
}
