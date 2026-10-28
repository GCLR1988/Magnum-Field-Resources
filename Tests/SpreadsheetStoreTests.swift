import Foundation
import Testing
import zlib
@testable import SpreadsheetReader

@Suite(.serialized)
@MainActor
struct SpreadsheetStoreTests {
    @Test func overlappingRefreshesWaitForOneListing() async {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {
            DropboxService.beforeListing = nil
            try? FileManager.default.removeItem(at: url)
        }
        let store = SpreadsheetStore(snapshotURL: url)
        DropboxService.files = []
        DropboxService.listingAttempts = 0
        var resumeListing: CheckedContinuation<Void, Never>?
        DropboxService.beforeListing = {
            await withCheckedContinuation { resumeListing = $0 }
        }
        let first = Task { await store.sync() }
        while resumeListing == nil { await Task.yield() }
        var secondStarted = false
        var secondFinished = false
        let second = Task {
            secondStarted = true
            await store.sync()
            secondFinished = true
        }
        while !secondStarted { await Task.yield() }
        #expect(!secondFinished)
        #expect(store.isSyncing)
        #expect(DropboxService.listingAttempts == 1)
        resumeListing?.resume()
        await first.value
        await second.value
        #expect(secondFinished)
        #expect(!store.isSyncing)
    }

    @Test func clearingDuringRefreshDoesNotRestoreSnapshot() async {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {
            DropboxService.beforeListing = nil
            try? FileManager.default.removeItem(at: url)
        }
        let store = SpreadsheetStore(snapshotURL: url)
        DropboxService.files = []
        var resumeListing: CheckedContinuation<Void, Never>?
        DropboxService.beforeListing = {
            await withCheckedContinuation { resumeListing = $0 }
        }
        let refresh = Task { await store.sync() }
        while resumeListing == nil { await Task.yield() }
        store.clearCache()
        resumeListing?.resume()
        await refresh.value
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(store.contacts.isEmpty && store.links.isEmpty)
        #expect(store.errorMessage == nil)
        #expect(!store.isSyncing)
        DropboxService.beforeListing = nil
        await store.sync()
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    @Test func failedUpdatesKeepOldDataAndRetryAfterRelaunch() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let contactsURL = directory.appendingPathComponent("directory.xlsx")
        let linksURL = directory.appendingPathComponent("links.xlsx")
        try workbook(rows: [["Name", "Email", "Phone"], ["Old Person", "", "5551234"]]).write(to: contactsURL)
        try workbook(rows: [["Display Name", "URL"], ["Old Link", "https://example.com"]]).write(to: linksURL)
        let snapshotURL = directory.appendingPathComponent("snapshot.json")
        let store = SpreadsheetStore(snapshotURL: snapshotURL)
        let cache = MediaCache.shared
        cache.urls = ["directory": contactsURL, "links": linksURL]
        cache.downloadFails = false
        cache.attempts = 0
        DropboxService.files = files(revision: "1")
        await store.sync()
        #expect(store.contacts.first?.name == "Old Person")
        #expect(store.links.first?.title == "Old Link")
        #expect(store.errorMessage == nil)

        DropboxService.files = files(revision: "2")
        cache.downloadFails = true
        await store.sync()
        #expect(store.errorMessage != nil)
        #expect(store.contacts.first?.name == "Old Person")
        #expect(store.links.first?.title == "Old Link")

        try workbook(rows: [["Name", "Email", "Phone"], ["New Person", "", "5555678"]]).write(to: contactsURL)
        try workbook(rows: [["Display Name", "URL"], ["New Link", "https://example.org"]]).write(to: linksURL)
        cache.downloadFails = false
        let restored = SpreadsheetStore(snapshotURL: snapshotURL)
        await restored.sync()
        #expect(restored.contacts.first?.name == "New Person")
        #expect(restored.links.first?.title == "New Link")
        #expect(restored.errorMessage == nil)
        #expect(cache.attempts == 6)
        await restored.sync()
        #expect(cache.attempts == 6) // Unchanged revisions do not download again.

        restored.clearCache()
        #expect(restored.contacts.isEmpty && restored.links.isEmpty)
        await restored.sync()
        #expect(restored.contacts.first?.name == "New Person")
        #expect(restored.links.first?.title == "New Link")
        #expect(cache.attempts == 8)
    }

    private func files(revision: String) -> [DropboxFileMetadata] {
        [DropboxFileMetadata(id: "directory", name: "Company Directory.xlsx", pathLower: "/directory.xlsx", rev: revision),
         DropboxFileMetadata(id: "links", name: "Useful Links.xlsx", pathLower: "/links.xlsx", rev: revision)]
    }
}

// Tiny synthetic workbooks keep regression checks independent of private company files.
func workbook(rows: [[String]]) -> Data {
    let cells = rows.enumerated().map { row, values in
        "<row>" + values.enumerated().map { column, value in
            let letter = ["A", "B", "C"][column]
            return "<c r=\"\(letter)\(row + 1)\" t=\"inlineStr\"><is><t>\(value)</t></is></c>"
        }.joined() + "</row>"
    }.joined()
    let parts = [
        ("xl/workbook.xml", "<workbook xmlns:r=\"urn:relationships\"><sheets><sheet name=\"Sheet1\" r:id=\"r1\"/></sheets></workbook>"),
        ("xl/_rels/workbook.xml.rels", "<Relationships><Relationship Id=\"r1\" Target=\"worksheets/sheet1.xml\"/></Relationships>"),
        ("xl/worksheets/sheet1.xml", "<worksheet><sheetData>\(cells)</sheetData></worksheet>")
    ]
    var data = Data()
    var central = Data()
    func number(_ value: Int, _ bytes: Int) -> Data {
        Data((0..<bytes).map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) })
    }
    for (path, xml) in parts {
        let name = Data(path.utf8)
        let body = Data(xml.utf8)
        let checksum = body.withUnsafeBytes { crc32(0, $0.bindMemory(to: Bytef.self).baseAddress, uInt($0.count)) }
        let offset = data.count
        data += number(0x04034b50, 4) + number(20, 2) + Data(repeating: 0, count: 8)
        data += number(Int(checksum), 4) + number(body.count, 4) + number(body.count, 4)
        data += number(name.count, 2) + number(0, 2) + name + body
        central += number(0x02014b50, 4) + number(20, 2) + number(20, 2) + Data(repeating: 0, count: 8)
        central += number(Int(checksum), 4) + number(body.count, 4) + number(body.count, 4)
        central += number(name.count, 2) + Data(repeating: 0, count: 12) + number(offset, 4) + name
    }
    let offset = data.count
    data += central
    data += number(0x06054b50, 4) + Data(repeating: 0, count: 4)
    data += number(parts.count, 2) + number(parts.count, 2)
    data += number(central.count, 4) + number(offset, 4) + number(0, 2)
    return data
}
