//
//  Baumio_Tests.swift
//  Baumio.Tests
//

import SwiftUI
import XCTest
@testable import Baumio_

final class Baumio_Tests: XCTestCase {

    // MARK: - Terminzeiten, Dauer und Abhängigkeit

    func testAppointmentCoderRoundTripKeepsDurationAndDependency() throws {
        let dependency = UUID()
        let encoded = try XCTUnwrap(AppointmentTimeCoder.encode(startTime: nil, endTime: nil, dependsOn: dependency, durationDays: 3, userNotes: "Rohbau"))
        let decoded = AppointmentTimeCoder.decode(encoded)
        XCTAssertEqual(decoded.dependsOn, dependency)
        XCTAssertEqual(decoded.durationDays, 3)
        XCTAssertEqual(decoded.userNotes, "Rohbau")
    }

    func testAppointmentCoderWithoutMetadataReturnsPlainNotes() {
        XCTAssertEqual(AppointmentTimeCoder.encode(startTime: nil, endTime: nil, userNotes: "Nur Notiz"), "Nur Notiz")
        XCTAssertNil(AppointmentTimeCoder.encode(startTime: nil, endTime: nil, userNotes: "  "))
        let decoded = AppointmentTimeCoder.decode("Nur Notiz")
        XCTAssertEqual(decoded.durationDays, 1)
        XCTAssertNil(decoded.dependsOn)
        XCTAssertEqual(decoded.userNotes, "Nur Notiz")
    }

    // MARK: - Förderung und Firmenzuordnung

    func testFundingLinkCoderRoundTripWithTrade() throws {
        let funding = UUID()
        let trade = UUID()
        let encoded = try XCTUnwrap(FundingLinkCoder.encode(fundingID: funding, tradeID: trade, userNotes: "Hinweis"))
        let decoded = FundingLinkCoder.decodeFull(encoded)
        XCTAssertEqual(decoded.fundingID, funding)
        XCTAssertEqual(decoded.tradeID, trade)
        XCTAssertEqual(decoded.userNotes, "Hinweis")
    }

    func testFundingLinkCoderLegacyFormatStillDecodes() {
        let funding = UUID()
        let decoded = FundingLinkCoder.decode("#FUND:id=\(funding.uuidString)\nNotiz")
        XCTAssertEqual(decoded.fundingID, funding)
        XCTAssertEqual(decoded.userNotes, "Notiz")
    }

    // MARK: - Mängel mit Pin

    func testDefectMetaCoderKeepsPinPosition() {
        let encoded = DefectMetaCoder.encode(trade: "Elektriker", responsible: "Müller", deadline: nil, userNotes: "Steckdose lose", pinX: 0.25, pinY: 0.75)
        let decoded = DefectMetaCoder.decode(encoded)
        XCTAssertEqual(decoded.trade, "Elektriker")
        XCTAssertEqual(decoded.pinX ?? 0, 0.25, accuracy: 0.0001)
        XCTAssertEqual(decoded.pinY ?? 0, 0.75, accuracy: 0.0001)
        XCTAssertEqual(decoded.description, "Steckdose lose")
    }

    // MARK: - Statusanzeige

    func testDisplayStatusCapitalizesCostStates() {
        XCTAssertEqual("bezahlt".displayStatus, "Bezahlt")
        XCTAssertEqual("beauftragt".displayStatus, "Beauftragt")
        XCTAssertEqual("storniert".displayStatus, "Storniert")
    }

    func testCostStatusFlags() {
        XCTAssertTrue(CostStatusValue.isOrdered("beauftragt"))
        XCTAssertTrue(CostStatusValue.isPaid("bezahlt"))
        XCTAssertFalse(CostStatusValue.isOrdered("offen"))
    }

    // MARK: - Geldformat

    func testEuroStringUsesGermanFormat() {
        let text = Decimal(1234.5).euroString
        XCTAssertTrue(text.contains("1.234,50"))
        XCTAssertTrue(text.contains("€"))
    }

    // MARK: - Darstellung

    func testAppearanceModeMapping() {
        XCTAssertEqual(AppearanceMode.dark.colorScheme, .dark)
        XCTAssertEqual(AppearanceMode.light.colorScheme, .light)
        XCTAssertNil(AppearanceMode.system.colorScheme)
    }
}
