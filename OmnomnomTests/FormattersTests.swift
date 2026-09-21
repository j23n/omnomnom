import Testing
@testable import Omnomnom

struct FormattersTests {
    @Test func parseGramsAcceptsCommaAndTrimsWhitespace() {
        #expect(Formatters.parseGrams(" 62,5 ") == 62.5)
        #expect(Formatters.parseGrams("182") == 182)
    }

    @Test func parseGramsRejectsGarbageAndOutOfRange() {
        #expect(Formatters.parseGrams("") == nil)
        #expect(Formatters.parseGrams("abc") == nil)
        #expect(Formatters.parseGrams("0") == nil)
        #expect(Formatters.parseGrams("0.05") == nil)
        #expect(Formatters.parseGrams("5000.1") == nil)
        #expect(Formatters.parseGrams("inf") == nil)
        #expect(Formatters.parseGrams("0.1") == 0.1)
        #expect(Formatters.parseGrams("5000") == 5000)
    }
}
