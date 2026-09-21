import Testing
@testable import Omnomnom

struct UserAgentTests {
    @Test func carriesNameVersionAndContactURL() {
        #expect(UserAgent.string(appVersion: "0.1") == "Omnomnom/0.1 (https://github.com/j23n/omnomnom)")
        #expect(UserAgent.string(appVersion: " 1.2.3 ") == "Omnomnom/1.2.3 (https://github.com/j23n/omnomnom)")
    }

    @Test func unknownVersionIsLeftOut() {
        #expect(UserAgent.string(appVersion: nil) == "Omnomnom (https://github.com/j23n/omnomnom)")
        #expect(UserAgent.string(appVersion: "  ") == "Omnomnom (https://github.com/j23n/omnomnom)")
    }

    @Test func contactURLIsTheRepository() {
        #expect(UserAgent.contactURL == "https://github.com/j23n/omnomnom")
    }
}
