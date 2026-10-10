import FoundationModels

// The app is built with Xcode 27 against the iOS 27 SDK, and builds with Xcode 26 too, as CI
// does until the hosted runners have Xcode 27. The two SDKs differ in a few places, and code
// that needs Xcode 27's is under `#if compiler(>=6.4)`, Xcode 27's Swift: the photograph
// attached to an on-device prompt (`PhotoPrompt`), the framework's newer error
// (`EstimationError`) and the Health query for a time-limited authorization window
// (`HealthStore+Observing`). An Xcode 26 build behaves as the app does on iOS 26 there.

nonisolated extension GenerationOptions {
    /// Greedy sampling: the same answer for the same prompt. The initializer's label differs
    /// between the iOS 26 and iOS 27 SDKs.
    static var greedy: GenerationOptions {
        #if compiler(>=6.4)
        GenerationOptions(samplingMode: .greedy)
        #else
        GenerationOptions(sampling: .greedy)
        #endif
    }
}
