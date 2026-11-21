import XCTest

@MainActor
final class mbangleUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testUnavailableFixtureShowsDisabledCalibrationAndEscapeClosesTray() {
        let app = launch(sensor: "unavailable")
        defer { app.terminate() }
        openTray(in: app)

        assertText("—", in: element("live-angle", in: app))
        assertText("Sensor unavailable", in: element("alignment-status", in: app))
        XCTAssertFalse(app.buttons["set-current-angle"].isEnabled)
        assertText("50°", in: element("target-angle", in: app))

        app.typeKey(.escape, modifierFlags: [])
        assertGone(element("alignment-tray", in: app))
    }

    func testRaw104FixtureCalibratesTo76AndAdjustsByWholeDegrees() {
        let app = launch(sensor: "raw104")
        defer { app.terminate() }
        openTray(in: app)
        assertText("76.0°", in: element("live-angle", in: app))
        assertText("50°", in: element("target-angle", in: app))
        XCTAssertTrue(app.buttons["set-current-angle"].isEnabled)

        app.buttons["set-current-angle"].click()
        let target = element("target-angle", in: app)
        assertText("76°", in: target)
        assertText("On target", in: element("alignment-status", in: app))

        app.buttons["Increase target angle"].click()
        assertText("77°", in: target)
        app.buttons["Decrease target angle"].click()
        assertText("76°", in: target)
        app.typeKey(.upArrow, modifierFlags: [])
        assertText("77°", in: target)
        app.typeKey(.downArrow, modifierFlags: [])
        assertText("76°", in: target)
        app.typeKey(.upArrow, modifierFlags: [.shift])
        assertText("77°", in: target)
        app.typeKey(.downArrow, modifierFlags: [.shift])
        assertText("76°", in: target)
        app.buttons["alignment-done"].click()
        assertGone(element("alignment-tray", in: app))
    }

    func testOptionHoldShowsFeedbackAndReleaseRestoresNormalTitle() {
        let app = launch(sensor: "raw104")
        defer { app.terminate() }
        openTray(in: app)
        app.buttons["set-current-angle"].click()
        app.typeKey(.escape, modifierFlags: [])
        assertGone(element("alignment-tray", in: app))
        let title = element("alignment-title", in: app)
        assertLabel("MacBook Air 15-inch", in: title)

        XCUIElement.perform(withKeyModifiers: [.option]) {
            // An actual modified UI action exercises flagsChanged and the focused window.
            title.click()
            assertLabel("MacBook Air 15-inch, On target", in: title)
            XCTAssertTrue(app.buttons["alignment-reveal"].waitForExistence(timeout: 5))
            XCTAssertFalse(element("alignment-tray", in: app).exists)
        }

        assertLabel("MacBook Air 15-inch", in: title)
        assertGone(app.buttons["alignment-reveal"])
    }

    func testFixtureCalibrationDoesNotPersistBetweenLaunches() {
        let app = launch(sensor: "raw104")
        openTray(in: app)
        app.buttons["set-current-angle"].click()
        assertText("76°", in: element("target-angle", in: app))
        app.terminate()

        app.launch()
        defer { app.terminate() }
        focusShowcase(in: app)
        openTray(in: app)
        assertText("50°", in: element("target-angle", in: app))
        assertText("76.0°", in: element("live-angle", in: app))
    }

    private func launch(sensor: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--mbangle-ui-testing"]
        app.launchEnvironment["MBANGLE_UI_TEST_SENSOR"] = sensor
        app.launch()
        focusShowcase(in: app)
        return app
    }

    private func focusShowcase(in app: XCUIApplication) {
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 5))
        app.activate()
        let title = element("alignment-title", in: app)
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.click()
    }

    private func openTray(in app: XCUIApplication) {
        app.typeKey("l", modifierFlags: [.control, .option, .shift])
        XCTAssertTrue(element("alignment-tray", in: app).waitForExistence(timeout: 5))
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func assertText(_ expected: String, in element: XCUIElement,
                            file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: 5), file: file, line: line)
        let predicate = NSPredicate(format: "label == %@ OR value == %@", expected, expected)
        assertEventually(predicate, for: element, file: file, line: line)
    }

    private func assertLabel(_ expected: String, in element: XCUIElement,
                             file: StaticString = #filePath, line: UInt = #line) {
        assertEventually(NSPredicate(format: "label == %@", expected), for: element, file: file, line: line)
    }

    private func assertGone(_ element: XCUIElement,
                            file: StaticString = #filePath, line: UInt = #line) {
        assertEventually(NSPredicate(format: "exists == false"), for: element, file: file, line: line)
    }

    private func assertEventually(_ predicate: NSPredicate, for element: XCUIElement,
                                  file: StaticString = #filePath, line: UInt = #line) {
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed,
                       "Expected UI state did not appear", file: file, line: line)
    }
}
