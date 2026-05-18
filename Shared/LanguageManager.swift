import Foundation

extension Notification.Name {
    static let RCBLanguageDidChange = Notification.Name("RCBLanguageDidChange")
}

enum LanguageManager {
    static let preferredLanguageKey = "RCBPreferredLanguage"

    static var preferredLanguage: String {
        get { RCBAppGroup.defaults?.string(forKey: preferredLanguageKey) ?? "" }
        set { RCBAppGroup.defaults?.set(newValue.isEmpty ? nil : newValue, forKey: preferredLanguageKey) }
    }

    static func localizedString(_ key: String, comment: String = "") -> String {
        let lang = preferredLanguage
        if lang.isEmpty {
            return NSLocalizedString(key, comment: comment)
        }
        return localizedStringFromTable(key, language: lang) ?? key
    }

    private static var stringsCache: [String: [String: String]] = [:]

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
