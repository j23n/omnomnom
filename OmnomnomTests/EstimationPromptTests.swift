import Testing
@testable import Omnomnom

/// The instructions carry the rules the plan asks for, and the prompts embed the
/// description without ever putting it in the instructions.
struct EstimationPromptTests {
    @Test func instructionsStateTheKeyRules() {
        let text = EstimationPrompt.instructions
        #expect(text.contains("food log"))
        #expect(text.contains("conservative"))
        #expect(text.contains("portion that was eaten"))
        #expect(text.contains("not per 100 g"))
        #expect(text.contains("sodium in milligrams"))
        #expect(text.contains("unsure"))
        #expect(text.contains("Never give advice"))
    }

    @Test func textPromptQuotesTheDescription() {
        let prompt = EstimationPrompt.text(description: "two scrambled eggs and a slice of rye toast")
        #expect(prompt.contains("\"two scrambled eggs and a slice of rye toast\""))
        #expect(prompt.hasPrefix("Estimate the nutrition of this meal"))
    }

    @Test func photoPromptMentionsThePhotoAndOptionalHint() {
        let bare = EstimationPrompt.photoText(description: nil)
        #expect(bare.contains("attached photo"))
        #expect(!bare.contains("says:"))
        #expect(EstimationPrompt.photoText(description: "   ") == bare)
        let hinted = EstimationPrompt.photoText(description: "half of it was left")
        #expect(hinted.hasPrefix(bare))
        #expect(hinted.contains("says: \"half of it was left\""))
    }

    @Test func descriptionIsTrimmedCollapsedAndCapped() {
        #expect(EstimationPrompt.clean("  eggs \n\n toast  ") == "eggs toast")
        let long = String(repeating: "a", count: 800)
        #expect(EstimationPrompt.clean(long).count == EstimationPrompt.maximumDescriptionLength)
        #expect(EstimationPrompt.text(description: long).count < 800)
    }
}
