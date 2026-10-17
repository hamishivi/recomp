import XCTest

// No accounts, Health access, real diary or AI server is used. The app recognizes
// these launch flags ONLY in Debug simulator builds and uses an isolated diary.
final class RecompUITests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("UI tests are simulator-only; never run synthetic records against personal Health.")
        #endif
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--recomp-ui-test", "--reset-test-diary", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.buttons["food.log"].waitForExistence(timeout: 10))
    }
    override func tearDownWithError() throws {
        if let app {
            let image = XCTAttachment(screenshot: app.screenshot())
            image.name = name; image.lifetime = .keepAlways; add(image)
            app.terminate()
        }
    }
    private func replace(_ identifier: String, with text: String) {
        let field = app.textFields[identifier]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        for _ in 0..<6 { if field.isHittable { break }; app.swipeUp() }
        // Nutrition fields are right-aligned. Select the existing numeric
        // token before typing so XCTest replaces it, rather than inserting
        // before it (for example, turning "0" → "500" into "5000").
        field.tap()
        let current = field.value as? String ?? ""
        if !current.isEmpty && current != field.placeholderValue {
            field.doubleTap()
        }
        field.typeText(text)
    }
    private func addFood() {
        app.buttons["food.log"].tap()
        replace("food.name", with: "Synthetic UI meal")
        replace("nutrition.calories", with: "500")
        replace("nutrition.protein", with: "30")
        replace("nutrition.carbs", with: "50")
        replace("nutrition.fat", with: "20")
        app.buttons["food.save"].tap()
        XCTAssertTrue(app.buttons.matching(identifier: "food.entry").firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons.matching(identifier: "food.entry").firstMatch.label.contains("Synthetic UI meal"))
    }
    // Records a real native launch metric when run on the Mac. No result is
    // prefilled and no universal timing threshold is fabricated for simulators.
    func testLaunchPerformance() {
        app.terminate()
        app.launchArguments.removeAll { $0 == "--reset-test-diary" }
        let options = XCTMeasureOptions()
        options.iterationCount = 5
        measure(metrics: [XCTApplicationLaunchMetric(waitUntilResponsive: true)], options: options) {
            app.launch()
        }
    }
    func testNavigationAndEmptyScreens() {
        for label in ["Body", "Trends", "Maintenance", "Settings", "Today"] {
            let tab = app.tabBars.buttons[label]
            XCTAssertTrue(tab.exists); tab.tap()
        }
        XCTAssertTrue(app.buttons["food.log"].exists)
    }
    func testFoodSurvivesRelaunch() {
        addFood()
        app.terminate()
        app.launchArguments.removeAll { $0 == "--reset-test-diary" }
        app.launch()
        XCTAssertTrue(app.buttons.matching(identifier: "food.entry").firstMatch.waitForExistence(timeout: 10))
        XCTAssertEqual(app.buttons.matching(identifier: "food.entry").count, 1)
    }
    func testCancelFoodDoesNotLog() {
        app.buttons["food.log"].tap()
        replace("food.name", with: "Never saved")
        app.navigationBars.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["Discard"].waitForExistence(timeout: 3))
        app.buttons["Discard"].tap()
        XCTAssertTrue(app.buttons["food.log"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons.matching(identifier: "food.entry").count, 0)
    }
    func testCheckHasNoLogButtonAndDoesNotChangeDiary() {
        app.buttons["food.check"].tap()
        XCTAssertTrue(app.navigationBars["Check food"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["food.save"].exists)
        app.navigationBars.buttons["Close"].tap()
        XCTAssertTrue(app.buttons["food.log"].waitForExistence(timeout: 5))
    }
    func testWeightCanBeLoggedLocally() {
        app.tabBars.buttons["Body"].tap()
        app.buttons["Log measurements"].tap()
        replace("measurement.weight", with: "85")
        app.navigationBars.buttons["Save"].tap()
        XCTAssertTrue(app.buttons["Log measurements"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.navigationBars["Log measurements"].exists)
    }

    func testSingleFoodFlowHasPhotosAndSavedFoods() {
        XCTAssertFalse(app.navigationBars["Recomp"].exists)
        XCTAssertFalse(app.buttons["Estimate"].exists)
        XCTAssertFalse(app.buttons["food.usuals"].exists)
        app.buttons["food.log"].tap()
        XCTAssertTrue(app.navigationBars["Log food"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["food.photos"].exists)
        XCTAssertTrue(app.buttons["food.camera"].exists)
        XCTAssertTrue(app.buttons["food.usuals"].exists)
        XCTAssertTrue(app.buttons["food.save"].exists)
    }
    func testSavedFoodOnlyFillsDraftUntilSave() {
        app.buttons["food.log"].tap()
        app.buttons["food.usuals"].tap()
        let choice = app.buttons.matching(identifier: "food.savedChoice").firstMatch
        XCTAssertTrue(choice.waitForExistence(timeout: 5)); choice.tap()
        XCTAssertTrue(app.navigationBars["Log food"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["food.save"].isEnabled)
        app.navigationBars.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["Discard"].waitForExistence(timeout: 3)); app.buttons["Discard"].tap()
        XCTAssertEqual(app.buttons.matching(identifier: "food.entry").count, 0)
    }
    func testHistorySearchReusesOlderMealAndKeepsUsualsSeparate() {
        app.buttons["Previous day"].tap()
        addFood()
        app.buttons["Next day"].tap()
        XCTAssertEqual(app.buttons.matching(identifier: "food.entry").count, 0)
        app.buttons["food.log"].tap()
        app.buttons["food.history"].tap()
        XCTAssertTrue(app.navigationBars["Meal history"].waitForExistence(timeout: 5))
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 3)); search.tap()
        search.typeText("synthetic meal")
        let choice = app.buttons.matching(identifier: "food.historyChoice").firstMatch
        XCTAssertTrue(choice.waitForExistence(timeout: 3))
        XCTAssertTrue(choice.label.contains("500 kcal"))
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = "Meal history - search older meal"; image.lifetime = .keepAlways; add(image)
        choice.tap()
        XCTAssertTrue(app.navigationBars["Log food"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["food.name"].value as? String, "Synthetic UI meal")
        XCTAssertEqual(app.textFields["nutrition.calories"].value as? String, "500")
        app.buttons["food.save"].tap()
        XCTAssertTrue(app.buttons.matching(identifier: "food.entry").firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons.matching(identifier: "food.entry").count, 1)
        app.buttons["Previous day"].tap()
        XCTAssertEqual(app.buttons.matching(identifier: "food.entry").count, 1)
        app.buttons["Next day"].tap()
        app.buttons["food.log"].tap()
        app.buttons["food.usuals"].tap()
        XCTAssertTrue(app.navigationBars["Your usuals"].waitForExistence(timeout: 5))
        XCTAssertGreaterThan(app.buttons.matching(identifier: "food.savedChoice").count, 0)
        XCTAssertFalse(app.buttons.matching(identifier: "food.savedChoice").allElementsBoundByIndex.contains { $0.label.contains("Synthetic UI meal") })
    }
    func testHistoryReplacementUndoAndDiscardDoNotLog() {
        addFood()
        app.buttons["food.log"].tap()
        replace("food.name", with: "New draft")
        replace("nutrition.calories", with: "700")
        app.buttons["Done"].tap()
        for _ in 0..<6 { if app.buttons["food.history"].isHittable { break }; app.swipeDown() }
        app.buttons["food.history"].tap()
        let choice = app.buttons.matching(identifier: "food.historyChoice").firstMatch
        XCTAssertTrue(choice.waitForExistence(timeout: 5)); choice.tap()
        XCTAssertTrue(app.buttons["Replace"].waitForExistence(timeout: 3))
        app.buttons["Replace"].tap()
        XCTAssertTrue(app.navigationBars["Log food"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["nutrition.calories"].value as? String, "500")
        app.buttons["food.undo"].tap()
        XCTAssertEqual(app.textFields["food.name"].value as? String, "New draft")
        XCTAssertEqual(app.textFields["nutrition.calories"].value as? String, "700")
        app.navigationBars.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["Discard"].waitForExistence(timeout: 3)); app.buttons["Discard"].tap()
        XCTAssertEqual(app.buttons.matching(identifier: "food.entry").count, 1)
    }
    func testHistoryEmptySearchAndEditingExclusion() {
        app.buttons["food.log"].tap()
        app.buttons["food.history"].tap()
        XCTAssertTrue(app.staticTexts["No meal history yet"].waitForExistence(timeout: 5))
        let search = app.searchFields.firstMatch
        search.tap(); search.typeText("nothing here")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'no results'")).firstMatch.waitForExistence(timeout: 3))
        XCTAssertEqual(app.buttons.matching(identifier: "food.historyChoice").count, 0)
        let endSearch = app.buttons.matching(NSPredicate(format: "label == 'close' OR label CONTAINS[c] 'cancel'"))
            .allElementsBoundByIndex.first { $0.isHittable }
        XCTAssertNotNil(endSearch, app.debugDescription); endSearch?.tap()
        app.navigationBars["Meal history"].buttons["Cancel"].tap()
        app.navigationBars["Log food"].buttons["Cancel"].tap()
        XCTAssertEqual(app.buttons.matching(identifier: "food.entry").count, 0)
        addFood()
        app.buttons.matching(identifier: "food.entry").firstMatch.tap()
        app.buttons["food.history"].tap()
        XCTAssertTrue(app.staticTexts["No other meals yet"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons.matching(identifier: "food.historyChoice").count, 0)
    }
    func testHistorySupportsDarkAppearanceAndLargestText() {
        addFood()
        app.terminate()
        app.launchArguments.removeAll { $0 == "--reset-test-diary" }
        app.launchArguments += ["-recomp.interface.appearance", "dark", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        XCTAssertTrue(app.buttons["food.log"].waitForExistence(timeout: 10)); app.buttons["food.log"].tap()
        app.buttons["food.history"].tap()
        let choice = app.buttons.matching(identifier: "food.historyChoice").firstMatch
        XCTAssertTrue(choice.waitForExistence(timeout: 5))
        XCTAssertTrue(choice.isHittable)
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = "Meal history - dark largest text"; image.lifetime = .keepAlways; add(image)
        choice.tap()
        XCTAssertTrue(app.navigationBars["Log food"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["food.save"].isEnabled)
    }
    func testSavedFoodsSettingsIsSubmenu() {
        app.tabBars.buttons["Settings"].tap()
        let row = app.buttons["settings.usuals"]
        for _ in 0..<6 { if row.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(row.exists); row.tap()
        XCTAssertTrue(app.navigationBars["Your usuals"].waitForExistence(timeout: 5))
    }
    func testEditingFoodStillOffersPhotos() {
        addFood()
        app.buttons.matching(identifier: "food.entry").firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Edit food"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["food.photos"].exists)
    }

    func testUndoRestoresAnEditedMeal() {
        addFood()
        app.buttons.matching(identifier: "food.entry").firstMatch.tap()
        replace("nutrition.calories", with: "600")
        let undo = app.buttons["food.undo"]
        XCTAssertTrue(undo.waitForExistence(timeout: 3)); undo.tap()
        XCTAssertEqual(app.textFields["nutrition.calories"].value as? String, "500")
        app.buttons["food.save"].tap()
        XCTAssertEqual(app.buttons.matching(identifier: "food.entry").count, 1)
    }
    func testPortionShortcutUpdatesFields() {
        addFood()
        app.buttons.matching(identifier: "food.entry").firstMatch.tap()
        let half = app.buttons["food.half"]
        for _ in 0..<6 { if half.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(half.exists); half.tap()
        XCTAssertEqual(app.textFields["nutrition.calories"].value as? String, "250")
        app.buttons["food.undo"].tap()
        XCTAssertEqual(app.textFields["nutrition.calories"].value as? String, "500")
    }
    func testHealthSettingsOpensWithoutConnecting() {
        app.tabBars.buttons["Settings"].tap()
        app.buttons["Apple Health"].tap()
        XCTAssertTrue(app.navigationBars["Apple Health"].waitForExistence(timeout: 5))
        // Never tap Connect: tests must not publish synthetic diary values.
        XCTAssertTrue(app.buttons["Connect Apple Health"].exists || app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'unavailable'")).count > 0)
    }

    private func openBurnPreview() {
        app.tabBars.buttons["Settings"].tap()
        let preview = app.buttons["settings.preview"]
        for _ in 0..<8 { if preview.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(preview.exists)
        preview.tap()
        app.buttons["Burn"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["burn.chart"].firstMatch.waitForExistence(timeout: 5))
    }

    private func captureBurnChart(_ title: String) {
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = title
        image.lifetime = .keepAlways
        add(image)
    }

    func testBurnChartInspectionAndDayStates() {
        openBurnPreview()
        captureBurnChart("Burn - in progress")
        let chart = app.descendants(matching: .any)["burn.chart"].firstMatch
        chart.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.5)).tap()
        captureBurnChart("Burn - after tapping forecast")
        XCTAssertTrue(app.buttons["burn.reset"].waitForExistence(timeout: 3), app.debugDescription)
        app.buttons["burn.reset"].tap()
        chart.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.5))
            .press(forDuration: 0.5, thenDragTo: chart.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.5)))
        XCTAssertTrue(app.buttons["burn.reset"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'FORECAST AT'")).firstMatch.exists)
        captureBurnChart("Burn - inspecting forecast")
        app.buttons["burn.reset"].tap()

        app.buttons["Complete"].tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'ESTIMATED DAY TOTAL'")).firstMatch.exists)
        XCTAssertFalse(app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'DAY FORECAST'")).firstMatch.exists)
        captureBurnChart("Burn - completed day")

        app.buttons["Upcoming"].tap()
        XCTAssertTrue(app.staticTexts["This day has not started. All values are forecasts."].exists)
        captureBurnChart("Burn - upcoming day")

        app.buttons["In progress"].tap()
        app.switches["Include sample activity"].tap()
        XCTAssertTrue(app.staticTexts["No activity data · using maintenance pace"].exists)
        app.buttons["How this is estimated"].tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'No activity data for this day'")).firstMatch.exists)
        captureBurnChart("Burn - maintenance fallback and explanation")
    }

    func testBurnChartDarkAppearanceAndLargeText() {
        app.terminate()
        app.launchArguments += ["-recomp.interface.appearance", "dark", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        openBurnPreview()
        let title = app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'ESTIMATED BURN SO FAR'")).firstMatch
        XCTAssertTrue(title.exists)
        XCTAssertGreaterThanOrEqual(title.frame.minX, app.frame.minX)
        XCTAssertLessThanOrEqual(title.frame.maxX, app.frame.maxX)
        captureBurnChart("Burn - dark accessibility header")
        let chart = app.descendants(matching: .any)["burn.chart"].firstMatch
        for _ in 0..<5 { if chart.isHittable { break }; app.swipeUp() }
        captureBurnChart("Burn - dark accessibility chart")
        let details = app.buttons["How this is estimated"]
        for _ in 0..<5 { if details.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(details.isHittable)
    }
}
