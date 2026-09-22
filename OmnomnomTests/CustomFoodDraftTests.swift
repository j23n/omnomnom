import Foundation
import Testing
@testable import Omnomnom

struct CustomFoodDraftTests {
    @Test func energyIsRequiredAndBlanksStayUnknown() {
        var draft = CustomFoodDraft()
        draft.name = "Granola"
        #expect(draft.per100g == nil)
        #expect(!draft.isValid)
        draft.setText("450", for: .energy)
        #expect(draft.isValid)
        #expect(draft.per100g?.energy == 450)
        #expect(draft.per100g?.protein == nil)
    }

    @Test func aFieldThatDoesNotParseBlocksSaving() {
        var draft = CustomFoodDraft()
        draft.name = "Granola"
        draft.setText("450", for: .energy)
        draft.setText("lots", for: .sugar)
        #expect(draft.per100g == nil)
        #expect(draft.isInvalid(.sugar))
        #expect(!draft.isInvalid(.energy))
        #expect(!draft.isInvalid(.fiber))
        draft.setText("12,5", for: .sugar)
        #expect(draft.per100g?.sugar == 12.5)
    }

    @Test func prefillRoundTripsStoredValues() {
        let stored = Nutrition(energy: 389, protein: 16.9, fiber: 10.6, sodium: 2)
        let draft = CustomFoodDraft(name: "Oats", per100g: stored)
        #expect(draft.text(for: .energy) == "389")
        #expect(draft.text(for: .sodium) == "2")
        #expect(draft.text(for: .sugar) == "")
        #expect(draft.per100g == stored)
        #expect(draft.isValid)
    }

    @Test func prefillCarriesThePhotoAndANewDraftHasNone() {
        #expect(CustomFoodDraft().photo == nil)
        let photo = Data([0xFF, 0xD8, 0x02])
        var draft = CustomFoodDraft(name: "Oats", per100g: Nutrition(energy: 389), photo: photo)
        #expect(draft.photo == photo)
        #expect(draft.isValid)
        draft.photo = nil
        #expect(draft.photo == nil)
        #expect(draft.isValid)
    }

    @Test func nameMustNotBeBlank() {
        var draft = CustomFoodDraft()
        draft.setText("100", for: .energy)
        draft.name = "   "
        #expect(!draft.isValid)
    }
}
