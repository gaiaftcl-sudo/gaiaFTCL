import Foundation

// Provides realityKitContentBundle when the RealityKitContent module from an
// Xcode project template is absent (e.g. plain `swift build`).
// The Xcode app target supplies the real bundle via the RealityKitContent package.
#if !canImport(RealityKitContent)
public var realityKitContentBundle: Bundle { .main }
#endif
