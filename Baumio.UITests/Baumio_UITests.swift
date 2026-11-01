//
//  Baumio_UITests.swift
//  Baumio.UITests
//
//  Created by Christopher Biehler on 28.06.26.
//

import XCTest

final class Baumio_UITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testAppLaunchesAndStaysInForeground() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15), "Die App soll nach dem Start im Vordergrund laufen.")
    }

    // Hinweis: Der von Xcode vorgegebene `testLaunchPerformance` (XCTApplicationLaunchMetric) wurde entfernt.
    // Er liefert im Simulator häufig 0 Messwerte und schlägt dann ohne App-Fehler fehl.
    // Startzeiten lassen sich zuverlässiger über MetricKit (siehe BaumioMetricKit.swift) und Instruments beobachten.
}
