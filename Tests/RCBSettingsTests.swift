import XCTest

final class RCBSettingsTests: XCTestCase {

    // MARK: - Default Settings

    func testDefaultSettingsMenuEnabled() {
        let s = RCBSettings()
        XCTAssertTrue(s.menu.enabled)
        XCTAssertTrue(s.menu.showNew)
        XCTAssertTrue(s.menu.showTemplates)
        XCTAssertTrue(s.menu.showOffice)
        XCTAssertTrue(s.menu.showOpenWith)
    }

    func testDefaultSettingsEmptyScopeRoots() {
        let s = RCBSettings()
        XCTAssertTrue(s.scopeRoots.isEmpty)
    }

    func testDefaultSettingsEmptyCustomTemplates() {
        let s = RCBSettings()
        XCTAssertTrue(s.customTemplateSpecs.isEmpty)
    }

    func testDefaultSettingsEmptyTemplatesAndOpenWith() {
        let s = RCBSettings()
        XCTAssertTrue(s.templates.isEmpty)
        XCTAssertTrue(s.openWith.isEmpty)
    }

    // MARK: - defaultSettings

    func testDefaultSettingsFillsTemplates() {
        let s = RCBSettings.defaultSettings
        for t in RCBSettings.templateSpecs {
            XCTAssertTrue(s.isTemplateEnabled(t.id), "\(t.id) should be enabled")
        }
    }

    func testDefaultSettingsObsidianOptOut() {
        let s = RCBSettings.defaultSettings
        XCTAssertFalse(s.isOpenWithEnabled("openwith.obsidian"),
                       "Obsidian should be opt-in by default")
    }

    func testDefaultSettingsOpenWithOthersEnabled() {
        let s = RCBSettings.defaultSettings
        for a in RCBSettings.openWithSpecs where a.id != "openwith.obsidian" {
            XCTAssertTrue(s.isOpenWithEnabled(a.id), "\(a.id) should be enabled")
        }
    }

    // MARK: - Normalization

    func testNormalizationFillsMissingTemplateDefaults() {
        var s = RCBSettings()
        s.templates = [:] // Explicitly clear
        let n = s.normalized()
        for t in RCBSettings.templateSpecs {
            XCTAssertTrue(n.isTemplateEnabled(t.id), "\(t.id) should be true after normalization")
        }
    }

    func testNormalizationPreservesExistingTemplateFlags() {
        var s = RCBSettings()
        s.templates[RCBSettings.templateSpecs[0].id] = false
        let n = s.normalized()
        XCTAssertFalse(n.isTemplateEnabled(RCBSettings.templateSpecs[0].id))
    }

    func testNormalizationFillsMissingOpenWithDefaults() {
        var s = RCBSettings()
        s.openWith = [:]
        let n = s.normalized()
        XCTAssertFalse(n.isOpenWithEnabled("openwith.obsidian"))
        for a in RCBSettings.openWithSpecs where a.id != "openwith.obsidian" {
            XCTAssertTrue(n.isOpenWithEnabled(a.id),
                          "\(a.id) should be true after normalization")
        }
    }

    func testNormalizationPreservesExistingOpenWithFlags() {
        var s = RCBSettings()
        s.openWith["openwith.vscode"] = false
        let n = s.normalized()
        XCTAssertFalse(n.isOpenWithEnabled("openwith.vscode"))
    }

    func testNormalizationFillsCustomTemplateDefaults() {
        let t = RCBSettings.TemplateSpec(id: "", title: "Test", fileName: "test.txt", category: "Custom", contents: "hello")
        var s = RCBSettings()
        s.addCustomTemplate(t)
        let n = s.normalized()
        // The generated ID after addCustomTemplate
        let added = n.customTemplateSpecs[0]
        XCTAssertTrue(n.isTemplateEnabled(added.id))
    }

    // MARK: - Template CRUD

