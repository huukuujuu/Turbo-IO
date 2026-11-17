import XCTest

final class LocalizationReviewUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    func testKoreanScreensAndExternalServiceExplanations() {
        let app = XCUIApplication()
        let scope = UUID().uuidString
        for tab in 0...3 {
            app.launchArguments = ["--ui-test-scope", scope, "--ui-tab", String(tab)]
            app.launch()
            XCTAssertTrue(app.buttons["tab-\(tab)"].waitForExistence(timeout: 10))
            for element in app.staticTexts.allElementsBoundByIndex where element.exists {
                XCTAssertNil(element.label.range(of: "[\\p{Han}]", options: .regularExpression), element.label)
            }
            capture("ko-tab-\(tab)", app)
            app.terminate()
        }
        app.launchArguments = ["--ui-test-scope", scope, "--ui-tab", "3"]
        app.launch()
        let guide = app.buttons["external-services-guide"]
        XCTAssertTrue(guide.waitForExistence(timeout: 10)); guide.tap()
        XCTAssertTrue(app.staticTexts["음성 인식, 답변 AI, PC 작업은 서로 다른 연결입니다."].waitForExistence(timeout: 5))
        capture("ko-external-services-flow", app)
        let draft = app.staticTexts["5. 다른 모델 설정 초안"]
        for _ in 0..<12 where !draft.isHittable { app.swipeUp() }
        XCTAssertTrue(draft.isHittable)
        XCTAssertTrue(app.staticTexts["저장 전용 · 실제 연동 안 됨"].exists)
        capture("ko-draft-is-not-live", app)
    }
    private func capture(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
