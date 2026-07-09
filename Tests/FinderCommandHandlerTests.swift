import XCTest

final class FinderCommandHandlerTests: XCTestCase {

    var tempDir: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("RightClickBuddyTests_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
        try super.tearDownWithError()
    }

    // MARK: - createNewFile

    func testCreateNewFile() throws {
        let url = try FinderCommandHandler.createNewFile(in: tempDir, fileName: "hello.txt")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertEqual(url.lastPathComponent, "hello.txt")
        // Content should be empty
        let content = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(content.isEmpty)
    }

    func testCreateNewFileAddsTxtExtension() throws {
        let url = try FinderCommandHandler.createNewFile(in: tempDir, fileName: "readme")
        XCTAssertTrue(url.pathExtension == "txt" || url.lastPathComponent == "readme.txt",
                      "Should add .txt extension: \(url.lastPathComponent)")
    }

    func testCreateNewFilePreservesExistingExtension() throws {
        let url = try FinderCommandHandler.createNewFile(in: tempDir, fileName: "data.json")
        XCTAssertEqual(url.pathExtension, "json")
    }

    func testCreateNewFileTrimsWhitespace() throws {
        let url = try FinderCommandHandler.createNewFile(in: tempDir, fileName: "  file.txt  ")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func testCreateNewFileWithEmptyNameThrows() {
        XCTAssertThrowsError(try FinderCommandHandler.createNewFile(in: tempDir, fileName: "  ")) { error in
            let nsError = error as NSError
            XCTAssertEqual(nsError.domain, "RightClickBuddy")
            XCTAssertEqual(nsError.code, 2)
        }
    }

    func testCreateNewFileWithDotSuffix() throws {
        let url = try FinderCommandHandler.createNewFile(in: tempDir, fileName: "file.")
        // Should not crash; should create with .txt added
        XCTAssertTrue(url.lastPathComponent.hasPrefix("file."),
                      "\(url.lastPathComponent) should preserve the trailing dot")
    }

    // MARK: - Shell Script Creation

    func testCreateNewShellScriptIncludesShebang() throws {
        let url = try FinderCommandHandler.createNewFile(in: tempDir, fileName: "script.sh")
        let content = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(content.hasPrefix("#!/bin/zsh\n"))
    }

    func testCreateNewShellScriptIsExecutable() throws {
        let url = try FinderCommandHandler.createNewFile(in: tempDir, fileName: "deploy.sh")
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let permissions = attrs[.posixPermissions] as? NSNumber
        let perms = permissions?.int16Value ?? 0
        XCTAssertTrue(perms & 0o111 != 0, "Shell script should be executable, got permissions: \(String(permissions?.intValue ?? 0, radix: 8))")
    }

    // MARK: - createNewFolder

    func testCreateNewFolder() throws {
        let url = try FinderCommandHandler.createNewFolder(in: tempDir, folderName: "MyFolder")
        var isDir: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir))
        XCTAssertTrue(isDir.boolValue)
        XCTAssertEqual(url.lastPathComponent, "MyFolder")
    }

    func testCreateNewFolderWithEmptyNameThrows() {
        XCTAssertThrowsError(try FinderCommandHandler.createNewFolder(in: tempDir, folderName: "")) { error in
            let nsError = error as NSError
            XCTAssertEqual(nsError.domain, "RightClickBuddy")
            XCTAssertEqual(nsError.code, 12)
        }
    }

    func testCreateNewFolderWithWhitespaceNameThrows() {
        XCTAssertThrowsError(try FinderCommandHandler.createNewFolder(in: tempDir, folderName: "   "))
    }

    // MARK: - createNewTemplateFile

    func testCreateNewTemplateFile() throws {
        let contents = "Hello, World!".data(using: .utf8)!
        let url = try FinderCommandHandler.createNewTemplateFile(in: tempDir, fileName: "greeting.txt", contents: contents)
        let read = try String(contentsOf: url, encoding: .utf8)
        XCTAssertEqual(read, "Hello, World!")
    }

    func testCreateNewTemplateFileWithPermissions() throws {
        let contents = Data("#!/bin/bash\necho hi".utf8)
        let url = try FinderCommandHandler.createNewTemplateFile(in: tempDir, fileName: "script.sh", contents: contents, posixPermissions: 0o755)
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let perms = (attrs[.posixPermissions] as? NSNumber)?.intValue ?? 0
        XCTAssertEqual(perms & 0o777, 0o755)
    }

    func testCreateNewTemplateFileWithEmptyNameThrows() {
        let contents = Data()
        XCTAssertThrowsError(try FinderCommandHandler.createNewTemplateFile(in: tempDir, fileName: "", contents: contents))
    }

    func testCreateNewTemplateFileEmptyContent() throws {
        let url = try FinderCommandHandler.createNewTemplateFile(in: tempDir, fileName: "empty.txt", contents: Data())
        let read = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(read.isEmpty)
    }

    // MARK: - Duplicate File Handling (createUniqueURL through public API)

    func testCreateNewFileWithDuplicateName() throws {
        // Create first file
        let first = try FinderCommandHandler.createNewFile(in: tempDir, fileName: "dup.txt")
        XCTAssertEqual(first.lastPathComponent, "dup.txt")

        // Create second file with same name → should get dedup
        let second = try FinderCommandHandler.createNewFile(in: tempDir, fileName: "dup.txt")
        XCTAssertNotEqual(second.lastPathComponent, "dup.txt",
                          "Should not overwrite; got \(second.lastPathComponent)")
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.path))
    }

    func testCreateNewFolderWithDuplicateName() throws {
        let first = try FinderCommandHandler.createNewFolder(in: tempDir, folderName: "Folder")
        let second = try FinderCommandHandler.createNewFolder(in: tempDir, folderName: "Folder")
        XCTAssertNotEqual(second.lastPathComponent, "Folder")
        var isDir: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.path, isDirectory: &isDir))
        XCTAssertTrue(isDir.boolValue)
    }

    func testCreateNewFileWithMultipleDuplicates() throws {
        var created = Set<String>()
        for _ in 0..<5 {
            let url = try FinderCommandHandler.createNewFile(in: tempDir, fileName: "multi.txt")
            XCTAssertTrue(created.insert(url.lastPathComponent).inserted,
                          "Duplicate path generated: \(url.lastPathComponent)")
        }
    }

    // MARK: - Office Document Creation

    func testCreateNewDocxDocument() throws {
        let url = try FinderCommandHandler.createNewOfficeDocument(in: tempDir, fileName: "document.docx", kind: "docx")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        // Verify it's a valid zip (starts with PK)
        let data = try Data(contentsOf: url)
        XCTAssertEqual(data.prefix(2).map { String(format: "%02X", $0) }.joined(), "504B",
                       "DOCX should be a valid ZIP (PK magic bytes)")
    }

    func testCreateNewXlsxDocument() throws {
        let url = try FinderCommandHandler.createNewOfficeDocument(in: tempDir, fileName: "spreadsheet.xlsx", kind: "xlsx")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        let data = try Data(contentsOf: url)
        XCTAssertEqual(data.prefix(2).map { String(format: "%02X", $0) }.joined(), "504B")
    }

    func testCreateNewPptxDocument() throws {
        let url = try FinderCommandHandler.createNewOfficeDocument(in: tempDir, fileName: "slides.pptx", kind: "pptx")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        let data = try Data(contentsOf: url)
        XCTAssertEqual(data.prefix(2).map { String(format: "%02X", $0) }.joined(), "504B")
    }

    func testCreateNewOfficeDocumentWithInvalidKind() {
        XCTAssertThrowsError(try FinderCommandHandler.createNewOfficeDocument(in: tempDir, fileName: "file.xyz", kind: "xyz"))
    }

    func testCreateNewOfficeDocumentDuplicateFilenames() throws {
        let first = try FinderCommandHandler.createNewOfficeDocument(in: tempDir, fileName: "report.docx", kind: "docx")
        let second = try FinderCommandHandler.createNewOfficeDocument(in: tempDir, fileName: "report.docx", kind: "docx")
        XCTAssertNotEqual(second.lastPathComponent, "report.docx")
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.path))
    }

    // MARK: - iWork Document Creation

    func testCreateNewIWorkDocumentCopiesTemplate() throws {
        // Create a template file first
        let templateURL = tempDir.appendingPathComponent("blank.template")
        try Data("template-content".utf8).write(to: templateURL)

        let url = try FinderCommandHandler.createNewIWorkDocument(in: tempDir, fileName: "output.pages", templateURL: templateURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        let content = try String(contentsOf: url, encoding: .utf8)
        XCTAssertEqual(content, "template-content")
    }

    func testCreateNewIWorkDocumentWithNonexistentTemplate() {
        let missing = tempDir.appendingPathComponent("nonexistent.template")
        XCTAssertThrowsError(try FinderCommandHandler.createNewIWorkDocument(in: tempDir, fileName: "doc.pages", templateURL: missing))
    }

    func testCreateNewIWorkDocumentDuplicateFilenames() throws {
        let templateURL = tempDir.appendingPathComponent("blank.template")
        try Data("t".utf8).write(to: templateURL)

        let first = try FinderCommandHandler.createNewIWorkDocument(in: tempDir, fileName: "doc.pages", templateURL: templateURL)
        let second = try FinderCommandHandler.createNewIWorkDocument(in: tempDir, fileName: "doc.pages", templateURL: templateURL)
        XCTAssertNotEqual(second.lastPathComponent, "doc.pages")
    }

    // MARK: - Pasteboard (error cases only — no simulated pasteboard)

    func testCreateNewTextFileFromPasteboardNoContent() {
        // With no text in the pasteboard, this should throw
        XCTAssertThrowsError(try FinderCommandHandler.createNewTextFileFromPasteboard(in: tempDir))
    }

    func testCreateNewPNGFileFromPasteboardNoImage() {
        XCTAssertThrowsError(try FinderCommandHandler.createNewPNGFileFromPasteboard(in: tempDir))
    }

    // MARK: - Utility Functions

    func testCopyPOSIXPaths() {
        let urls = [
            URL(fileURLWithPath: "/Users/test/Documents/file.txt"),
            URL(fileURLWithPath: "/Users/test/Downloads/photo.jpg")
        ]
        FinderCommandHandler.copyPOSIXPaths(urls)
        let pasteboard = NSPasteboard.general
        let text = pasteboard.string(forType: .string)
        XCTAssertEqual(text, "/Users/test/Documents/file.txt\n/Users/test/Downloads/photo.jpg")
        pasteboard.clearContents()
    }

    func testCopyFilenames() {
        let urls = [
            URL(fileURLWithPath: "/Users/test/file.txt"),
            URL(fileURLWithPath: "/Users/test/photo.jpg")
        ]
        FinderCommandHandler.copyFilenames(urls)
        let pasteboard = NSPasteboard.general
        let text = pasteboard.string(forType: .string)
        XCTAssertEqual(text, "file.txt\nphoto.jpg")
        pasteboard.clearContents()
    }

    func testCanOpenApplicationWithTerminal() {
        // Terminal is always available on macOS
        XCTAssertTrue(FinderCommandHandler.canOpenApplication(bundleIdentifier: "com.apple.Terminal"))
    }

    func testCanOpenApplicationWithNonexistent() {
        XCTAssertFalse(FinderCommandHandler.canOpenApplication(bundleIdentifier: "com.example.nonexistent.12345"))
    }

    func testCanOpenAnyApplication() {
        XCTAssertTrue(FinderCommandHandler.canOpenAnyApplication(bundleIdCandidates: ["com.apple.Terminal"]))
        XCTAssertFalse(FinderCommandHandler.canOpenAnyApplication(bundleIdCandidates: ["com.example.nonexistent.99999"]))
    }

    func testResolveInstalledApplicationURL() {
        let url = FinderCommandHandler.resolveInstalledApplicationURL(bundleIdCandidates: ["com.apple.Terminal"])
        XCTAssertNotNil(url)
        XCTAssertTrue(url!.path.contains("Terminal"))
    }

    func testResolveInstalledApplicationURLWithMultipleCandidates() {
        let url = FinderCommandHandler.resolveInstalledApplicationURL(bundleIdCandidates: [
            "com.example.nonexistent",
            "com.apple.Terminal"
        ])
        XCTAssertNotNil(url)
    }

    func testResolveInstalledApplicationURLWithNonexistent() {
        let url = FinderCommandHandler.resolveInstalledApplicationURL(bundleIdCandidates: ["com.example.nonexistent.88888"])
        XCTAssertNil(url)
    }
}
