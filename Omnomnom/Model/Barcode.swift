import Foundation

/// GS1 barcode validation and normalisation for the scanner and the manual field.
///
/// Accepts EAN-8, UPC-A, EAN-13 and UPC-E payloads and returns the form Open Food
/// Facts indexes by: 8 digits for EAN-8, 13 for everything else (UPC-A gets a leading
/// 0; UPC-E is expanded to UPC-A first). The check digit is verified in every case, so
/// a misread from the camera or a typo never reaches the network.
nonisolated enum Barcode {
    /// The canonical code, or `nil` when `raw` is not all digits, has an unexpected
    /// length or fails its check digit. An 8-digit payload is read as EAN-8 when its
    /// check digit holds and as UPC-E otherwise; a scanner that knows the symbology
    /// calls `expandUPCE` directly.
    static func normalize(_ raw: String) -> String? {
        guard let digits = digitValues(raw) else { return nil }
        switch digits.count {
        case 8:
            return hasValidCheckDigit(digits) ? string(digits) : expandUPCE(raw)
        case 12:
            return hasValidCheckDigit(digits) ? "0" + string(digits) : nil
        case 13:
            return hasValidCheckDigit(digits) ? string(digits) : nil
        case 6, 7:
            return expandUPCE(raw)
        default:
            return nil
        }
    }

    /// Expands a UPC-E payload (6 digits, 7 with the number system, or 8 with the check
    /// digit too) to UPC-A and returns it as 13 digits, or `nil` when the number system
    /// is not 0 or 1 or a supplied check digit does not match the expansion.
    static func expandUPCE(_ raw: String) -> String? {
        guard let digits = digitValues(raw) else { return nil }
        let numberSystem: Int
        let x: [Int]
        let givenCheck: Int?
        switch digits.count {
        case 6:
            numberSystem = 0
            x = digits
            givenCheck = nil
        case 7:
            numberSystem = digits[0]
            x = Array(digits[1...6])
            givenCheck = nil
        case 8:
            numberSystem = digits[0]
            x = Array(digits[1...6])
            givenCheck = digits[7]
        default:
            return nil
        }
        guard numberSystem == 0 || numberSystem == 1 else { return nil }
        let middle: [Int]
        switch x[5] {
        case 0, 1, 2: middle = [x[0], x[1], x[5], 0, 0, 0, 0, x[2], x[3], x[4]]
        case 3: middle = [x[0], x[1], x[2], 0, 0, 0, 0, 0, x[3], x[4]]
        case 4: middle = [x[0], x[1], x[2], x[3], 0, 0, 0, 0, 0, x[4]]
        default: middle = [x[0], x[1], x[2], x[3], x[4], 0, 0, 0, 0, x[5]]
        }
        let upcA = [numberSystem] + middle
        let check = checkDigit(for: upcA)
        if let givenCheck, givenCheck != check { return nil }
        return "0" + string(upcA + [check])
    }

    /// The GS1 modulo-10 check digit for `digits`, which exclude it: weights alternate
    /// 3 and 1 from the right, and the digit brings the sum to a multiple of ten.
    static func checkDigit(for digits: [Int]) -> Int {
        var sum = 0
        for (offset, digit) in digits.reversed().enumerated() {
            sum += digit * (offset.isMultiple(of: 2) ? 3 : 1)
        }
        return (10 - sum % 10) % 10
    }

    /// Whether the last digit is the check digit of the ones before it.
    static func hasValidCheckDigit(_ digits: [Int]) -> Bool {
        guard let last = digits.last else { return false }
        return checkDigit(for: Array(digits.dropLast())) == last
    }

    /// The ASCII digits of `raw` after trimming, or `nil` if anything else is in it.
    private static func digitValues(_ raw: String) -> [Int]? {
        var digits: [Int] = []
        for character in raw.trimmingCharacters(in: .whitespacesAndNewlines) {
            guard character.isASCII, let value = character.wholeNumberValue else { return nil }
            digits.append(value)
        }
        return digits
    }

    private static func string(_ digits: [Int]) -> String {
        digits.map(String.init).joined()
    }
}
