import Foundation
import zlib

enum SpreadsheetError: LocalizedError {
    case invalid(String)

    var errorDescription: String? {
        switch self {
        case .invalid(let message): message
        }
    }
}

/// Reads the saved values in ordinary .xlsx workbooks; never executes formulas.
struct ExcelWorkbook {
    struct Sheet {
        let name: String
        let rows: [[String: String]]
    }

    let sheets: [Sheet]

    init(url: URL) throws {
        let archive = try WorkbookArchive(url: url)
        let workbook = try XMLNode.read(archive.data("xl/workbook.xml"))
        let relationships = try XMLNode.read(archive.data("xl/_rels/workbook.xml.rels"))
        var targets: [String: String] = [:]
        for relation in relationships.children {
            if let id = relation.attributes["Id"], let target = relation.attributes["Target"],
               relation.attributes["TargetMode"] != "External" {
                targets[id] = target
            }
        }
        let strings: [String]
        if archive.contains("xl/sharedStrings.xml") {
            strings = try XMLNode.read(archive.data("xl/sharedStrings.xml")).children.map {
                $0.descendants("t").map(\.text).joined()
            }
        } else {
            strings = []
        }
        var result: [Sheet] = []
        for sheet in workbook.descendants("sheet") {
            guard let id = sheet.attributes["id"], let target = targets[id] else { continue }
            let path = Self.resolve(target, relativeTo: "xl")
            let xml = try XMLNode.read(archive.data(path))
            var hyperlinks: [String: String] = [:]
            let parent = (path as NSString).deletingLastPathComponent
            let filename = (path as NSString).lastPathComponent
            let relationPath = "\(parent)/_rels/\(filename).rels"
            if archive.contains(relationPath) {
                let relations = try XMLNode.read(archive.data(relationPath))
                var urls: [String: String] = [:]
                for relation in relations.children where relation.attributes["Type"]?.hasSuffix("/hyperlink") == true {
                    if let id = relation.attributes["Id"], let target = relation.attributes["Target"] {
                        urls[id] = target
                    }
                }
                for link in xml.descendants("hyperlink") {
                    if let cell = link.attributes["ref"], let id = link.attributes["id"], let url = urls[id] {
                        hyperlinks[cell] = url
                    }
                }
            }
            var rows: [[String: String]] = []
            for row in xml.descendants("row") {
                var values: [String: String] = [:]
                for cell in row.children where cell.name == "c" {
                    guard let reference = cell.attributes["r"] else { continue }
                    let column = String(reference.prefix { $0.isLetter })
                    var value = cell.children.first { $0.name == "v" }?.text ?? ""
                    if cell.attributes["t"] == "s" {
                        guard let index = Int(value), strings.indices.contains(index) else {
                            throw SpreadsheetError.invalid(AppLanguage.string("The spreadsheet contains an invalid text reference."))
                        }
                        value = strings[index]
                    } else if cell.attributes["t"] == "inlineStr" {
                        value = cell.descendants("t").map(\.text).joined()
                    }
                    values[column] = value.trimmingCharacters(in: .whitespacesAndNewlines)
                    // Retain the displayed label as well as the actual hyperlink destination.
                    if let url = hyperlinks[reference] { values[column + ":url"] = url }
                }
                rows.append(values)
            }
            result.append(Sheet(name: sheet.attributes["name"] ?? "", rows: rows))
        }
        sheets = result
    }

    private static func resolve(_ target: String, relativeTo parent: String) -> String {
        let combined = target.hasPrefix("/") ? String(target.dropFirst()) : parent + "/" + target
        var parts: [String] = []
        for part in combined.split(separator: "/") {
            if part == ".." {
                if !parts.isEmpty { parts.removeLast() }
            } else if part != "." {
                parts.append(String(part))
            }
        }
        return parts.joined(separator: "/")
    }
}

private final class XMLNode: NSObject, XMLParserDelegate {
    let name: String
    let attributes: [String: String]
    var text = ""
    var children: [XMLNode] = []
    private var stack: [XMLNode] = []
    private var nodes = 0

    init(name: String = "", attributes: [String: String] = [:]) {
        self.name = name
        self.attributes = attributes
    }

    static func read(_ data: Data) throws -> XMLNode {
        let document = XMLNode()
        document.stack = [document]
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.delegate = document
        guard parser.parse(), let root = document.children.first else {
            throw SpreadsheetError.invalid(AppLanguage.string("The spreadsheet XML could not be read."))
        }
        return root
    }

    func descendants(_ name: String) -> [XMLNode] {
        children.flatMap { ($0.name == name ? [$0] : []) + $0.descendants(name) }
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String: String]) {
        nodes += 1
        guard stack.count < 64, nodes < 500_000 else { parser.abortParsing(); return }
        var attributes: [String: String] = [:]
        for (key, value) in attributeDict {
            attributes[String(key.split(separator: ":").last ?? Substring(key))] = value
        }
        let node = XMLNode(name: String(elementName.split(separator: ":").last ?? Substring(elementName)),
                           attributes: attributes)
        stack.last?.children.append(node)
        stack.append(node)
    }

    func parser(_ parser: XMLParser, foundInternalEntityDeclarationWithName name: String, value: String?) {
        parser.abortParsing()
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        stack.last?.text += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?) {
        if stack.count > 1 { stack.removeLast() }
    }
}

