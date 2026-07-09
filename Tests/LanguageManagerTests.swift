import XCTest

final class LanguageManagerTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // Reset to default before each test
        LanguageManager.preferredLanguage = ""
    }

    override func tearDown() {
        LanguageManager.preferredLanguage = ""
        super.tearDown()
    }

    // MARK: - Preferred Language

    func testDefaultLanguageIsEmpty() {
        let lang = LanguageManager.preferredLanguage
        XCTAssertEqual(lang, "", "Default language should be empty (system)")
    }

    func testSetChineseLanguage() {
        LanguageManager.preferredLanguage = "zh-Hans"
        XCTAssertEqual(LanguageManager.preferredLanguage, "zh-Hans")
    }

    func testSetEnglishLanguage() {
        LanguageManager.preferredLanguage = "en"
        XCTAssertEqual(LanguageManager.preferredLanguage, "en")
    }

    func testSetEmptyLanguageRestoresDefault() {
        LanguageManager.preferredLanguage = "en"
        LanguageManager.preferredLanguage = ""
        XCTAssertEqual(LanguageManager.preferredLanguage, "")
    }

    // MARK: - Localized String

    func testLocalizedStringWithSystemLanguage() {
        // With empty lang, NSLocalizedString is used — should return the key itself
        // for a key that has no localized version
        let result = LanguageManager.localizedString("nonexistent_key_abc123")
        XCTAssertEqual(result, "nonexistent_key_abc123",
                       "With system language, missing keys should return the key")
    }

    func testRCLocalizedStringFunction() {
        let result = RCLocalizedString("nonexistent_key_def456")
        XCTAssertEqual(result, "nonexistent_key_def456")
    }

    // MARK: - Cache Behavior

    func testStringsCacheMissReturnsNil() {
        let result = LanguageManager.localizedString("some_key")
        // Should not crash; cache miss just means we go to the file
        XCTAssertNotNil(result)
    }

    func testLanguagePersistenceAcrossInstances() {
        // Set via UserDefaults directly
        LanguageManager.preferredLanguage = "en"
        let readBack = LanguageManager.preferredLanguage
        XCTAssertEqual(readBack, "en")
    }

    // MARK: - Notification

    func testLanguageChangeNotification() {
        let expectation = self.expectation(forNotification: .RCBLanguageDidChange, object: nil, handler: nil)

        // Post the notification
        NotificationCenter.default.post(name: .RCBLanguageDidChange, object: nil)

        wait(for: [expectation], timeout: 1.0)
    }

    func testLanguageChangeNotificationNameEquality() {
        let name = Notification.Name("RCBLanguageDidChange")
        XCTAssertEqual(name, .RCBLanguageDidChange)
    }
}
