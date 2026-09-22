import Testing
@testable import Omnomnom

struct AppVersionTests {
    @Test func versionAndBuildAreBothShown() {
        #expect(AppVersion.string(version: "0.1", build: "1") == "Version 0.1 (1)")
        #expect(AppVersion.string(version: " 1.2.3 ", build: " 42 ") == "Version 1.2.3 (42)")
    }

    @Test func missingBuildIsLeftOut() {
        #expect(AppVersion.string(version: "0.1", build: nil) == "Version 0.1")
        #expect(AppVersion.string(version: "0.1", build: "  ") == "Version 0.1")
    }

    @Test func missingVersionReadsUnknown() {
        #expect(AppVersion.string(version: nil, build: "1") == "Version unknown")
        #expect(AppVersion.string(version: "", build: nil) == "Version unknown")
    }
}
