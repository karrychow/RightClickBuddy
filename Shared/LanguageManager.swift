import Foundation

extension Notification.Name {
    static let RCBLanguageDidChange = Notification.Name("RCBLanguageDidChange")
    static let RCBMenuBarIconDidChange = Notification.Name("RCBMenuBarIconDidChange")
}

enum LanguageManager {
    static let preferredLanguageKey = "RCBPreferredLanguage"

    static var preferredLanguage: String {
        get { RCBAppGroup.defaults?.string(forKey: preferredLanguageKey) ?? "" }
        set {
            let old = preferredLanguage
            RCBAppGroup.defaults?.set(newValue.isEmpty ? nil : newValue, forKey: preferredLanguageKey)
            if newValue != old {
                AppLogger.settings.info("Language changed: \"\(old)\" → \"\(newValue)\"")
            }
        }
    }

    static func localizedString(_ key: String, comment: String = "") -> String {
        let lang = preferredLanguage
        if lang.isEmpty {
            return NSLocalizedString(key, comment: comment)
        }
        return localizedStringFromTable(key, language: lang) ?? key
    }

    private static var stringsCache: [String: [String: String]] = [:]
    private static var reverseStringsCache: [String: [String: String]] = [:]

    /// Given a localized (English) value, find the original key from en.lproj.
    /// E.g. "Templates" → "模板", "Entry Files" → "入口文件".
    /// Returns nil if the value doesn't match any key in the table.
    static func originalKey(for localizedValue: String, fromLanguage: String = "en") -> String? {
        if let cached = reverseStringsCache[fromLanguage] {
            return cached[localizedValue]
        }
        guard let lprojPath = Bundle.main.path(forResource: fromLanguage, ofType: "lproj") else {
            return nil
        }
        let stringsPath = (lprojPath as NSString).appendingPathComponent("Localizable.strings")
        guard let dict = NSDictionary(contentsOfFile: stringsPath) as? [String: String] else {
            return nil
        }
        let reverse = Dictionary(uniqueKeysWithValues: dict.map { ($0.value, $0.key) })
        reverseStringsCache[fromLanguage] = reverse
        return reverse[localizedValue]
    }

    private static func localizedStringFromTable(_ key: String, language: String) -> String? {
        if let cached = stringsCache[language] {
            return cached[key]
        }
        guard let lprojPath = Bundle.main.path(forResource: language, ofType: "lproj") else {
            return nil
        }
        let stringsPath = (lprojPath as NSString).appendingPathComponent("Localizable.strings")
        guard let dict = NSDictionary(contentsOfFile: stringsPath) as? [String: String] else {
            return nil
        }
        stringsCache[language] = dict
        return dict[key]
    }
}

func RCLocalizedString(_ key: String, comment: String = "") -> String {
    LanguageManager.localizedString(key, comment: comment)
}
