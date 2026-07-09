import Foundation

/// Pure Swift ZIP archive writer using "store" method (no compression).
/// Sufficient for OOXML (docx/xlsx/pptx) and other small archives.
/// Avoids the need to spawn /usr/bin/zip from a sandboxed app extension.
struct ZipWriter {
    static func createArchive(from sourceDirectory: URL, to destination: URL) throws {
        let fm = FileManager.default
        var entries: [(name: String, data: Data)] = []

        let enumerator = fm.enumerator(at: sourceDirectory, includingPropertiesForKeys: [.isDirectoryKey])
        while let fileURL = enumerator?.nextObject() as? URL {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: fileURL.path, isDirectory: &isDir), !isDir.boolValue else {
                continue
            }
            let relativePath = String(fileURL.path.dropFirst(sourceDirectory.path.count + 1))
            entries.append((relativePath, try Data(contentsOf: fileURL)))
        }

        // Deterministic output
        entries.sort { $0.name < $1.name }

        var localHeaders = Data()
        var centralDir = Data()
        var offset: UInt32 = 0

        for (name, data) in entries {
            let crc = data.crc32Value
            let nameData = Data(name.utf8)
            let size = UInt32(data.count)

            // Local File Header
            var lfh = Data()
            lfh.append(contentsOf:UInt32(0x04034b50).le)
            lfh.append(contentsOf:UInt16(20).le)    // version needed
            lfh.append(contentsOf:UInt16(0).le)     // flags
            lfh.append(contentsOf:UInt16(0).le)     // compression: store
            lfh.append(contentsOf:UInt16(0).le)     // mod time
            lfh.append(contentsOf:UInt16(0).le)     // mod date
            lfh.append(contentsOf:crc.le)
            lfh.append(contentsOf:size.le)          // compressed size
            lfh.append(contentsOf:size.le)          // uncompressed size
            lfh.append(contentsOf:UInt16(nameData.count).le)
            lfh.append(contentsOf:UInt16(0).le)     // extra field length
            lfh.append(contentsOf:nameData)

            // Central Directory Entry
            var cde = Data()
            cde.append(contentsOf:UInt32(0x02014b50).le)
            cde.append(contentsOf:UInt16(20).le)    // version made by
            cde.append(contentsOf:UInt16(20).le)    // version needed
            cde.append(contentsOf:UInt16(0).le)     // flags
            cde.append(contentsOf:UInt16(0).le)     // compression: store
            cde.append(contentsOf:UInt16(0).le)     // mod time
            cde.append(contentsOf:UInt16(0).le)     // mod date
            cde.append(contentsOf:crc.le)
            cde.append(contentsOf:size.le)          // compressed size
            cde.append(contentsOf:size.le)          // uncompressed size
            cde.append(contentsOf:UInt16(nameData.count).le)
            cde.append(contentsOf:UInt16(0).le)     // extra field length
            cde.append(contentsOf:UInt16(0).le)     // file comment length
            cde.append(contentsOf:UInt16(0).le)     // disk number start
            cde.append(contentsOf:UInt16(0).le)     // internal file attributes
            cde.append(contentsOf:UInt32(0).le)     // external file attributes
            cde.append(contentsOf:offset.le)        // relative offset of local header
            cde.append(contentsOf:nameData)

            localHeaders.append(contentsOf:lfh)
            localHeaders.append(contentsOf:data)
            centralDir.append(contentsOf:cde)

            offset += 30 + UInt32(nameData.count) + size
        }

        // End of Central Directory Record
        var eocd = Data()
        eocd.append(contentsOf:UInt32(0x06054b50).le)
        eocd.append(contentsOf:UInt16(0).le)                     // disk number
        eocd.append(contentsOf:UInt16(0).le)                     // disk with central dir
        eocd.append(contentsOf:UInt16(entries.count).le)         // entries on disk
        eocd.append(contentsOf:UInt16(entries.count).le)         // total entries
        eocd.append(contentsOf:UInt32(centralDir.count).le)      // central dir size
        eocd.append(contentsOf:UInt32(localHeaders.count).le)    // central dir offset
        eocd.append(contentsOf:UInt16(0).le)                     // comment length

        var archive = Data()
        archive.append(contentsOf:localHeaders)
        archive.append(contentsOf:centralDir)
        archive.append(contentsOf:eocd)

        try archive.write(to: destination, options: [.atomic])
    }
}

// MARK: - Little-endian helpers

private extension UInt16 {
    var le: [UInt8] {
        [UInt8(self & 0xFF), UInt8(self >> 8)]
    }
}

private extension UInt32 {
    var le: [UInt8] {
        [UInt8(self & 0xFF), UInt8((self >> 8) & 0xFF), UInt8((self >> 16) & 0xFF), UInt8(self >> 24)]
    }
}

private extension Data {
    /// CRC-32 / IEEE 802.3 (same as zlib's crc32, no external dependency needed).
    var crc32Value: UInt32 {
        var table: [UInt32] = Array(repeating: 0, count: 256)
        for i in 0..<256 {
            var crc = UInt32(i)
            for _ in 0..<8 {
                crc = (crc & 1) != 0 ? 0xedb88320 ^ (crc >> 1) : crc >> 1
            }
            table[i] = crc
        }
        return withUnsafeBytes { ptr in
            var crc: UInt32 = 0xffffffff
            for byte in ptr {
                crc = table[Int(UInt8(truncatingIfNeeded: (crc ^ UInt32(byte)) & 0xff))] ^ (crc >> 8)
            }
            return crc ^ 0xffffffff
        }
    }
}
