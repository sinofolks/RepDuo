import XCTest

final class RepDuoUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-resetOnboarding", "-disableCountdown"]
    }

    func testSquatDemoWorkoutFlow() {
        app.launch()
        reachChoose()
        startWorkout(exerciseIdentifier: "choose.squat")
        completeOneDemoRep()
    }

    func testPushUpHasAnIndependentEndToEndRoute() {
        app.launch()
        reachChoose()
        startWorkout(exerciseIdentifier: "choose.pushUp")
        completeOneDemoRep()
    }

    func testCompletedOnboardingRelaunchesDirectlyToChoose() {
        app.launch()
        reachChoose()
        app.terminate()
        app.launchArguments.removeAll { $0 == "-resetOnboarding" }
        app.launch()

        XCTAssertTrue(app.buttons["choose.start"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["choose.squat"].exists)
        XCTAssertTrue(app.buttons["choose.pushUp"].exists)
        XCTAssertFalse(app.buttons["onboarding.getStarted"].exists)
    }

    func testSettingsPreservesTrainingNeonAndPrivacyControls() {
        app.launch()
        reachChoose()
        let settings = app.buttons["choose.settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 3))
        settings.tap()

        let table = app.tables.firstMatch
        XCTAssertTrue(table.waitForExistence(timeout: 3))
        XCTAssertEqual(table.cells.count, 10)
        XCTAssertEqual(table.switches.count, 4)
        XCTAssertEqual(table.sliders.count, 1)

        let glow = table.staticTexts.matching(
            NSPredicate(format: "label IN %@", ["Glow intensity", "发光强度", "発光の強さ"])
        ).firstMatch
        XCTAssertTrue(glow.exists)

        let privacy = table.staticTexts.matching(
            NSPredicate(format: "label IN %@", ["Privacy details", "隐私详情", "プライバシーの詳細"])
        ).firstMatch
        if !privacy.isHittable { table.swipeUp() }
        XCTAssertTrue(privacy.waitForExistence(timeout: 3))
        privacy.tap()
        let privacyTitle = app.alerts.staticTexts.matching(
            NSPredicate(format: "label IN %@", ["Private by design", "隐私优先设计", "プライバシーを重視"])
        ).firstMatch
        XCTAssertTrue(privacyTitle.waitForExistence(timeout: 3))
    }

    func testPauseFreezesCountingAndCancelFinishPreservesPausedState() {
        app.launch()
        reachChoose()
        startWorkout(exerciseIdentifier: "choose.squat")

        let pause = app.buttons["workout.pause"]
        XCTAssertTrue(pause.waitForExistence(timeout: 3))
        pause.tap()
        XCTAssertTrue(app.otherElements["workout.pausedPanel"].waitForExistence(timeout: 2))
        app.buttons["workout.simulateRep"].tap()
        XCTAssertEqual(app.staticTexts["workout.repCount"].label, "0")

        app.buttons["workout.finish"].tap()
        let keepTraining = localizedButton(labels: ["Keep training", "继续训练", "トレーニングを続ける"])
        XCTAssertTrue(keepTraining.waitForExistence(timeout: 2))
        keepTraining.tap()
        XCTAssertTrue(["RESUME", "继续", "再開"].contains(pause.label))

        pause.tap()
        app.buttons["workout.simulateRep"].tap()
        XCTAssertEqual(app.staticTexts["workout.repCount"].label, "1")
    }

    func testDeniedCameraPermissionShowsSettingsRecoveryScreen() {
        app.launchArguments.append("-simulateCameraDenied")
        app.launch()

        skipOnboardingIntro()
        XCTAssertTrue(app.buttons["cameraPermission.settings"].waitForExistence(timeout: 3))
    }

    func testOnboardingRemainsNavigableAtAccessibilityTextSize() {
        app.launchArguments += [
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge"
        ]
        app.launch()
        let next = app.buttons["onboarding.next"]
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        XCTAssertTrue(next.isHittable)
        next.tap()
        next.tap()
        let getStarted = app.buttons["onboarding.getStarted"]
        XCTAssertTrue(getStarted.waitForExistence(timeout: 3))
        XCTAssertTrue(getStarted.isHittable)
    }

    func testGearCheckPrimaryActionRemainsVisibleInLandscape() {
        addTeardownBlock { XCUIDevice.shared.orientation = .portrait }
        app.launch()

        skipOnboardingIntro()

        let gearContinue = app.buttons["gear.continue"]
        XCTAssertTrue(gearContinue.waitForExistence(timeout: 4))
        XCUIDevice.shared.orientation = .landscapeLeft
        let landscapeExpectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in self.app.frame.width > self.app.frame.height },
            object: nil
        )
        XCTAssertEqual(XCTWaiter.wait(for: [landscapeExpectation], timeout: 3), .completed)
        XCTAssertTrue(gearContinue.waitForExistence(timeout: 3))
        XCTAssertTrue(gearContinue.isHittable)

        gearContinue.tap()
        XCTAssertTrue(app.buttons["choose.start"].waitForExistence(timeout: 3))
    }

    func testWideCameraControlTogglesOnCameraSetup() {
        app.launchArguments.append("-simulateWideCamera")
        app.launch()
        reachChoose()
        app.buttons["choose.start"].tap()

        let wide = app.buttons["setup.wide"]
        XCTAssertTrue(wide.waitForExistence(timeout: 3))
        XCTAssertTrue(["On", "开启", "オン"].contains(wide.value as? String ?? ""))
        wide.tap()
        XCTAssertTrue(["Off", "关闭", "オフ"].contains(wide.value as? String ?? ""))
        wide.tap()
        XCTAssertTrue(["On", "开启", "オン"].contains(wide.value as? String ?? ""))
    }

    func testBodyTrackingModeCanSwitchAndRemainsUsableInLandscape() {
        addTeardownBlock { XCUIDevice.shared.orientation = .portrait }
        app.launch()
        reachChoose()
        app.buttons["choose.start"].tap()

        let control = app.segmentedControls["setup.trackingMode"]
        XCTAssertTrue(control.waitForExistence(timeout: 3))
        let partialBody = control.buttons.matching(
            NSPredicate(format: "label IN %@", ["PARTIAL BODY · ROUGH", "部分身体 · 粗略", "部分身体 · 簡易"])
        ).firstMatch
        XCTAssertTrue(partialBody.waitForExistence(timeout: 3))
        partialBody.tap()
        XCTAssertTrue(partialBody.isSelected)

        XCUIDevice.shared.orientation = .landscapeLeft
        let landscapeExpectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in self.app.frame.width > self.app.frame.height },
            object: nil
        )
        XCTAssertEqual(XCTWaiter.wait(for: [landscapeExpectation], timeout: 3), .completed)
        XCTAssertTrue(control.isHittable)
        XCTAssertTrue(app.buttons["setup.continue"].isHittable)
    }

    func testAICoachWorkoutControlsRemainUsableInLandscape() {
        addTeardownBlock { XCUIDevice.shared.orientation = .portrait }
        app.launch()
        reachChoose()
        startWorkout(exerciseIdentifier: "choose.pushUp")
        app.buttons["workout.simulateRep"].tap()

        XCTAssertTrue(app.otherElements["workout.coachScale"].waitForExistence(timeout: 2))
        XCUIDevice.shared.orientation = .landscapeLeft
        let landscapeExpectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in self.app.frame.width > self.app.frame.height },
            object: nil
        )
        XCTAssertEqual(XCTWaiter.wait(for: [landscapeExpectation], timeout: 3), .completed)
        XCTAssertTrue(app.buttons["workout.pause"].isHittable)
        XCTAssertTrue(app.buttons["workout.finish"].isHittable)
        XCTAssertTrue(app.otherElements["workout.coachScale"].exists)
    }

    /// Skips to the final onboarding page, whose button requests camera access.
    private func skipOnboardingIntro() {
        let skip = app.buttons["onboarding.skip"]
        XCTAssertTrue(skip.waitForExistence(timeout: 5))
        skip.tap()
        let getStarted = app.buttons["onboarding.getStarted"]
        XCTAssertTrue(getStarted.waitForExistence(timeout: 3))
        getStarted.tap()
    }

    private func reachChoose() {
        skipOnboardingIntro()

        let gearContinue = app.buttons["gear.continue"]
        XCTAssertTrue(gearContinue.waitForExistence(timeout: 4))
        XCTAssertTrue(gearContinue.isEnabled)
        gearContinue.tap()
        XCTAssertTrue(app.buttons["choose.start"].waitForExistence(timeout: 3))
    }

    private func startWorkout(exerciseIdentifier: String) {
        let exercise = app.buttons[exerciseIdentifier]
        XCTAssertTrue(exercise.waitForExistence(timeout: 3))
        exercise.tap()
        XCTAssertTrue(exercise.isSelected)
        app.buttons["choose.start"].tap()

        let setupContinue = app.buttons["setup.continue"]
        XCTAssertTrue(setupContinue.waitForExistence(timeout: 3))
        setupContinue.tap()
        XCTAssertTrue(app.buttons["workout.simulateRep"].waitForExistence(timeout: 3))
    }

    private func completeOneDemoRep() {
        let simulateRep = app.buttons["workout.simulateRep"]
        simulateRep.tap()
        XCTAssertEqual(app.staticTexts["workout.repCount"].label, "1")

        app.buttons["workout.finish"].tap()
        let finishSet = localizedButton(labels: ["Finish set", "结束本组", "セットを終了"])
        XCTAssertTrue(finishSet.waitForExistence(timeout: 2))
        finishSet.tap()
        let coachSummary = app.otherElements["summary.aiCoach"]
        if !coachSummary.waitForExistence(timeout: 2) { app.swipeUp() }
        XCTAssertTrue(coachSummary.waitForExistence(timeout: 3))
        let done = app.buttons["summary.done"]
        if !done.exists { app.swipeUp() }
        XCTAssertTrue(done.waitForExistence(timeout: 3))
    }

    private func localizedButton(labels: [String]) -> XCUIElement {
        app.sheets.buttons.matching(NSPredicate(format: "label IN %@", labels)).firstMatch
    }
}
