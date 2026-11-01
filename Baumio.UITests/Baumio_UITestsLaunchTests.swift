//
//  Baumio_UITestsLaunchTests.swift
//  Baumio.UITests
//
//  Created by Christopher Biehler on 28.06.26.
//

import XCTest

final class Baumio_UITestsLaunchTests: XCTestCase {

    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        true
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunch() throws {
        let app = XCUIApplication()
        app.launch()

        // Erst auf den Vordergrund warten, sonst schlägt der Snapshot manchmal fehl („Error getting main window“).
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15))
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 15))

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Launch Screen"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
