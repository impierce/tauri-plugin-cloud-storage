import XCTest
@testable import CloudStorageCore

final class CloudStorageCoreTests: XCTestCase {
  func testNativeValidationMatchesThePublicFileContract() throws {
    try ICloudValidation.file(name: "backup.bin", data: [0, 128, 255])
    try ICloudValidation.file(name: String(repeating: "é", count: 127), data: [])

    for name in ["", " ", ".", "..", "nested/file", "nested\\file", "line\nbreak"] {
      XCTAssertThrowsError(try ICloudValidation.file(name: name, data: [])) { error in
        XCTAssertEqual((error as? CloudStorageFailure)?.code, "invalidArgument")
      }
    }
    XCTAssertThrowsError(try ICloudValidation.file(name: String(repeating: "a", count: 256), data: []))
  }

  func testPayloadAndRequestBoundsAreEnforced() throws {
    try ICloudValidation.payload([UInt8](repeating: 0, count: cloudStorageMaximumFileSize))
    XCTAssertThrowsError(
      try ICloudValidation.payload([UInt8](repeating: 0, count: cloudStorageMaximumFileSize + 1))
    )

    let id = UUID().uuidString
    try ICloudValidation.fileId(id)
    XCTAssertThrowsError(try ICloudValidation.fileId("../not-an-id"))
    for size in [1, 100, 1000] { try ICloudValidation.pageSize(size) }
    for size in [0, 1001] { XCTAssertThrowsError(try ICloudValidation.pageSize(size)) }
    for timeout in [1_000, 60_000, 300_000] { try ICloudValidation.timeout(UInt32(timeout)) }
    for timeout in [0, 999, 300_001] {
      XCTAssertThrowsError(try ICloudValidation.timeout(UInt32(timeout)))
    }
  }

  func testNativeDtosUseCamelCaseWireKeys() throws {
    let data = try JSONEncoder().encode(
      NativeCloudFile(id: "id", name: "backup", size: 3, modifiedAt: "2026-09-08T00:00:00.000Z")
    )
    let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    XCTAssertEqual(object?["modifiedAt"] as? String, "2026-09-08T00:00:00.000Z")
    XCTAssertNil(object?["modified_at"])
  }
}
