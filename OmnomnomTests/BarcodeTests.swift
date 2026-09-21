import Testing
@testable import Omnomnom

struct BarcodeTests {
    @Test func validCodesPassInCanonicalForm() {
        #expect(Barcode.normalize("4006381333931") == "4006381333931")
        #expect(Barcode.normalize("96385074") == "96385074")
        #expect(Barcode.normalize("036000291452") == "0036000291452")
        #expect(Barcode.normalize(" 4006381333931\n") == "4006381333931")
    }

    @Test func wrongCheckDigitsAreRejected() {
        #expect(Barcode.normalize("4006381333932") == nil)
        #expect(Barcode.normalize("96385075") == nil)
        #expect(Barcode.normalize("036000291453") == nil)
    }

    @Test func nonDigitsAndOddLengthsAreRejected() {
        #expect(Barcode.normalize("") == nil)
        #expect(Barcode.normalize("4006381333931a") == nil)
        #expect(Barcode.normalize("4006 381 333931") == nil)
        #expect(Barcode.normalize("12345") == nil)
        #expect(Barcode.normalize("40063813339310") == nil)
        #expect(Barcode.normalize("٤٠٠٦٣٨١٣٣٣٩٣١") == nil)
    }

    @Test func upcEExpandsToUPCAAsThirteenDigits() {
        #expect(Barcode.expandUPCE("04252614") == "0042100005264")
        #expect(Barcode.expandUPCE("0425261") == "0042100005264")
        #expect(Barcode.expandUPCE("425261") == "0042100005264")
        #expect(Barcode.normalize("04252614") == "0042100005264")
        #expect(Barcode.normalize("425261") == "0042100005264")
    }

    @Test func upcEExpansionCoversEveryLastDigitPattern() {
        #expect(Barcode.expandUPCE("123450") == "0012000003455")
        #expect(Barcode.expandUPCE("123453") == "0012300000451")
        #expect(Barcode.expandUPCE("123454") == "0012340000053")
        #expect(Barcode.expandUPCE("123457") == "0012345000072")
    }

    @Test func upcEWithWrongCheckDigitOrNumberSystemIsRejected() {
        #expect(Barcode.expandUPCE("04252615") == nil)
        #expect(Barcode.expandUPCE("24252614") == nil)
        #expect(Barcode.expandUPCE("2425261") == nil)
        #expect(Barcode.expandUPCE("12345") == nil)
        #expect(Barcode.expandUPCE("4006381333931") == nil)
        #expect(Barcode.expandUPCE("42526x") == nil)
    }

    @Test func eightDigitsReadAsEAN8WhenTheirCheckDigitHolds() {
        #expect(Barcode.normalize("01234565") == "01234565")
    }

    @Test func checkDigitFollowsGS1Weights() {
        #expect(Barcode.checkDigit(for: [4, 0, 0, 6, 3, 8, 1, 3, 3, 3, 9, 3]) == 1)
        #expect(Barcode.checkDigit(for: [9, 6, 3, 8, 5, 0, 7]) == 4)
        #expect(Barcode.checkDigit(for: [0, 3, 6, 0, 0, 0, 2, 9, 1, 4, 5]) == 2)
        #expect(Barcode.checkDigit(for: []) == 0)
        #expect(Barcode.hasValidCheckDigit([9, 6, 3, 8, 5, 0, 7, 4]))
        #expect(!Barcode.hasValidCheckDigit([9, 6, 3, 8, 5, 0, 7, 5]))
        #expect(!Barcode.hasValidCheckDigit([]))
    }
}
