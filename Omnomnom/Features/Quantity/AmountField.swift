import SwiftUI

/// The unit an `AmountField` collects: the food's own, grams or millilitres, or
/// servings for a recipe. One `FoodMeasure` is the single source of a food's unit text,
/// so the field, its hint and its VoiceOver label can never disagree.
nonisolated enum AmountUnit: Hashable, Sendable {
    case food(FoodMeasure)
    case servings

    /// The unit of what is being logged: servings for a recipe, else the food's own.
    init(choice: FoodChoice) {
        self = choice.isRecipe ? .servings : .food(choice.measure)
    }

    /// Shown after the field.
    var symbol: String {
        switch self {
        case .food(let measure): measure.unitSymbol
        case .servings: "servings"
        }
    }

    /// VoiceOver label for the field.
    var accessibilityLabel: String {
        switch self {
        case .food(let measure): measure.displayName
        case .servings: "Servings"
        }
    }

    /// The unit's name as VoiceOver should read it after the typed number.
    var spokenName: String {
        switch self {
        case .food(let measure): measure.spokenName
        case .servings: "servings"
        }
    }

    /// The typed amount, or `nil` when it is empty, not a number or out of range. The
    /// bounds are the same for grams and millilitres: they bound an amount, not a mass.
    func parse(_ text: String) -> Double? {
        switch self {
        case .food: Formatters.parseAmount(text)
        case .servings: Formatters.parseServings(text)
        }
    }

    /// "0.1 and 5000 g", for the inline hint when the text is out of range.
    var rangeText: String {
        switch self {
        case .food(let measure): Formatters.amountRangeText(measure: measure)
        case .servings: Formatters.servingsRangeText
        }
    }
}

/// The canonical amount field: decimal pad, one unit, VoiceOver reads the unit. The
/// whole text is selected whenever the field gains focus, so typing over a prefilled
/// amount replaces it while Log still uses it untouched. The unit sits beside the
/// field, and below it at accessibility sizes, where the two no longer share a line.
struct AmountField: View {
    @Binding var text: String
    let unit: AmountUnit
    var isFocused: FocusState<Bool>.Binding

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var selection: TextSelection?

    /// One field whichever way the pair is laid out, so focus and the keyboard survive
    /// a change of type size; `ViewThatFits` would give the field two identities.
    private var layout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .trailing, spacing: 4))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))
    }

    /// The selection as the field may see it: `nil` once its indices no longer fit the
    /// text, as after a chip replaces a typed amount with a shorter one, since a stale
    /// `String.Index` handed back to the field traps.
    private var validSelection: Binding<TextSelection?> {
        Binding(
            get: { selection.flatMap { Self.fits($0, in: text) ? $0 : nil } },
            set: { selection = $0 }
        )
    }

    var body: some View {
        layout {
            TextField("0", text: $text, selection: validSelection)
                .keyboardType(.decimalPad)
                .font(.largeTitle.weight(.semibold))
                .multilineTextAlignment(.trailing)
                .focused(isFocused)
                .accessibilityLabel(unit.accessibilityLabel)
                .accessibilityValue(text.isEmpty ? "no amount" : "\(text) \(unit.spokenName)")
            Text(unit.symbol)
                .font(.title2)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
        .onChange(of: isFocused.wrappedValue) { _, focused in
            if focused {
                selectAll()
            }
        }
        .onChange(of: text) { _, newText in
            if let selection, !Self.fits(selection, in: newText) {
                self.selection = nil
            }
        }
    }

    private func selectAll() {
        guard !text.isEmpty else { return }
        selection = TextSelection(range: text.startIndex..<text.endIndex)
    }

    /// Whether every index of `selection` lies within `text`.
    private static func fits(_ selection: TextSelection, in text: String) -> Bool {
        switch selection.indices {
        case .selection(let range):
            return range.upperBound <= text.endIndex
        case .multiSelection(let ranges):
            return ranges.ranges.allSatisfy { $0.upperBound <= text.endIndex }
        @unknown default:
            return false
        }
    }
}
