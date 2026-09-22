import Foundation

/// A raw amount with its mass and its volume kept apart: 450 g, 450 ml, or 300 g and
/// 150 ml at once, which is what a recipe mixing a solid and a liquid comes to.
///
/// The two parts are never added together and never converted into each other, because
/// the app does not know a food's density. A dish of 300 g of lentils and 150 ml of
/// stock weighs 300 g and measures 150 ml, and says exactly that. Nutrition is not
/// affected: a serving is the same fraction of the whole dish either way.
nonisolated struct RawAmount: Hashable, Sendable {
    var grams: Double
    var millilitres: Double

    init(grams: Double = 0, millilitres: Double = 0) {
        self.grams = grams
        self.millilitres = millilitres
    }

    /// `amount` counted under `measure`, with the other part left at zero.
    init(_ amount: Double, measure: FoodMeasure) {
        switch measure {
        case .mass: self.init(grams: amount, millilitres: 0)
        case .volume: self.init(grams: 0, millilitres: amount)
        }
    }

    /// Nothing counted under either measure.
    static let zero = RawAmount()

    /// Whether neither part holds anything to show or to scale.
    var isEmpty: Bool {
        grams <= 0 && millilitres <= 0
    }

    /// The part counted under `measure`, which is all a single-unit food ever has.
    func amount(in measure: FoodMeasure) -> Double {
        switch measure {
        case .mass: grams
        case .volume: millilitres
        }
    }

    /// "450 g", "450 ml" or "300 g + 150 ml"; empty when nothing is counted, since a
    /// zero would have to name a unit and there is none to name.
    var text: String {
        joined { Formatters.amount($0, measure: $1) }
    }

    /// The same rounded to whole units, for captions where a decimal adds nothing.
    var wholeText: String {
        joined { Formatters.wholeAmount($0, measure: $1) }
    }

    static func + (lhs: RawAmount, rhs: RawAmount) -> RawAmount {
        RawAmount(grams: lhs.grams + rhs.grams, millilitres: lhs.millilitres + rhs.millilitres)
    }

    static func * (lhs: RawAmount, rhs: Double) -> RawAmount {
        RawAmount(grams: lhs.grams * rhs, millilitres: lhs.millilitres * rhs)
    }

    /// The parts that hold something, mass first, joined plainly. An empty amount reads
    /// blank rather than "0 g": a recipe of nothing but stock has no mass, and printing
    /// one in grams would name the unit it is not counted in. Callers that need a value
    /// to show check `isEmpty` first.
    private func joined(_ format: (Double, FoodMeasure) -> String) -> String {
        var parts: [String] = []
        if grams > 0 {
            parts.append(format(grams, .mass))
        }
        if millilitres > 0 {
            parts.append(format(millilitres, .volume))
        }
        return parts.joined(separator: " + ")
    }
}