/// Bounded ZIP reader for the XML parts of an XLSX file. No files are extracted to disk.
private struct WorkbookArchive {
    private struct Entry {
        let method: Int
        let size: Int
        let compressedSize: Int
        let offset: Int
        let checksum: UInt32
    }
    private let bytes: Data
    private var entries: [String: Entry] = [:]

    init(url: URL) throws {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= 20_000_000 else {
            throw SpreadsheetError.invalid(AppLanguage.string("This spreadsheet is too large. Please keep it below 20 MB."))
        }
        bytes = try Data(contentsOf: url)
        guard bytes.count >= 22 else { throw Self.invalid }
        var end: Int?
        for index in stride(from: bytes.count - 22, through: max(0, bytes.count - 65_557), by: -1) {
            if try number(index, 4) == 0x06054b50,
               try index + 22 + number(index + 20, 2) == bytes.count {
                end = index
                break
            }
        }
        guard let end, try number(end + 4, 2) == 0,
              try number(end + 6, 2) == 0 else { throw Self.invalid }
        let count = try number(end + 10, 2)
        guard count < 10_000 else { throw Self.invalid }
        var offset = try number(end + 16, 4)
        for _ in 0..<count {
            guard try number(offset, 4) == 0x02014b50,
                  try number(offset + 8, 2) & 1 == 0 else { throw Self.invalid }
            let nameLength = try number(offset + 28, 2)
            let extraLength = try number(offset + 30, 2)
            let commentLength = try number(offset + 32, 2)
            let nameStart = offset + 46
            guard nameStart + nameLength <= bytes.count,
                  let name = String(data: bytes[nameStart..<(nameStart + nameLength)], encoding: .utf8),
                  entries[name] == nil else { throw Self.invalid }
            entries[name] = try Entry(method: number(offset + 10, 2),
                                      size: number(offset + 24, 4),
                                      compressedSize: number(offset + 20, 4),
                                      offset: number(offset + 42, 4),
                                      checksum: UInt32(number(offset + 16, 4)))
            offset = nameStart + nameLength + extraLength + commentLength
        }
        // Bound the total expanded XML, not just each part, before parsing any sheets.
        let expandedSize = entries.filter { $0.key.hasSuffix(".xml") || $0.key.hasSuffix(".rels") }
            .values.reduce(0) { $0 + $1.size }
        guard expandedSize <= 50_000_000 else { throw Self.invalid }
    }

    func contains(_ name: String) -> Bool { entries[name] != nil }

    func data(_ name: String) throws -> Data {
        guard let entry = entries[name], entry.size <= 25_000_000,
              try number(entry.offset, 4) == 0x04034b50 else { throw Self.invalid }
        let start = try entry.offset + 30 + number(entry.offset + 26, 2) + number(entry.offset + 28, 2)
        guard start <= bytes.count, entry.compressedSize <= bytes.count - start else { throw Self.invalid }
        var input = Data(bytes[start..<(start + entry.compressedSize)])
        var output: Data
        if entry.method == 0 {
            output = input
        } else if entry.method == 8 {
            output = Data(count: max(1, entry.size))
            var stream = z_stream()
            guard inflateInit2_(&stream, -MAX_WBITS, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
                throw Self.invalid
            }
            defer { inflateEnd(&stream) }
            let result = input.withUnsafeMutableBytes { source in
                output.withUnsafeMutableBytes { destination in
                    stream.next_in = source.bindMemory(to: Bytef.self).baseAddress
                    stream.avail_in = uInt(entry.compressedSize)
                    stream.next_out = destination.bindMemory(to: Bytef.self).baseAddress
                    stream.avail_out = uInt(max(1, entry.size))
                    return inflate(&stream, Z_FINISH)
                }
            }
            guard result == Z_STREAM_END, stream.total_out == entry.size else { throw Self.invalid }
            output.count = entry.size
        } else {
            throw Self.invalid
        }
        let checksum = output.withUnsafeBytes { buffer in
            crc32(0, buffer.bindMemory(to: Bytef.self).baseAddress, uInt(buffer.count))
        }
        guard output.count == entry.size, UInt32(checksum) == entry.checksum else { throw Self.invalid }
        return output
    }

    private func number(_ offset: Int, _ length: Int) throws -> Int {
        guard offset >= 0, offset <= bytes.count, length <= bytes.count - offset else { throw Self.invalid }
        return (0..<length).reduce(0) { $0 | (Int(bytes[offset + $1]) << (8 * $1)) }
    }

    private static var invalid: SpreadsheetError {
        .invalid(AppLanguage.string("This file is not a supported Excel workbook. Save it as an unencrypted .xlsx file and try again."))
    }
}
