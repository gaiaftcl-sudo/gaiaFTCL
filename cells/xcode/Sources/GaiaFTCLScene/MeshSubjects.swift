import Foundation
import GaiaGateKit

public enum MeshSubjects {
    public static let macCellID: String = GaiaCellIdentity.uuid.uuidString
    public static let all = "gaiaftcl.>"

    public static func vqbit(domain: String, cellID: String) -> String {
        "gaiaftcl.\(domain.lowercased()).vqbit.\(cellID)"
    }
}