    func testAddCustomTemplateAssignsUUIDIfEmpty() {
        var s = RCBSettings()
        let t = RCBSettings.TemplateSpec(id: "", title: "Test", fileName: "t.txt", category: "X", contents: "")
        s.addCustomTemplate(t)
        XCTAssertEqual(s.customTemplateSpecs.count, 1)
        XCTAssertFalse(s.customTemplateSpecs[0].id.isEmpty)
    }

    func testAddCustomTemplatePreservesProvidedID() {
        var s = RCBSettings()
        let t = RCBSettings.TemplateSpec(id: "my-id", title: "Test", fileName: "t.txt", category: "X", contents: "")
        s.addCustomTemplate(t)
        XCTAssertEqual(s.customTemplateSpecs[0].id, "my-id")
    }

    func testUpdateCustomTemplate() {
        var s = RCBSettings()
        let t = RCBSettings.TemplateSpec(id: "my-id", title: "Original", fileName: "a.txt", category: "X", contents: "")
        s.addCustomTemplate(t)
        let updated = RCBSettings.TemplateSpec(id: "my-id", title: "Updated", fileName: "b.txt", category: "Y", contents: "new")
        s.updateCustomTemplate(updated)
        XCTAssertEqual(s.customTemplateSpecs[0].title, "Updated")
        XCTAssertEqual(s.customTemplateSpecs[0].fileName, "b.txt")
    }

    func testUpdateCustomTemplateNonexistentDoesNothing() {
        var s = RCBSettings()
        let t = RCBSettings.TemplateSpec(id: "missing", title: "X", fileName: "x.txt", category: "X", contents: "")
        s.updateCustomTemplate(t) // should not crash
        XCTAssertTrue(s.customTemplateSpecs.isEmpty)
    }

    func testRemoveCustomTemplate() {
        var s = RCBSettings()
        let t = RCBSettings.TemplateSpec(id: "my-id", title: "Test", fileName: "t.txt", category: "X", contents: "")
        s.addCustomTemplate(t)
        s.templates["my-id"] = true
        s.removeCustomTemplate(id: "my-id")
        XCTAssertTrue(s.customTemplateSpecs.isEmpty)
        // Should also clean up the templates dictionary
        XCTAssertNil(s.templates["my-id"])
    }

    func testAllTemplateSpecsIncludesBuiltinAndCustom() {
        var s = RCBSettings()
        let count = s.allTemplateSpecs.count
        s.addCustomTemplate(RCBSettings.TemplateSpec(id: "custom1", title: "C", fileName: "c.txt", category: "C", contents: ""))
        XCTAssertEqual(s.allTemplateSpecs.count, count + 1)
    }

    // MARK: - Category Operations

    func testRenameCategory() {
        var s = RCBSettings()
        s.addCustomTemplate(RCBSettings.TemplateSpec(id: "a", title: "A", fileName: "a.txt", category: "Old", contents: ""))
        s.addCustomTemplate(RCBSettings.TemplateSpec(id: "b", title: "B", fileName: "b.txt", category: "Old", contents: ""))
        s.addCustomTemplate(RCBSettings.TemplateSpec(id: "c", title: "C", fileName: "c.txt", category: "Other", contents: ""))
        s.renameCategory(from: "Old", to: "New")
        for t in s.customTemplateSpecs where ["a", "b"].contains(t.id) {
            XCTAssertEqual(t.category, "New")
        }
        XCTAssertEqual(s.customTemplateSpecs.first(where: { $0.id == "c" })?.category, "Other")
    }

    func testRenameCategoryToSameNameDoesNothing() {
        var s = RCBSettings()
        s.addCustomTemplate(RCBSettings.TemplateSpec(id: "a", title: "A", fileName: "a.txt", category: "X", contents: ""))
        s.renameCategory(from: "X", to: "X") // should be fine
        XCTAssertEqual(s.customTemplateSpecs[0].category, "X")
    }

