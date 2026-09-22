import Foundation
import Testing
@testable import Omnomnom

struct ProductRecordTests {
    private func decode(_ json: String) throws -> ProductResponse {
        try JSONDecoder().decode(ProductResponse.self, from: Data(json.utf8))
    }

    private func product(_ fields: String) throws -> ProductRecord {
        let response = try decode(#"{"code":"4006381333931","status":1,"status_verbose":"product found","product":{\#(fields)}}"#)
        return try #require(response.product)
    }

    @Test func fullRecordMapsEveryNutrient() throws {
        let record = try product(#"""
            "code":"4006381333931","product_name":" Nutella ","brands":"Ferrero, Nutella",
            "nutriments":{"energy-kcal_100g":539,"energy_100g":2252,"proteins_100g":6.3,"carbohydrates_100g":57.5,
            "fat_100g":30.9,"saturated-fat_100g":10.6,"fiber_100g":0,"sugars_100g":56.3,"sodium_100g":0.0428,"salt_100g":0.107}
            """#)
        #expect(record.code == "4006381333931")
        #expect(record.name == "Nutella")
        #expect(record.brand == "Ferrero")
        #expect(record.per100g.energy == 539)
        #expect(record.per100g.protein == 6.3)
        #expect(record.per100g.carbohydrates == 57.5)
        #expect(record.per100g.fatTotal == 30.9)
        #expect(record.per100g.fatSaturated == 10.6)
        #expect(record.per100g.fiber == 0)
        #expect(record.per100g.sugar == 56.3)
        let sodium = try #require(record.per100g.sodium)
        #expect(abs(sodium - 42.8) < 0.001)
        #expect(record.isUsable)
    }

    @Test func saltAloneBecomesSodiumInMilligrams() throws {
        let record = try product(#""product_name":"Crackers","nutriments":{"energy-kcal_100g":100,"salt_100g":1.25}"#)
        #expect(record.per100g.sodium == 500)
        #expect(record.per100g.protein == nil)
    }

    @Test func stringValuedNutrimentsDecode() throws {
        let record = try product(#""nutriments":{"energy-kcal_100g":"250","proteins_100g":"12,5","fat_100g":"n/a"}"#)
        #expect(record.per100g.energy == 250)
        #expect(record.per100g.protein == 12.5)
        #expect(record.per100g.fatTotal == nil)
        #expect(record.isUsable)
    }

    @Test func kilojoulesAloneConvertToKilocalories() throws {
        let record = try product(#""nutriments":{"energy_100g":2092}"#)
        #expect(record.per100g.energy == 500)
    }

    @Test func blankNameAndBrandBecomeNil() throws {
        let record = try product(#""product_name":"   ","brands":"","nutriments":{"energy-kcal_100g":1}"#)
        #expect(record.name == nil)
        #expect(record.brand == nil)
    }

    @Test func missingNutrimentsGiveAnUnusableRecord() throws {
        let record = try product(#""product_name":"Mystery""#)
        #expect(record.per100g == .empty)
        #expect(!record.isUsable)
        #expect(record.name == "Mystery")
    }

    @Test func statusZeroIsAMiss() throws {
        let response = try decode(#"{"code":"123","status":0,"status_verbose":"product not found"}"#)
        #expect(!response.isFound)
        #expect(response.product == nil)
    }

    @Test func statusMayArriveAsAString() throws {
        let response = try decode(#"{"status":"1","product":{"code":"1"}}"#)
        #expect(response.isFound)
    }

    @Test func implausibleValuesBecomeUnknown() throws {
        let record = try product(#""nutriments":{"energy-kcal_100g":-5,"proteins_100g":1e9,"fat_100g":100000,"fiber_100g":0,"sugars_100g":100000.5}"#)
        #expect(record.per100g.energy == nil)
        #expect(record.per100g.protein == nil)
        #expect(record.per100g.fatTotal == 100_000)
        #expect(record.per100g.fiber == 0)
        #expect(record.per100g.sugar == nil)
        #expect(!record.isUsable)
    }

    @Test func nameAndBrandAreCapped() throws {
        let long = String(repeating: "x", count: 250)
        let record = try product(#""product_name":"\#(long)","brands":" \#(long) ,other""#)
        #expect(record.name?.count == 200)
        #expect(record.brand?.count == 200)
    }

    @Test func aDrinkIsMeasuredInMillilitres() throws {
        let record = try product(#"""
            "product_name":"Oat drink","quantity":"1 l","product_quantity_unit":"ml",
            "nutriments":{"energy-kcal_100g":46}
            """#)
        #expect(record.measure == .volume)
        #expect(record.per100g.energy == 46)
        #expect(record.isUsable)
    }

    @Test func aSolidIsMeasuredInGrams() throws {
        let record = try product(#""quantity":"400 g","product_quantity_unit":"g","nutriments":{"energy-kcal_100g":539}"#)
        #expect(record.measure == .mass)
    }

    @Test func aMissingQuantityFallsBackToMass() throws {
        #expect(try product(#""product_name":"Mystery""#).measure == .mass)
        #expect(try product(#""quantity":500,"nutriments":{"energy-kcal_100g":1}"#).measure == .mass)
    }

    /// The free-text quantity is the field that is actually filled in upstream, so the
    /// unit is read out of it as a word, never from a letter inside another word.
    @Test func volumeIsReadAsAUnitWordOnly() {
        #expect(ProductRecord.inferredMeasure(quantityUnit: nil, quantity: "330ml") == .volume)
        #expect(ProductRecord.inferredMeasure(quantityUnit: nil, quantity: "6 x 25 cl") == .volume)
        #expect(ProductRecord.inferredMeasure(quantityUnit: nil, quantity: "Flasche 0,5 L") == .volume)
        #expect(ProductRecord.inferredMeasure(quantityUnit: "ml", quantity: nil) == .volume)
        #expect(ProductRecord.inferredMeasure(quantityUnit: nil, quantity: "250 g") == .mass)
        #expect(ProductRecord.inferredMeasure(quantityUnit: nil, quantity: "1 kg") == .mass)
        #expect(ProductRecord.inferredMeasure(quantityUnit: nil, quantity: "Aloe vera gel") == .mass)
        #expect(ProductRecord.inferredMeasure(quantityUnit: nil, quantity: "") == .mass)
        #expect(ProductRecord.inferredMeasure(quantityUnit: nil, quantity: nil) == .mass)
    }

    @Test func nullAndBooleanNutrimentsAreIgnored() throws {
        let record = try product(#""nutriments":{"energy-kcal_100g":null,"proteins_100g":true,"fiber_100g":2}"#)
        #expect(record.per100g.energy == nil)
        #expect(record.per100g.protein == nil)
        #expect(record.per100g.fiber == 2)
    }
}
