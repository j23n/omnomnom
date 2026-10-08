import Foundation

/// How much of something, as a step rather than a number.
///
/// The gram field is the most expensive thing in logging and it buys a precision the
/// overview never spends: day totals read as a weekly mean tolerate twenty per cent on
/// a single item without the line moving. So the question stops being "how many grams"
/// and becomes "about as usual, or not".
///
/// The multipliers are geometric about 1, which keeps "less" then "more" from landing
/// back where it started, and they live here alone because they are a tuning decision
/// rather than a fact.
///
/// What a bucket multiplies is the point, and it is the caller's business: see
/// `AmountReference`. On a food with history that is what this person last ate, which is
/// why "usual" is a true word there. On a food eaten for the first time there is nothing
/// to multiply and buckets are not offered at all.
nonisolated enum AmountBucket: String, CaseIterable, Hashable, Sendable {
    case less
    case usual
    case more
    case double

    var multiplier: Double {
        switch self {
        case .less: 0.7
        case .usual: 1
        case .more: 1.4
        case .double: 2
        }
    }

    /// Shown on the control. Deliberately not a figure: the resolved amount is shown
    /// beside it, so the step and the number it came to are both visible.
    var label: String {
        switch self {
        case .less: "Less"
        case .usual: "Usual"
        case .more: "More"
        case .double: "Double"
        }
    }

    /// The amount this bucket comes to against a reference, rounded to something a
    /// person would recognise rather than to the arithmetic.
    func amount(of reference: Double) -> Double {
        let scaled = reference * multiplier
        guard scaled > 0 else { return 0 }
        // To 5 below 100, to 10 above: 0.7 x 180 g reads as 130 g rather than 126 g,
        // and 0.7 x 40 g as 30 g rather than 28 g.
        let step: Double = scaled < 100 ? 5 : 10
        return (scaled / step).rounded() * step
    }
}