    func testRemoveAllCustomTemplatesInCategory() {
        var s = RCBSettings()
        s.addCustomTemplate(RCBSettings.TemplateSpec(id: "a", title: "A", fileName: "a.txt", category: "RemoveMe", contents: ""))
        s.addCustomTemplate(RCBSettings.TemplateSpec(id: "b", title: "B", fileName: "b.txt", category: "RemoveMe", contents: ""))
        s.addCustomTemplate(RCBSettings.TemplateSpec(id: "c", title: "C", fileName: "c.txt", category: "Keep", contents: ""))
        s.templates["a"] = true
        s.templates["b"] = false
        s.removeAllCustomTemplates(inCategory: "RemoveMe")
        XCTAssertEqual(s.customTemplateSpecs.count, 1)
        XCTAssertEqual(s.customTemplateSpecs[0].id, "c")
        XCTAssertNil(s.templates["a"])
        XCTAssertNil(s.templates["b"])
    }

    func testCustomTemplateIDs() {
        var s = RCBSettings()
        s.addCustomTemplate(RCBSettings.TemplateSpec(id: "x", title: "X", fileName: "x.txt", category: "G", contents: ""))
        s.addCustomTemplate(RCBSettings.TemplateSpec(id: "y", title: "Y", fileName: "y.txt", category: "G", contents: ""))
        let ids = s.customTemplateIDs(inCategory: "G")
        XCTAssertEqual(ids.sorted(), ["x", "y"])
    }

    func testCustomTemplateIDsEmptyForUnknownCategory() {
        let s = RCBSettings()
        XCTAssertTrue(s.customTemplateIDs(inCategory: "Nonexistent").isEmpty)
    }

    // MARK: - Toggle / isEnabled

    func testIsTemplateEnabledDefaultTrue() {
        let s = RCBSettings()
        XCTAssertTrue(s.isTemplateEnabled("nonexistent"))
    }

    func testIsTemplateEnabledWhenExplicitlyDisabled() {
        var s = RCBSettings()
        s.templates["some.id"] = false
        XCTAssertFalse(s.isTemplateEnabled("some.id"))
    }

    func testIsOpenWithEnabledDefaultTrue() {
        let s = RCBSettings()
        XCTAssertTrue(s.isOpenWithEnabled("nonexistent"))
    }

    func testIsOpenWithEnabledWhenExplicitlyDisabled() {
        var s = RCBSettings()
        s.openWith["some.id"] = false
        XCTAssertFalse(s.isOpenWithEnabled("some.id"))
    }

    // MARK: - Encoding / Decoding

    func testEncodeDecodeRoundTrip() throws {
        let s = RCBSettings.defaultSettings
        let data = try JSONEncoder().encode(s)
        let decoded = try JSONDecoder().decode(RCBSettings.self, from: data)
        XCTAssertEqual(s, decoded)
    }

    func testEncodeDecodeCustomTemplates() throws {
        var s = RCBSettings()
        s.addCustomTemplate(RCBSettings.TemplateSpec(id: "c1", title: "Custom", fileName: "f.txt", category: "C", contents: "hello"))
        let data = try JSONEncoder().encode(s)
        let decoded = try JSONDecoder().decode(RCBSettings.self, from: data)
        XCTAssertEqual(decoded.customTemplateSpecs.count, 1)
        XCTAssertEqual(decoded.customTemplateSpecs[0].title, "Custom")
        XCTAssertEqual(decoded.customTemplateSpecs[0].contents, "hello")
    }

    func testEncodeDecodeScopeRoots() throws {
        var s = RCBSettings()
        s.scopeRoots = ["~/Desktop", "/Volumes/External"]
        let data = try JSONEncoder().encode(s)
        let decoded = try JSONDecoder().decode(RCBSettings.self, from: data)
        XCTAssertEqual(decoded.scopeRoots, ["~/Desktop", "/Volumes/External"])
    }

    func testEncodeDecodeToggles() throws {
        var s = RCBSettings()
        s.templates["t1"] = false
        s.templates["t2"] = true
        s.openWith["o1"] = false
        let data = try JSONEncoder().encode(s)
        let decoded = try JSONDecoder().decode(RCBSettings.self, from: data)
        XCTAssertFalse(decoded.isTemplateEnabled("t1"))
        XCTAssertTrue(decoded.isTemplateEnabled("t2"))
        XCTAssertFalse(decoded.isOpenWithEnabled("o1"))
    }

