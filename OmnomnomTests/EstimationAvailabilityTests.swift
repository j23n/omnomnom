import Testing
@testable import Omnomnom

/// Every state has its own sentence and says whether a photo can go along.
struct EstimationAvailabilityTests {
    @Test func availableStatesSayWhetherPhotosWork() {
        let withPhoto = EstimationAvailability.available(photo: true)
        #expect(withPhoto.isAvailable)
        #expect(withPhoto.supportsPhoto)
        #expect(withPhoto.message.contains("photo"))
        let textOnly = EstimationAvailability.available(photo: false)
        #expect(textOnly.isAvailable)
        #expect(!textOnly.supportsPhoto)
        #expect(textOnly.message.contains("iOS 27"))
    }

    @Test func unavailableStatesExplainThemselves() {
        #expect(EstimationAvailability.deviceNotEligible.message.contains("does not support Apple Intelligence"))
        #expect(EstimationAvailability.appleIntelligenceNotEnabled.message.contains("Turn on Apple Intelligence"))
        #expect(EstimationAvailability.modelNotReady.message.contains("not ready"))
        #expect(EstimationAvailability.unavailable("region").message.hasSuffix("region"))
    }

    @Test func unavailableStatesNeverOfferAPhoto() {
        let states: [EstimationAvailability] = [.deviceNotEligible, .appleIntelligenceNotEnabled, .modelNotReady, .unavailable("x")]
        for state in states {
            #expect(!state.isAvailable)
            #expect(!state.supportsPhoto)
            #expect(!state.message.isEmpty)
        }
    }

    @Test func settingsKeyIsStable() {
        #expect(EstimationModule.enabledKey == "mealEstimationEnabled")
    }
}
