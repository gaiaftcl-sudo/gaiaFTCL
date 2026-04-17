import Foundation

public extension Bundle {
    static var gaiaFusionResourceBundle: Bundle {
        // 1. Check if it's inside an .app bundle (Contents/Resources/GaiaFusion_GaiaFusion.bundle)
        if let url = Bundle.main.url(forResource: "GaiaFusion_GaiaFusion", withExtension: "bundle"),
           let bundle = Bundle(url: url) {
            return bundle
        }
        
        // 2. Check if we are running tests or from .build directory (where Bundle.module works)
        // We use a safe check to avoid the fatalError in Bundle.module
        let mainPath = Bundle.main.bundleURL.appendingPathComponent("GaiaFusion_GaiaFusion.bundle").path
        if FileManager.default.fileExists(atPath: mainPath), let bundle = Bundle(path: mainPath) {
            return bundle
        }
        
        // Fallback to Bundle.main
        return Bundle.main
    }
}
