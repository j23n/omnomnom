import Testing
@testable import Omnomnom

/// Mass and volume are carried side by side and never mixed. The text is what a row,
/// a footer and the Quantity sheet all print, so it is pinned here.
struct RawAmountTests {
    @Test func oneMeasureFillsOnePartAndLeavesTheOtherAtZero() {
        let mass = RawAmount(450, measure: .mass)
        #expect(mass.grams == 450)
        #expect(mass.millilitres == 0)
        #expect(mass.amount(in: .mass) == 450)
        #expect(mass.amount(in: .volume) == 0)

        let volume = RawAmount(250, measure: .volume)
        #expect(volume.grams == 0)
        #expect(volume.millilitres == 250)
        #expect(volume.amount(in: .volume) == 250)
    }

    @Test func emptyOnlyWhenNeitherPartHoldsAnything() {
        #expect(RawAmount.zero.isEmpty)
        #expect(RawAmount(0, measure: .volume).isEmpty)
        #expect(!RawAmount(0.1, measure: .volume).isEmpty)
        #expect(!RawAmount(grams: 300, millilitres: 150).isEmpty)
    }

    @Test func addingAndScalingKeepThePartsApart() {
        let sum = RawAmount(grams: 300) + RawAmount(millilitres: 150) + RawAmount(grams: 50)
        #expect(sum.grams == 350)
        #expect(sum.millilitres == 150)

        let doubled = sum * 2
        #expect(doubled.grams == 700)
        #expect(doubled.millilitres == 300)
        #expect((sum * 0).isEmpty)
    }

    @Test func textNamesOnlyThePartsThatAreThere() {
        #expect(RawAmount(grams: 450).text == "450 g")
        #expect(RawAmount(millilitres: 450).text == "450 ml")
        #expect(RawAmount(grams: 300, millilitres: 150).text == "300 g + 150 ml")
    }

    /// Nothing counted has no unit to be counted in, so it reads blank rather than
    /// claiming a mass of zero: an all-volume recipe with nothing typed is not 0 g.
    @Test func nothingCountedReadsBlank() {
        #expect(RawAmount.zero.text == "")
        #expect(RawAmount.zero.wholeText == "")
        #expect((RawAmount(millilitres: 450) * 0).text == "")
    }

    @Test func wholeTextRoundsEveryPartToTheUnit() {
        #expect(RawAmount(grams: 350.6).wholeText == "351 g")
        #expect(RawAmount(grams: 233.75, millilitres: 99.5).wholeText == "234 g + 100 ml")
        #expect(RawAmount(millilitres: 249.5).wholeText == "250 ml")
    }
}
