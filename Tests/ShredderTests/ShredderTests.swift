import XCTest
@testable import Shredder

final class ShredderTests: XCTestCase {
    func testShredsFileAndNestedFolderWithoutFollowingSymlink() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ShredderTests-\(UUID().uuidString)")
        let folder = root.appendingPathComponent("folder")
        let file = folder.appendingPathComponent("secret.txt")
        let outside = root.appendingPathComponent("outside.txt")
        let link = folder.appendingPathComponent("link")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(repeating: 0x41, count: 2_500_000).write(to: file)
        try Data("must survive".utf8).write(to: outside)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        defer { try? FileManager.default.removeItem(at: root) }

        try await ShredEngine.shred([folder]) { _, _ in }

        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path))
        XCTAssertEqual(try Data(contentsOf: outside), Data("must survive".utf8))
    }

    func testCustomSettingsShredFile() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("ShredderCustom-\(UUID().uuidString)")
        try Data(repeating: 0x53, count: 1_100_000).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }

        let settings = ShredSettings(passes: 1, randomEveryPass: true, obfuscateNames: false)
        try await ShredEngine.shred([file], settings: settings) { _, _ in }

        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }
}
