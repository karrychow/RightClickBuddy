import AppKit
import Foundation
import os

enum FinderCommandHandler {
    private static var logger: Logger {
        Logger(subsystem: "com.karry.RightClickBuddy", category: "FinderCommandHandler")
    }
    static func copyPOSIXPaths(_ urls: [URL]) {
        let paths = urls.map { $0.path }
        writeToPasteboard(paths.joined(separator: "\n"))
    }

    static func copyFilenames(_ urls: [URL]) {
        let names = urls.map { $0.lastPathComponent }
        writeToPasteboard(names.joined(separator: "\n"))
    }

    static func openInTerminal(_ url: URL) {
        let directoryURL: URL
        if url.hasDirectoryPath {
            directoryURL = url
        } else {
            directoryURL = url.deletingLastPathComponent()
        }

        guard let terminalURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") else {
            return
        }

        let config = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.open([directoryURL], withApplicationAt: terminalURL, configuration: config)
    }

    private static func resolveInstalledApplicationURLImpl(bundleIdCandidates: [String]) -> URL? {
        for bundleId in bundleIdCandidates {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
                return url
            }
        }
        return nil
    }

    static func resolveInstalledApplicationURL(bundleIdCandidates: [String]) -> URL? {
        // NSWorkspace is AppKit; keep it on the main thread to avoid flakiness.
        if Thread.isMainThread {
            return resolveInstalledApplicationURLImpl(bundleIdCandidates: bundleIdCandidates)
        }

        var result: URL?
        DispatchQueue.main.sync {
            result = resolveInstalledApplicationURLImpl(bundleIdCandidates: bundleIdCandidates)
        }
        return result
    }

    private static func resolveInstalledBundleIdentifierImpl(bundleIdCandidates: [String]) -> String? {
        for bundleId in bundleIdCandidates {
            if NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) != nil {
                return bundleId
            }
        }
        return nil
    }

    static func resolveInstalledBundleIdentifier(bundleIdCandidates: [String]) -> String? {
        // NSWorkspace is AppKit; keep it on the main thread to avoid flakiness.
        if Thread.isMainThread {
            return resolveInstalledBundleIdentifierImpl(bundleIdCandidates: bundleIdCandidates)
        }

        var result: String?
        DispatchQueue.main.sync {
            result = resolveInstalledBundleIdentifierImpl(bundleIdCandidates: bundleIdCandidates)
        }
        return result
    }

    static func canOpenApplication(bundleIdentifier: String) -> Bool {
        // NSWorkspace is AppKit; keep it on the main thread to avoid flakiness.
        if Thread.isMainThread {
            return NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) != nil
        }

        var result = false
        DispatchQueue.main.sync {
            result = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) != nil
        }
        return result
    }

    static func canOpenAnyApplication(bundleIdCandidates: [String]) -> Bool {
        resolveInstalledApplicationURL(bundleIdCandidates: bundleIdCandidates) != nil
    }

    static func openInApplication(bundleIdentifier: String, urls: [URL]) throws {
        guard !urls.isEmpty else { return }

        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            throw NSError(domain: "RightClickBuddy", code: 20, userInfo: [NSLocalizedDescriptionKey: "Application not found: \(bundleIdentifier)"])
        }

        let config = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.open(urls, withApplicationAt: appURL, configuration: config)
    }

    static func openInFirstAvailableApplication(bundleIdCandidates: [String], urls: [URL]) throws {
        guard !urls.isEmpty else { return }

        guard let appURL = resolveInstalledApplicationURL(bundleIdCandidates: bundleIdCandidates) else {
            throw NSError(
                domain: "RightClickBuddy",
                code: 21,
                userInfo: [NSLocalizedDescriptionKey: "Application not found: \(bundleIdCandidates.joined(separator: ", "))"]
            )
        }

        // Debug aid: try to surface the chosen app.
        logger.debug("openInFirstAvailableApplication appURL=\(appURL.path, privacy: .public)")

        let config = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.open(urls, withApplicationAt: appURL, configuration: config)
    }

    static func createNewFolder(in directoryURL: URL, folderName: String) throws -> URL {
        let trimmed = folderName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            throw NSError(domain: "RightClickBuddy", code: 12, userInfo: [NSLocalizedDescriptionKey: "Empty folder name"])
        }

        let url = try createUniqueURL(in: directoryURL, fileName: trimmed)

        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        } catch {
            throw NSError(domain: "RightClickBuddy", code: 11, userInfo: [NSLocalizedDescriptionKey: "Failed to create folder: \(error.localizedDescription)"])
        }

        return url
    }

    static func createNewTextFileFromPasteboard(in directoryURL: URL, fileName: String = "Clipboard.txt") throws -> URL {
        let pasteboard = NSPasteboard.general
        guard let text = pasteboard.string(forType: .string) else {
            throw NSError(domain: "RightClickBuddy", code: 30, userInfo: [NSLocalizedDescriptionKey: "Pasteboard has no text"])
        }

        let url = try createUniqueURL(in: directoryURL, fileName: fileName)
        let data = Data(text.utf8)

        let ok = FileManager.default.createFile(atPath: url.path, contents: data, attributes: nil)
        if !ok {
            throw NSError(domain: "RightClickBuddy", code: 31, userInfo: [NSLocalizedDescriptionKey: "Failed to create file"])
        }

        return url
    }

    static func createNewPNGFileFromPasteboard(in directoryURL: URL, fileName: String = "Clipboard.png") throws -> URL {
        let pasteboard = NSPasteboard.general
        guard let image = NSImage(pasteboard: pasteboard) else {
            throw NSError(domain: "RightClickBuddy", code: 32, userInfo: [NSLocalizedDescriptionKey: "Pasteboard has no image"])
        }

        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "RightClickBuddy", code: 33, userInfo: [NSLocalizedDescriptionKey: "Failed to convert image to PNG"])
        }

        let url = try createUniqueURL(in: directoryURL, fileName: fileName)
        do {
            try png.write(to: url, options: [.atomic])
        } catch {
            throw NSError(domain: "RightClickBuddy", code: 34, userInfo: [NSLocalizedDescriptionKey: "Failed to write image: \(error.localizedDescription)"])
        }

        return url
    }

    static func createNewTemplateFile(in directoryURL: URL, fileName: String, contents: Data, posixPermissions: Int? = nil) throws -> URL {
        let trimmed = fileName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            throw NSError(domain: "RightClickBuddy", code: 41, userInfo: [NSLocalizedDescriptionKey: "Empty file name"])
        }

        let url = try createUniqueURL(in: directoryURL, fileName: trimmed)

        var attributes: [FileAttributeKey: Any]? = nil
        if let posixPermissions {
            attributes = [.posixPermissions: posixPermissions]
        }

        let ok = FileManager.default.createFile(atPath: url.path, contents: contents, attributes: attributes)
        if !ok {
            throw NSError(domain: "RightClickBuddy", code: 42, userInfo: [NSLocalizedDescriptionKey: "Failed to create file"])
        }

        return url
    }

    static func createNewFile(in directoryURL: URL, fileName: String) throws -> URL {
        let fileManager = FileManager.default

        let trimmed = fileName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            throw NSError(domain: "RightClickBuddy", code: 2, userInfo: [NSLocalizedDescriptionKey: "Empty file name"])
        }

        // If user didn't provide an extension, default to .txt
        let hasExtension = trimmed.contains(".") && !trimmed.hasSuffix(".")
        let normalizedName = hasExtension ? trimmed : "\(trimmed).txt"

        let url = try createUniqueURL(in: directoryURL, fileName: normalizedName)

        var contents = Data()
        var attributes: [FileAttributeKey: Any]? = nil

        if url.pathExtension.lowercased() == "sh" {
            // Minimal template: shebang only
            contents = Data("#!/bin/zsh\n".utf8)
            // Make it executable
            attributes = [.posixPermissions: 0o755]
        }

        let ok = fileManager.createFile(atPath: url.path, contents: contents, attributes: attributes)
        if !ok {
            throw NSError(domain: "RightClickBuddy", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create file"])
        }

        return url
    }

    static func createNewIWorkDocument(in directoryURL: URL, fileName: String, templateURL: URL) throws -> URL {
        let url = try createUniqueURL(in: directoryURL, fileName: fileName)
        do {
            try FileManager.default.copyItem(at: templateURL, to: url)
        } catch {
            throw NSError(domain: "RightClickBuddy", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to create iWork document: \(error.localizedDescription)"])
        }
        return url
    }

    static func createNewOfficeDocument(in directoryURL: URL, fileName: String, kind: String) throws -> URL {
        // kind: docx / xlsx / pptx
        let url = try createUniqueURL(in: directoryURL, fileName: fileName)

        let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        switch kind {
        case "docx":
            try createDocxPayload(at: tmp)
        case "xlsx":
            try createXlsxPayload(at: tmp)
        case "pptx":
            try createPptxPayload(at: tmp)
        default:
            throw NSError(domain: "RightClickBuddy", code: 4, userInfo: [NSLocalizedDescriptionKey: "Unsupported office kind: \(kind)"])
        }

        // Zip the payload directory into the destination file.
        try zipDirectory(tmp, to: url)

        return url
    }

    private static func zipDirectory(_ directory: URL, to destination: URL) throws {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        task.currentDirectoryURL = directory
        task.arguments = ["-r", destination.path, "."]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        try task.run()
        task.waitUntilExit()

        if task.terminationStatus != 0 {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(decoding: data, as: UTF8.self)
            throw NSError(domain: "RightClickBuddy", code: Int(task.terminationStatus), userInfo: [NSLocalizedDescriptionKey: output.isEmpty ? "zip failed" : output])
        }
    }

    private static func write(_ text: String, to url: URL) throws {
        try text.data(using: .utf8)?.write(to: url, options: [.atomic])
    }

    private static func createDocxPayload(at root: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: root.appendingPathComponent("_rels"), withIntermediateDirectories: true)
        try fm.createDirectory(at: root.appendingPathComponent("word/_rels"), withIntermediateDirectories: true)

        try write("<?xml version=\"1.0\" encoding=\"UTF-8\"?><Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\"><Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/><Default Extension=\"xml\" ContentType=\"application/xml\"/><Override PartName=\"/word/document.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml\"/><Override PartName=\"/word/styles.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml\"/></Types>", to: root.appendingPathComponent("[Content_Types].xml"))

        try write("<?xml version=\"1.0\" encoding=\"UTF-8\"?><Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument\" Target=\"word/document.xml\"/></Relationships>", to: root.appendingPathComponent("_rels/.rels"))

        try write("<?xml version=\"1.0\" encoding=\"UTF-8\"?><Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles\" Target=\"styles.xml\"/></Relationships>", to: root.appendingPathComponent("word/_rels/document.xml.rels"))

        try write("<?xml version=\"1.0\" encoding=\"UTF-8\"?><w:styles xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\"><w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii=\"Calibri\" w:hAnsi=\"Calibri\" w:cs=\"Calibri\"/><w:sz w:val=\"22\"/><w:szCs w:val=\"22\"/></w:rPr></w:rPrDefault><w:pPrDefault><w:pPr><w:spacing w:after=\"0\" w:line=\"240\" w:lineRule=\"auto\"/></w:pPr></w:pPrDefault></w:docDefaults><w:style w:type=\"paragraph\" w:default=\"1\" w:styleId=\"Normal\"><w:name w:val=\"Normal\"/><w:rPr><w:rFonts w:ascii=\"Calibri\" w:hAnsi=\"Calibri\" w:cs=\"Calibri\"/><w:sz w:val=\"22\"/><w:szCs w:val=\"22\"/></w:rPr></w:style></w:styles>", to: root.appendingPathComponent("word/styles.xml"))

        try write("<?xml version=\"1.0\" encoding=\"UTF-8\"?><w:document xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\"><w:body><w:p><w:r><w:t></w:t></w:r></w:p></w:body></w:document>", to: root.appendingPathComponent("word/document.xml"))
    }

    private static func createXlsxPayload(at root: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: root.appendingPathComponent("_rels"), withIntermediateDirectories: true)
        try fm.createDirectory(at: root.appendingPathComponent("xl/_rels"), withIntermediateDirectories: true)
        try fm.createDirectory(at: root.appendingPathComponent("xl/worksheets"), withIntermediateDirectories: true)

        try write("<?xml version=\"1.0\" encoding=\"UTF-8\"?><Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\"><Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/><Default Extension=\"xml\" ContentType=\"application/xml\"/><Override PartName=\"/xl/workbook.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml\"/><Override PartName=\"/xl/worksheets/sheet1.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml\"/><Override PartName=\"/xl/styles.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml\"/></Types>", to: root.appendingPathComponent("[Content_Types].xml"))

        try write("<?xml version=\"1.0\" encoding=\"UTF-8\"?><Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument\" Target=\"xl/workbook.xml\"/></Relationships>", to: root.appendingPathComponent("_rels/.rels"))

        try write("<?xml version=\"1.0\" encoding=\"UTF-8\"?><workbook xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\"><sheets><sheet name=\"Sheet1\" sheetId=\"1\" r:id=\"rId1\"/></sheets></workbook>", to: root.appendingPathComponent("xl/workbook.xml"))

        try write("<?xml version=\"1.0\" encoding=\"UTF-8\"?><Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet\" Target=\"worksheets/sheet1.xml\"/><Relationship Id=\"rId2\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles\" Target=\"styles.xml\"/></Relationships>", to: root.appendingPathComponent("xl/_rels/workbook.xml.rels"))

        try write("<?xml version=\"1.0\" encoding=\"UTF-8\"?><styleSheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\"><fonts count=\"1\"><font><sz val=\"11\"/><name val=\"Calibri\"/><family val=\"2\"/></font></fonts><fills count=\"2\"><fill><patternFill patternType=\"none\"/></fill><fill><patternFill patternType=\"gray125\"/></fill></fills><borders count=\"1\"><border><left/><right/><top/><bottom/><diagonal/></border></borders><cellStyleXfs count=\"1\"><xf numFmtId=\"0\" fontId=\"0\" fillId=\"0\" borderId=\"0\"/></cellStyleXfs><cellXfs count=\"1\"><xf numFmtId=\"0\" fontId=\"0\" fillId=\"0\" borderId=\"0\" xfId=\"0\"/></cellXfs></styleSheet>", to: root.appendingPathComponent("xl/styles.xml"))

        try write("<?xml version=\"1.0\" encoding=\"UTF-8\"?><worksheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\"><sheetData/></worksheet>", to: root.appendingPathComponent("xl/worksheets/sheet1.xml"))
    }

    private static func createPptxPayload(at root: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: root.appendingPathComponent("_rels"), withIntermediateDirectories: true)
        try fm.createDirectory(at: root.appendingPathComponent("ppt/_rels"), withIntermediateDirectories: true)
        try fm.createDirectory(at: root.appendingPathComponent("ppt/slides"), withIntermediateDirectories: true)
        // Keep these empty directories to match MacNewFile payload.
        try fm.createDirectory(at: root.appendingPathComponent("ppt/slideLayouts"), withIntermediateDirectories: true)
        try fm.createDirectory(at: root.appendingPathComponent("ppt/slideMasters"), withIntermediateDirectories: true)

        try write("<?xml version=\"1.0\" encoding=\"UTF-8\"?><Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\"><Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/><Default Extension=\"xml\" ContentType=\"application/xml\"/><Override PartName=\"/ppt/presentation.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.presentationml.presentation.main+xml\"/><Override PartName=\"/ppt/slides/slide1.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.presentationml.slide+xml\"/></Types>", to: root.appendingPathComponent("[Content_Types].xml"))

        try write("<?xml version=\"1.0\" encoding=\"UTF-8\"?><Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument\" Target=\"ppt/presentation.xml\"/></Relationships>", to: root.appendingPathComponent("_rels/.rels"))

        try write("<?xml version=\"1.0\" encoding=\"UTF-8\"?><p:presentation xmlns:p=\"http://schemas.openxmlformats.org/presentationml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\"><p:sldIdLst><p:sldId id=\"256\" r:id=\"rId1\"/></p:sldIdLst></p:presentation>", to: root.appendingPathComponent("ppt/presentation.xml"))

        try write("<?xml version=\"1.0\" encoding=\"UTF-8\"?><Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide\" Target=\"slides/slide1.xml\"/></Relationships>", to: root.appendingPathComponent("ppt/_rels/presentation.xml.rels"))

        try write("<?xml version=\"1.0\" encoding=\"UTF-8\"?><p:sld xmlns:p=\"http://schemas.openxmlformats.org/presentationml/2006/main\"><p:cSld><p:spTree><p:nvGrpSpPr><p:cNvPr id=\"1\" name=\"\"/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr/></p:spTree></p:cSld></p:sld>", to: root.appendingPathComponent("ppt/slides/slide1.xml"))
    }

    private static func createUniqueURL(in directoryURL: URL, fileName: String) throws -> URL {
        let fileManager = FileManager.default

        func splitName(_ name: String) -> (base: String, ext: String?) {
            // Dotfiles like ".env" should be treated as a full basename with no extension.
            if name.hasPrefix("."), !name.dropFirst().contains(".") {
                return (name, nil)
            }

            let url = URL(fileURLWithPath: name)
            let ext = url.pathExtension.isEmpty ? nil : url.pathExtension
            let base = ext == nil ? name : String(name.dropLast(ext!.count + 1))

            // If base becomes empty (e.g. ".env" style names), treat the whole name as basename.
            if base.isEmpty {
                return (name, nil)
            }

            return (base, ext)
        }

        let (base, ext) = splitName(fileName)

        func candidate(_ index: Int?) -> String {
            if let index {
                if let ext {
                    return "\(base) \(index).\(ext)"
                }
                return "\(base) \(index)"
            } else {
                return fileName
            }
        }

        var candidateName = candidate(nil)
        var url = directoryURL.appendingPathComponent(candidateName)
        var i = 2
        while fileManager.fileExists(atPath: url.path) {
            candidateName = candidate(i)
            url = directoryURL.appendingPathComponent(candidateName)
            i += 1
        }

        return url
    }

    private static func writeToPasteboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}