    // MARK: - Equatable

    func testSettingsEquality() {
        let a = RCBSettings.defaultSettings
        let b = RCBSettings.defaultSettings
        XCTAssertEqual(a, b)
    }

    func testSettingsInequality() {
        var a = RCBSettings.defaultSettings
        var b = RCBSettings.defaultSettings
        a.menu.enabled = false
        XCTAssertNotEqual(a, b)
    }

    func testTemplateSpecEquality() {
        let a = RCBSettings.TemplateSpec(id: "x", title: "T", fileName: "f", category: "C", contents: "c")
        let b = RCBSettings.TemplateSpec(id: "x", title: "T", fileName: "f", category: "C", contents: "c")
        XCTAssertEqual(a, b)
    }

    func testOpenWithSpecEquality() {
        let a = RCBSettings.OpenWithSpec(id: "x", title: "T", category: "C", bundleIdCandidates: ["a", "b"])
        let b = RCBSettings.OpenWithSpec(id: "x", title: "T", category: "C", bundleIdCandidates: ["a", "b"])
        XCTAssertEqual(a, b)
    }

    // MARK: - Built-in Specs

    func testBuiltinTemplateSpecsAreNotEmpty() {
        XCTAssertFalse(RCBSettings.templateSpecs.isEmpty)
    }

    func testBuiltinTemplateSpecsHaveUniqueIDs() {
        let ids = RCBSettings.templateSpecs.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count, "TemplateSpec IDs must be unique")
    }

    func testBuiltinOpenWithSpecsAreNotEmpty() {
        XCTAssertFalse(RCBSettings.openWithSpecs.isEmpty)
    }

    func testBuiltinOpenWithSpecsHaveUniqueIDs() {
        let ids = RCBSettings.openWithSpecs.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count, "OpenWithSpec IDs must be unique")
    }

    // MARK: - Settings URL

    func testSettingsURLContainsFileName() {
        let url = RCBSettings.settingsURL()
        XCTAssertEqual(url.lastPathComponent, "settings.json")
    }

    func testSettingsURLContainsAppSupportFolder() {
        let url = RCBSettings.settingsURL()
        XCTAssertTrue(url.path.contains("RightClickBuddy"))
    }

    // MARK: - Caching

    func testLoadCachedReturnsDefaultsWhenNoFile() {
        // loadCached should not crash and return a valid RCBSettings
        let s = RCBSettings.loadCached()
        // Just verify it returns something usable
        XCTAssertNotNil(s.menu)
    }

    // MARK: - ScopeRootBookmarkStore (Unit-test friendly: no security scope)

    func testScopeRootBookmarkStoreRoundTrip() {
        RCBScopeRootBookmarkStore.removeAll()

        XCTAssertTrue(RCBScopeRootBookmarkStore.loadAll().isEmpty)

        let data = "hello".data(using: .utf8)!
        RCBScopeRootBookmarkStore.setBookmark(data, forScopeRoot: "~/test")
        let loaded = RCBScopeRootBookmarkStore.loadAll()
        XCTAssertEqual(loaded["~/test"], data)

        RCBScopeRootBookmarkStore.removeBookmark(forScopeRoot: "~/test")
        XCTAssertNil(RCBScopeRootBookmarkStore.loadAll()["~/test"])

        RCBScopeRootBookmarkStore.removeAll()
    }

    // MARK: - Codable Key Consistency

    func testJSONCodingKeysMatchPropertyNames() throws {
        let s = RCBSettings.defaultSettings
        let data = try JSONEncoder().encode(s)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNotNil(json["menu"])
        XCTAssertNotNil(json["scopeRoots"])
        XCTAssertNotNil(json["customTemplateSpecs"])
        XCTAssertNotNil(json["templates"])
        XCTAssertNotNil(json["openWith"])
    }
}
